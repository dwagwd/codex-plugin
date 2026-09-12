import AppKit
import UsageCore
import UsageTransport

let appID = "local.codex.usage-widget"
if CommandLine.arguments.contains("--quit") {
    DistributedNotificationCenter.default().postNotificationName(Notification.Name(appID+".quit"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexUsageWidget", isDirectory: true)
try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
let lockFD = open(support.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
    DistributedNotificationCenter.default().postNotificationName(Notification.Name(appID+".show"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class ColorOverlay: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class CardBackground: NSVisualEffectView {
    private var dragStart: NSPoint?
    private var originalOrigin: NSPoint?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        dragStart = window?.convertPoint(toScreen: event.locationInWindow)
        originalOrigin = window?.frame.origin
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStart, let originalOrigin else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(x: originalOrigin.x+point.x-dragStart.x,
                                      y: originalOrigin.y+point.y-dragStart.y))
    }
    override func mouseUp(with event: NSEvent) { dragStart = nil; originalOrigin = nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let client = UsageClient()
    private var panel: FloatingPanel!
    private var status: NSStatusItem!
    private let defaults = UserDefaults.standard
    private var history = History()
    private var tokenHistory = TokenHistory()
    private var tokenAvailable = false
    private var tokenUpdated: Date?
    private var settings = WidgetSettings()
    private var settingsWindow: SettingsWindowController?
    private var l: L10n { L10n(settings.language) }
    private var items: [WindowItem] = []
    private var codexItems: [WindowItem] = []
    private var bridgeSnapshots: [String: ProviderSnapshot] = [:]
    private var bridgeHistories: [String: History] = [:]
    private var bridgeDates: [String: Date] = [:]
    private var bridgeTick: Timer?
    private var extraLabels: [NSTextField] = []
    private var cachedRates: [String: Rate] = [:]
    private var cachedTokenRate: Rate?
    private var ratesDirty = true
    private var lastFreshness: [Bool] = []
    private let dateFormatter = DateFormatter()
    private var extraItems: [WindowItem] {
        guard settings.options.multiple else { return [] }
        return Array(items.filter { $0.id != current?.id && settings.options.windowIDs.contains($0.id) }.prefix(4))
    }
    private var selectedID: String?
    private var lastUpdate: Date?
    private var errorMessage: String? = "connecting"
    private var sleeping = false
    private var tick: Timer?
    private var collapsed = false
    private var pinned = true
    private var adjustingFrame = false
    private let titleButton = NSButton()
    private let foldButton = NSButton()
    private let settingsButton = NSButton()
    private let valueLabel = NSTextField(labelWithString: "—")
    private let resetLabel = NSTextField(labelWithString: "正在取得用量…")
    private let rateLabel = NSTextField(labelWithString: "近1小時 · 累積資料中")
    private let tokenLabel = NSTextField(labelWithString: "—")
    private let observationLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let colorOverlay = ColorOverlay()
    private var current: WindowItem? { items.first { $0.id == selectedID } ?? items.first }
    private var stale: Bool { errorMessage != nil || lastUpdate.map { Date().timeIntervalSince($0) > self.client.pollInterval + 30 } ?? true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        collapsed = defaults.bool(forKey: "collapsed")
        pinned = defaults.object(forKey: "pinned") as? Bool ?? true
        selectedID = defaults.string(forKey: "selectedWindow")
        if let data = try? Data(contentsOf: support.appendingPathComponent("history.json")),
           let saved = try? JSONDecoder().decode(History.self, from: data) { history = saved }
        if let data = defaults.data(forKey: "settings"), let decoded = try? JSONDecoder().decode(WidgetSettings.self, from: data), decoded.isValid { settings = decoded }
        if let data = try? Data(contentsOf: support.appendingPathComponent("tokens.json")), let saved = try? JSONDecoder().decode(TokenHistory.self, from: data) { tokenHistory = saved }
        client.pollInterval = settings.options.energySaver ? 120 : 60
        setupPanel(); setupStatus()
        client.onResult = { [weak self] response, account in self?.received(response, account: account) }
        client.onTokens = { [weak self] total, account in
            guard let self else { return }
            self.tokenAvailable = total.map { $0.isFinite && $0 >= 0 } ?? false
            self.tokenUpdated = Date()
            self.tokenHistory.record(account: account, total: total, now: Date().timeIntervalSince1970)
            if let data = try? JSONEncoder().encode(self.tokenHistory) { try? data.write(to: support.appendingPathComponent("tokens.json"), options: .atomic) }
            self.ratesDirty = true; self.render(); self.writeStatus()
        }
        client.onFailure = { [weak self] message in
            self?.errorMessage = message; self?.render(); self?.writeStatus()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showPanel), name: Notification.Name(appID+".show"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(quit), name: Notification.Name(appID+".quit"), object: nil)
        startUITimer()
        bridgeTick = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, !self.sleeping else { return }; self.reloadBridges()
        }
        bridgeTick?.tolerance = 3
        RunLoop.main.add(bridgeTick!, forMode: .common)
        reloadBridges()
        showPanel(); client.refresh()
    }
    private func startUITimer() {
        tick?.invalidate()
        guard !sleeping else { return }
        tick = Timer(timeInterval: settings.options.energySaver ? 15 : 1, repeats: true) { [weak self] _ in
            guard let self, !self.sleeping, self.panel.isVisible else { return }
            self.renderCountdown()
        }
        tick?.tolerance = settings.options.energySaver ? 3 : 0.2
        RunLoop.main.add(tick!, forMode: .common)
    }
    private func renderCountdown() {
        let now = Date().timeIntervalSince1970
        let freshness = items.map { isStale($0, now: now) || ($0.window.resetsAt.map { $0 <= now } ?? false) } + [stale]
        if freshness != lastFreshness { render(); return }
        guard !collapsed else { return }
        if let item = current {
            let prefix = isStale(item, now: now) ? l.text("stale") + " · " : (item.window.resetsAt.map { $0 > now } ?? false ? l.text("reset") + " " : "")
            let value = prefix + l.countdown(item.window.resetsAt, now: now)
            if resetLabel.stringValue != value { resetLabel.stringValue = value }
        }
        for (index, item) in extraItems.enumerated() where index < extraLabels.count {
            var lines = extraLabels[index].stringValue.components(separatedBy: "\n")
            guard lines.count == 3 else { continue }
            lines[2] = (isStale(item, now: now) ? l.text("stale") + " · " : "") + l.countdown(item.window.resetsAt, now: now)
            let value = lines.joined(separator: "\n")
            if extraLabels[index].stringValue != value { extraLabels[index].stringValue = value }
        }
    }
    private func applyColors() {
        func color(_ rgb: UsageCore.RGBColor) -> NSColor { NSColor(srgbRed: Double(rgb.red)/255, green: Double(rgb.green)/255, blue: Double(rgb.blue)/255, alpha: 1) }
        let custom = settings.options.customColors
        let foreground = custom ? color(settings.options.foreground) : NSColor.labelColor
        if let bg = panel.contentView as? CardBackground {
            bg.state = custom ? .inactive : .active
            colorOverlay.isHidden = !custom
            colorOverlay.layer?.backgroundColor = color(settings.options.background).cgColor
        }
        for label in [valueLabel, resetLabel, rateLabel, tokenLabel, observationLabel] + extraLabels {
            label.textColor = foreground
        }
        for button in [titleButton, foldButton, settingsButton] { button.contentTintColor = foreground }
    }
    private func providerFor(_ item: WindowItem) -> String? {
        ["claude", "antigravity", "cursor"].first { item.id.hasPrefix($0 + ":") }
    }
    private func sourceUpdate(for item: WindowItem) -> Date? {
        guard let provider = providerFor(item) else { return lastUpdate }
        return bridgeSnapshots[provider].map { Date(timeIntervalSince1970: $0.updatedAt) }
    }
    private func isStale(_ item: WindowItem, now: Double) -> Bool {
        guard let provider = providerFor(item) else { return stale }
        guard let snapshot = bridgeSnapshots[provider] else { return true }
        return now < snapshot.updatedAt || now - snapshot.updatedAt > 300
    }
    private func rebuildItems() {
        items = codexItems
        if settings.options.bridges {
            items += ["claude", "antigravity", "cursor"].flatMap { bridgeSnapshots[$0]?.limits.windows() ?? [] }
        }
        if !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id }
    }
    private func reloadBridges() {
        guard settings.options.bridges else { return }
        var changed = false
        for provider in ["claude", "antigravity", "cursor"] {
            let path = support.appendingPathComponent("providers/" + provider + ".json")
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
                  let date = attrs[.modificationDate] as? Date,
                  (attrs[.size] as? NSNumber)?.intValue ?? Int.max <= 262144,
                  date != bridgeDates[provider] else { continue }
            bridgeDates[provider] = date
            guard let bytes = try? Data(contentsOf: path),
                  let snapshot = try? JSONDecoder().decode(ProviderSnapshot.self, from: bytes),
                  snapshot.isValid(now: Date().timeIntervalSince1970, expectedProvider: provider),
                  snapshot.limits.windows().allSatisfy({ $0.id.hasPrefix(provider + ":") }) else { continue }
            if snapshot.updatedAt == bridgeSnapshots[provider]?.updatedAt { continue }
            bridgeSnapshots[provider] = snapshot
            var history = bridgeHistories[provider] ?? History()
            history.record(account: snapshot.account, items: snapshot.limits.windows(), now: snapshot.updatedAt)
            bridgeHistories[provider] = history; changed = true
        }
        if changed { ratesDirty = true; rebuildItems(); resize(); screensChanged(); render(); writeStatus() }
    }
    private func setupPanel() {
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 128), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Codex Usage"
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovable = true; panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = pinned ? .floating : .normal
        panel.delegate = self
        let bg = CardBackground()
        bg.material = .hudWindow; bg.blendingMode = .behindWindow; bg.state = .active
        bg.wantsLayer = true; bg.layer?.cornerRadius = 14; bg.layer?.masksToBounds = true
        panel.contentView = bg
        colorOverlay.wantsLayer = true; colorOverlay.frame = bg.bounds
        colorOverlay.autoresizingMask = [.width, .height]
        bg.addSubview(colorOverlay)
        titleButton.isBordered = false; titleButton.alignment = .left
        titleButton.font = .systemFont(ofSize: 11, weight: .medium)
        titleButton.target = self; titleButton.action = #selector(selectWindow)
        titleButton.setAccessibilityLabel(l.text("selectWindow"))
        titleButton.toolTip = l.text("dragHint")
        foldButton.isBordered = false; foldButton.target = self; foldButton.action = #selector(toggleCollapsed)
        foldButton.setAccessibilityLabel(l.text("toggleCollapsed"))
        settingsButton.isBordered = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: l.text("settings"))
        settingsButton.target = self; settingsButton.action = #selector(openSettings)
        settingsButton.setAccessibilityLabel(l.text("settings"))
        settingsButton.toolTip = l.text("settings")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.alignment = .right
        resetLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        rateLabel.font = .systemFont(ofSize: 10)
        rateLabel.textColor = .secondaryLabelColor
        tokenLabel.font = .systemFont(ofSize: 11)
        observationLabel.font = .systemFont(ofSize: 9)
        observationLabel.textColor = .secondaryLabelColor
        for label in [valueLabel, resetLabel, rateLabel, tokenLabel, observationLabel] { label.lineBreakMode = .byTruncatingTail }
        progress.style = .bar; progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 100
        for view in [titleButton, foldButton, settingsButton, valueLabel, resetLabel, rateLabel, tokenLabel, observationLabel, progress] { bg.addSubview(view) }
        resize()
        if defaults.object(forKey: "positionX") != nil {
            panel.setFrameOrigin(NSPoint(x: defaults.double(forKey: "positionX"), y: defaults.double(forKey: "positionY")))
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX-panel.frame.width-24, y: screen.visibleFrame.maxY-panel.frame.height-24))
        }
        screensChanged()
    }
    private func setupStatus() {
        if status == nil { status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        status.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "Codex Usage")
        let menu = NSMenu()
        func add(_ name: String, _ action: Selector) {
            let item = NSMenuItem(title: name, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        add(l.text("toggleVisible"), #selector(toggleVisible))
        add(l.text("refresh"), #selector(refresh))
        add(l.text("toggleCollapsed"), #selector(toggleCollapsed))
        add(l.text("pin"), #selector(togglePinned))
        menu.items.last?.state = pinned ? .on : .off
        add(l.text("settings") + "…", #selector(openSettings))
        menu.addItem(.separator())
        add(l.text("quit"), #selector(quit))
        status.menu = menu
    }
    private func resize() {
        adjustingFrame = true
        let old = panel.frame
        let size = collapsed ? NSSize(width: 182, height: 32) : NSSize(width: 260, height: 128 + CGFloat(extraItems.count) * 58)
        panel.setFrame(NSRect(x: old.minX, y: old.maxY-size.height, width: size.width, height: size.height), display: true)
        if collapsed {
            titleButton.frame = NSRect(x: 9, y: 6, width: 70, height: 20)
            valueLabel.frame = NSRect(x: 78, y: 6, width: 49, height: 20)
            settingsButton.frame = NSRect(x: 132, y: 6, width: 20, height: 20)
            foldButton.frame = NSRect(x: 158, y: 6, width: 18, height: 20)
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        } else {
            titleButton.frame = NSRect(x: 10, y: 101, width: 202, height: 20)
            settingsButton.frame = NSRect(x: 216, y: 101, width: 20, height: 20)
            foldButton.frame = NSRect(x: 238, y: 101, width: 18, height: 20)
            valueLabel.frame = NSRect(x: 167, y: 77, width: 78, height: 22)
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            progress.frame = NSRect(x: 12, y: 84, width: 143, height: 8)
            resetLabel.frame = NSRect(x: 12, y: 58, width: 236, height: 17)
            rateLabel.frame = NSRect(x: 12, y: 39, width: 236, height: 17)
            tokenLabel.frame = NSRect(x: 12, y: 21, width: 236, height: 17)
            observationLabel.frame = NSRect(x: 12, y: 5, width: 236, height: 14)
        }
        extraLabels.forEach { $0.removeFromSuperview() }; extraLabels = []
        if !collapsed {
            let offset = CGFloat(extraItems.count) * 58
            for view in [titleButton, settingsButton, foldButton, valueLabel, progress, resetLabel, rateLabel, tokenLabel, observationLabel] {
                view.frame.origin.y += offset
            }
            for index in extraItems.indices {
                let label = NSTextField(wrappingLabelWithString: "")
                label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
                label.maximumNumberOfLines = 3
                label.frame = NSRect(x: 12, y: CGFloat(extraItems.count - index - 1) * 58 + 4, width: 236, height: 52)
                extraLabels.append(label); panel.contentView?.addSubview(label)
            }
        }
        applyColors()
        for view in [progress, resetLabel, rateLabel, tokenLabel, observationLabel] { view.isHidden = collapsed }
        foldButton.title = collapsed ? "⌄" : "−"
        foldButton.toolTip = l.text(collapsed ? "expand" : "collapse")
        adjustingFrame = false
    }
    private func received(_ response: LimitsResponse, account: String) {
        codexItems = response.windows(); rebuildItems(); lastUpdate = Date()
        errorMessage = items.isEmpty ? "noQuota" : nil
        if !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id }
        if tokenHistory.account != account { tokenAvailable = false }
        history.record(account: account, items: codexItems, now: Date().timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: support.appendingPathComponent("history.json"), options: .atomic) }
        ratesDirty = true; resize(); render(); writeStatus()
    }
    private func title(for item: WindowItem) -> String {
        [item.name, item.planType?.capitalized, l.duration(item.window.windowDurationMins)].compactMap { $0 }.joined(separator: " · ")
    }
    private func rateText(_ rate: Rate?, metric: String, unavailable: Bool) -> String {
        let prefix = l.text(metric == "tokens" ? "accountTokens" : "quota")
        if unavailable { return prefix + " · —" }
        guard let rate else { return prefix + " · " + l.text("collecting") }
        let value = rate.value(per: settings.rateUnit)
        let number = metric == "tokens" ? l.compact(value) : l.number(value)
        let unit = metric == "tokens" ? "" : " " + l.text("points")
        return prefix + " · ≈" + number + unit + "/" + l.unit(settings.rateUnit, short: true)
    }
    private func render() {
        guard panel != nil else { return }
        let now = Date().timeIntervalSince1970
        let item = current
        titleButton.title = collapsed ? (item?.name ?? "Codex") : ((item.map { title(for: $0) } ?? "Codex Usage") + " ▾")
        if let used = item?.window.usedPercent, used.isFinite, (0...100).contains(used) {
            valueLabel.stringValue = l.number(used, decimals: 0) + "%"
            progress.doubleValue = used
            valueLabel.textColor = stale ? .secondaryLabelColor : (used >= 90 ? .systemOrange : .labelColor)
        } else { valueLabel.stringValue = "—"; progress.doubleValue = 0 }
        if ratesDirty {
            cachedRates = [:]
            for window in items {
                let provider = providerFor(window)
                cachedRates[window.id] = (provider == nil ? history : bridgeHistories[provider!] ?? History()).rate(for: window.id, now: now, lookback: settings.lookback)
            }
            cachedTokenRate = tokenHistory.rate(now: now, lookback: settings.lookback)
            ratesDirty = false
        }
        let itemStale = item.map { isStale($0, now: now) } ?? stale
        let planRate = item.flatMap { cachedRates[$0.id] }
        let tokenRate = cachedTokenRate
        let tokenStale = stale || !tokenAvailable || (tokenUpdated.map { Date().timeIntervalSince($0) > self.client.pollInterval + 30 } ?? true)
        let sourceUpdated = item.flatMap { sourceUpdate(for: $0) }
        let sourceError = item.flatMap { providerFor($0) } == nil ? errorMessage : nil
        let planUnavailable = itemStale || item?.window.validUsedPercent == nil || (item?.window.resetsAt.map { $0 <= now } ?? false)
        resetLabel.stringValue = itemStale ? (sourceUpdated == nil ? l.text(sourceError ?? "connecting") : l.text("stale") + " · " + l.countdown(item?.window.resetsAt, now: now)) :
            (item?.window.resetsAt.map { $0 > now } ?? false ? l.text("reset") + " " : "") + l.countdown(item?.window.resetsAt, now: now)
        rateLabel.stringValue = rateText(planRate, metric: "quota", unavailable: planUnavailable)
        tokenLabel.stringValue = "Codex · " + rateText(tokenRate, metric: "tokens", unavailable: tokenStale)
        rateLabel.textColor = planUnavailable ? .secondaryLabelColor : .labelColor
        tokenLabel.textColor = tokenStale ? .secondaryLabelColor : .labelColor
        let partial = [planRate, tokenRate].compactMap { $0 }.contains { $0.observedSeconds < settings.lookback }
        observationLabel.stringValue = l.text("last") + " \(settings.intervalValue) " + l.unit(settings.intervalUnit, short: true) + (partial ? " · " + l.text("estimate") : "")
        let formatter = dateFormatter; formatter.locale = l.locale; formatter.dateStyle = .medium; formatter.timeStyle = .medium
        let resetDate = item?.window.resetsAt.map { formatter.string(from: Date(timeIntervalSince1970: $0)) } ?? l.text("unknown")
        let updated = sourceUpdated.map { formatter.string(from: $0) } ?? l.text("unavailable")
        let detail = "\(valueLabel.stringValue) · \(item.map { title(for: $0) } ?? "Codex")\n\(l.text("reset")): \(resetDate)\n\(rateLabel.stringValue)\n\(tokenLabel.stringValue)\n\(observationLabel.stringValue)\n\(l.text("updated")): \(updated)" + (sourceError.map { "\n"+l.text($0) } ?? "")
        panel.contentView?.toolTip = detail; valueLabel.toolTip = detail; resetLabel.toolTip = detail
        rateLabel.toolTip = detail + "\n" + l.text("quotaHelp") + observedDetail(planRate)
        tokenLabel.toolTip = detail + "\n" + l.text("tokensHelp") + observedDetail(tokenRate)
        status?.button?.toolTip = detail
        for (index, extra) in extraItems.enumerated() where index < extraLabels.count {
            let old = isStale(extra, now: now)
            let percent = extra.window.validUsedPercent.map { l.number($0, decimals: 0) + "%" } ?? "—"
            let line = title(for: extra) + " · " + percent
            let rate = rateText(cachedRates[extra.id], metric: "quota", unavailable: old || extra.window.validUsedPercent == nil || (extra.window.resetsAt.map { $0 <= now } ?? false))
            extraLabels[index].stringValue = line + "\n" + rate + "\n" + (old ? l.text("stale") + " · " : "") + l.countdown(extra.window.resetsAt, now: now)
            extraLabels[index].toolTip = extraLabels[index].stringValue + "\n" + l.text("quotaHelp")
        }
        lastFreshness = items.map { isStale($0, now: now) || ($0.window.resetsAt.map { $0 <= now } ?? false) } + [stale]
        applyColors()
    }
    private func observedDetail(_ rate: Rate?) -> String {
        guard let rate else { return "" }
        return "\n" + l.text("observed") + ": " + l.number(rate.observedSeconds/60, decimals: 0) + " " + l.unit(.minute)
    }
    @objc private func openSettings() {
        if let window = settingsWindow, window.window?.isVisible == true { window.present(); return }
        settingsWindow = SettingsWindowController(settings: settings, windows: items.map { ($0.id, title(for: $0)) }) { [weak self] next in
            guard let self else { return }
            self.settings = next
            self.ratesDirty = true
            self.client.pollInterval = next.options.energySaver ? 120 : 60
            self.startUITimer(); self.reloadBridges(); self.rebuildItems()
            self.defaults.set(try? JSONEncoder().encode(next), forKey: "settings")
            self.titleButton.setAccessibilityLabel(self.l.text("selectWindow"))
            self.titleButton.toolTip = self.l.text("dragHint")
            self.foldButton.setAccessibilityLabel(self.l.text("toggleCollapsed"))
            self.settingsButton.setAccessibilityLabel(self.l.text("settings"))
            self.settingsButton.toolTip = self.l.text("settings")
            self.resize(); self.setupStatus(); self.render(); self.writeStatus()
        }
        settingsWindow?.present()
    }
    private func writeStatus() {
        var data: [String: Any] = ["schemaVersion": 2, "stale": current.map { isStale($0, now: Date().timeIntervalSince1970) } ?? stale, "collapsed": collapsed, "pinned": pinned,
            "visible": panel?.isVisible ?? false, "pid": ProcessInfo.processInfo.processIdentifier,
            "windows": items.map { ["id": $0.id, "title": title(for: $0)] },
            "frame": NSStringFromRect(panel?.frame ?? .zero)]
        data["displayedWindows"] = ([current].compactMap { $0 } + extraItems).map(\.id)
        data["energySaver"] = settings.options.energySaver
        data["enabledBridges"] = settings.options.bridges
        data["selectedWindow"] = current?.id
        data["usedPercent"] = current?.window.validUsedPercent
        data["resetsAt"] = current?.window.resetsAt
        data["lastUpdate"] = lastUpdate?.timeIntervalSince1970
        let sourceError = current.flatMap { providerFor($0) } == nil ? errorMessage : nil
        data["errorCode"] = sourceError
        data["error"] = sourceError.map { l.text($0) }
        data["codexErrorCode"] = errorMessage
        data["language"] = settings.language.rawValue
        data["observationSeconds"] = settings.lookback
        data["rateUnit"] = settings.rateUnit.rawValue
        data["planType"] = current?.planType
        if let current, let provider = providerFor(current) { data["lastUpdate"] = bridgeSnapshots[provider]?.updatedAt }
        data["tokenRatePerHour"] = stale || !tokenAvailable ? nil : tokenHistory.rate(now: Date().timeIntervalSince1970, lookback: settings.lookback)?.perHour
        data["tokenAvailable"] = tokenAvailable
        data["ratePerHour"] = current.flatMap { (isStale($0, now: Date().timeIntervalSince1970) || ($0.window.resetsAt.map { $0 <= Date().timeIntervalSince1970 } ?? false)) ? nil : cachedRates[$0.id]?.perHour }
        data["planRatePerHour"] = data["ratePerHour"]
        if let bytes = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? bytes.write(to: support.appendingPathComponent("status.json"), options: .atomic)
        }
    }
    @objc private func selectWindow() {
        let menu = NSMenu()
        for item in items {
            let entry = NSMenuItem(title: title(for: item), action: #selector(chosen(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = item.id; entry.state = item.id == current?.id ? .on : .off; menu.addItem(entry)
        }
        if items.isEmpty { let entry = NSMenuItem(title: l.text("noQuota"), action: nil, keyEquivalent: ""); entry.isEnabled = false; menu.addItem(entry) }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: titleButton)
    }
    @objc private func chosen(_ sender: NSMenuItem) {
        selectedID = sender.representedObject as? String
        defaults.set(selectedID, forKey: "selectedWindow"); resize(); screensChanged(); render(); writeStatus()
    }
    @objc private func toggleCollapsed() {
        collapsed.toggle(); defaults.set(collapsed, forKey: "collapsed"); resize(); screensChanged(); render(); savePosition(); writeStatus()
    }
    @objc private func togglePinned(_ sender: NSMenuItem) {
        pinned.toggle(); defaults.set(pinned, forKey: "pinned"); panel.level = pinned ? .floating : .normal
        sender.state = pinned ? .on : .off; writeStatus()
    }
    @objc private func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil); tick?.invalidate(); writeStatus() } else { showPanel() }
    }
    @objc private func showPanel() { screensChanged(); panel.orderFrontRegardless(); startUITimer(); render(); writeStatus() }
    @objc private func refresh() { client.refresh() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func willSleep() { sleeping = true; tick?.invalidate(); client.suspend(); errorMessage = "asleep"; writeStatus() }
    @objc private func didWake() { sleeping = false; client.resume(); startUITimer(); reloadBridges(); render() }
    @objc private func screensChanged() {
        guard let panel, !NSScreen.screens.isEmpty else { return }
        panel.setFrameOrigin(visibleOrigin(for: panel.frame, screens: NSScreen.screens.map(\.visibleFrame)))
    }
    private func savePosition() {
        defaults.set(panel.frame.minX, forKey: "positionX"); defaults.set(panel.frame.minY, forKey: "positionY")
    }
    func windowDidMove(_ notification: Notification) { if !adjustingFrame { savePosition(); writeStatus() } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return false }
    func applicationWillTerminate(_ notification: Notification) {
        tick?.invalidate(); bridgeTick?.invalidate(); client.stop(); flock(lockFD, LOCK_UN); close(lockFD)
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
