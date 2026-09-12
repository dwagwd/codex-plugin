import Foundation
import CryptoKit
import UsageCore

// All mutable state is confined to the main queue. No model turns are created.
public final class UsageClient {
    private let overrideExecutable: String?
    private let requestTimeout: Double
    public var pollInterval: Double
    private let retryBase: Double
    public init(executable: String? = nil, requestTimeout: Double = 20, pollInterval: Double = 60, retryBase: Double = 15) {
        overrideExecutable = executable; self.requestTimeout = requestTimeout; self.pollInterval = pollInterval; self.retryBase = retryBase
    }
    public var onResult: ((LimitsResponse, String) -> Void)?
    public var onTokens: ((Double?, String) -> Void)?
    private var pendingTokenAccount: String?
    public var onFailure: ((String) -> Void)?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var generation = UUID()
    private var ready = false
    private var inFlight = false
    private var accountIdentity: String?
    private var timeout: Timer?
    private var retryTimer: Timer?
    private var failures = 0
    private var suspended = false
    private var stopping = false
    private(set) var executable: String?

    public func refresh() {
        guard !suspended, !stopping, !inFlight else { return }
        retryTimer?.invalidate(); retryTimer = nil
        if process == nil { start(); return }
        guard ready else { return }
        inFlight = true
        armTimeout()
        send(["id": 2, "method": "account/read", "params": [:]])
    }
    public func suspend() { suspended = true; disconnect(); retryTimer?.invalidate() }
    public func resume() { suspended = false; refresh() }
    public func stop() {
        stopping = true; retryTimer?.invalidate()
        let child = process
        disconnect()
        // Complete shutdown before the application's run loop exits.
        if let child {
            let deadline = Date().addingTimeInterval(2)
            while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL); child.waitUntilExit() }
        }
    }

    private func start() {
        let env = ProcessInfo.processInfo.environment
        let candidates = [overrideExecutable, env["CODEX_USAGE_CODEX_PATH"],
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            NSHomeDirectory()+"/Applications/Codex.app/Contents/Resources/codex",
            NSHomeDirectory()+"/Applications/ChatGPT.app/Contents/Resources/codex"]
            .compactMap { $0 } + (env["PATH"] ?? "").split(separator: ":").map { String($0)+"/codex" }
            + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            fail("clientMissing"); return
        }
        executable = path
        let p = Process(), stdin = Pipe(), stdout = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["app-server", "--stdio"]
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        p.standardInput = stdin; p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice
        generation = UUID(); let token = generation
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                if data.isEmpty { self.fail("disconnected"); return }
                self.receive(data)
            }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.fail("serviceStopped")
            }
        }
        process = p; input = stdin; output = stdout; inFlight = true
        do {
            try p.run()
            armTimeout()
            send(["id": 1, "method": "initialize", "params": [
                "clientInfo": ["name": "codex_usage_widget", "version": "0.2.0"],
                "capabilities": ["experimentalApi": true]]])
        } catch { fail("startFailed") }
    }
    private func send(_ object: [String: Any]) {
        do {
            var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
            try input?.fileHandleForWriting.write(contentsOf: data)
        } catch { fail("sendFailed") }
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count < 8 * 1024 * 1024 else { fail("responseTooLarge"); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            // Ignore unrelated notifications and server requests: this client only reads account limits.
            guard let id = json["id"] as? Int, (1...4).contains(id) else { continue }
            if id == 4, pendingTokenAccount != nil, json["error"] != nil { finishTokens(nil); continue }
            if json["error"] != nil { fail("readFailed"); return }
            guard let result = json["result"] as? [String: Any] else {
                if id == 4 { finishTokens(nil) }; continue
            }
            switch id {
            case 1:
                timeout?.invalidate(); ready = true; inFlight = false
                send(["method": "initialized"]); refresh()
            case 2:
                let account = result["account"] as? [String: Any]
                let identity = (account?["id"] as? String) ?? (account?["email"] as? String)
                accountIdentity = identity.map { Self.hash($0) }
                send(["id": 3, "method": "account/rateLimits/read", "params": [:]])
            case 3:
                do {
                    let bytes = try JSONSerialization.data(withJSONObject: result)
                    let limits = try JSONDecoder().decode(LimitsResponse.self, from: bytes)
                    guard let identity = limits.accountId.map({ Self.hash($0) }) ?? accountIdentity else {
                        fail("loginRequired"); return
                    }
                    timeout?.invalidate(); failures = 0
                    pendingTokenAccount = identity
                    onResult?(limits, identity)
                    armTimeout()
                    send(["id": 4, "method": "account/usage/read", "params": [:]])
                } catch { fail("invalidQuota") }
            case 4:
                let bytes = try? JSONSerialization.data(withJSONObject: result)
                let usage = bytes.flatMap { try? JSONDecoder().decode(TokenUsageResponse.self, from: $0) }
                finishTokens(usage?.summary?.lifetimeTokens)
            default: break
            }
        }
    }
    private func finishTokens(_ total: Double?) {
        guard let account = pendingTokenAccount else { return }
        pendingTokenAccount = nil; timeout?.invalidate(); inFlight = false
        onTokens?(total, account)
        schedule(after: pollInterval)
    }
    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func armTimeout() {
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: requestTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.pendingTokenAccount != nil {
                self.finishTokens(nil)
                self.disconnect() // Tokens are optional; a token timeout must not invalidate fresh quota.
            } else { self.fail("timeout") }
        }
    }
    private func fail(_ message: String) {
        guard !stopping, !suspended else { return }
        if pendingTokenAccount != nil { finishTokens(nil) }
        disconnect(); failures += 1; onFailure?(message)
        schedule(after: min(300, retryBase * pow(2, Double(min(failures-1, 5)))))
    }
    private func schedule(after interval: Double) {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in self?.refresh() }
    }
    private func disconnect() {
        generation = UUID(); timeout?.invalidate()
        output?.fileHandleForReading.readabilityHandler = nil
        let old = process; old?.terminationHandler = nil
        try? input?.fileHandleForWriting.close()
        if let old, old.isRunning {
            old.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now()+2) {
                if old.isRunning { kill(old.processIdentifier, SIGKILL) }
            }
        }
        pendingTokenAccount = nil; process = nil; input = nil; output = nil; ready = false; inFlight = false; buffer = Data()
    }
}
