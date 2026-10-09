import Foundation

public struct UsageLedgerWindow: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Double?

    public init(id: String, name: String, usedPercent: Double?,
                windowDurationMins: Int?, resetsAt: Double?) {
        self.id = id
        self.name = name
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

/// A successful account-wide sample. Its values are context and are never task-attributed.
public struct UsageLedgerObservation: Codable, Equatable {
    public let capturedAt: Double
    public let accountKey: String?
    public let quotaWindows: [UsageLedgerWindow]
    public let quotaHealth: SourceHealth
    public let quotaErrorCode: String?
    public let accountTokenTotal: Double?
    public let tokenObservedAt: Double?
    public let tokenHealth: SourceHealth
    public let tokenErrorCode: String?

    public init(capturedAt: Double, accountKey: String?, quotaWindows: [UsageLedgerWindow],
                quotaHealth: SourceHealth, quotaErrorCode: String? = nil,
                accountTokenTotal: Double?, tokenObservedAt: Double?, tokenHealth: SourceHealth,
                tokenErrorCode: String? = nil) {
        self.capturedAt = capturedAt
        self.accountKey = accountKey
        self.quotaWindows = quotaWindows
        self.quotaHealth = quotaHealth
        self.quotaErrorCode = quotaErrorCode
        self.accountTokenTotal = accountTokenTotal
        self.tokenObservedAt = tokenObservedAt
        self.tokenHealth = tokenHealth
        self.tokenErrorCode = tokenErrorCode
    }
}

public enum UsageLedgerEventKind: String, Codable, CaseIterable {
    case checkpoint
    case dataGap
    case accountSwitch
    case windowReset
    case sourceCorrection
    case windowUnavailable
    case windowRestored
    case sourceFailure
    case sourceRecovered
}

/// Events contain hashed account keys only. Observation payloads are account-level snapshots.
public struct UsageLedgerEvent: Codable, Equatable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let timestamp: Double
    public let kind: UsageLedgerEventKind
    public let sourceID: String
    public let accountKey: String?
    public let previousAccountKey: String?
    public let windowID: String?
    public let windowName: String?
    public let previousValue: Double?
    public let currentValue: Double?
    public let previousAt: Double?
    public let gapSeconds: Double?
    public let detailCode: String?
    public let observation: UsageLedgerObservation?
    public let previousObservation: UsageLedgerObservation?

    public init(schemaVersion: Int = 1, id: String = UUID().uuidString,
                timestamp: Double, kind: UsageLedgerEventKind,
                sourceID: String, accountKey: String? = nil, previousAccountKey: String? = nil,
                windowID: String? = nil, windowName: String? = nil,
                previousValue: Double? = nil, currentValue: Double? = nil,
                previousAt: Double? = nil, gapSeconds: Double? = nil,
                detailCode: String? = nil, observation: UsageLedgerObservation? = nil,
                previousObservation: UsageLedgerObservation? = nil) {
        self.schemaVersion = max(1, schemaVersion)
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.sourceID = sourceID
        self.accountKey = accountKey
        self.previousAccountKey = previousAccountKey
        self.windowID = windowID
        self.windowName = windowName
        self.previousValue = previousValue
        self.currentValue = currentValue
        self.previousAt = previousAt
        self.gapSeconds = gapSeconds
        self.detailCode = detailCode
        self.observation = observation
        self.previousObservation = previousObservation
    }
}

public struct UsageEventFailureState: Codable, Equatable {
    public let code: String
    public let startedAt: Double
    public let lastEventAt: Double
    public let accountKey: String?

    public init(code: String, startedAt: Double, lastEventAt: Double, accountKey: String? = nil) {
        self.code = code
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
        self.accountKey = accountKey
    }
}

/// Small checkpoint state is saved separately from the append-only JSONL event file.
public struct UsageEventLedgerState: Codable, Equatable {
    public let schemaVersion: Int
    public var latestObservation: UsageLedgerObservation?
    public var lastCheckpointAt: Double?
    public var lastCheckpointObservation: UsageLedgerObservation?
    public var activeFailures: [String: UsageEventFailureState]
    public var unavailableWindowIDs: [String]
    public var eventCount: Int

    public init(schemaVersion: Int = 1, latestObservation: UsageLedgerObservation? = nil, lastCheckpointAt: Double? = nil,
                lastCheckpointObservation: UsageLedgerObservation? = nil,
                activeFailures: [String: UsageEventFailureState] = [:],
                unavailableWindowIDs: [String] = [], eventCount: Int = 0) {
        self.schemaVersion = max(1, schemaVersion)
        self.latestObservation = latestObservation
        self.lastCheckpointAt = lastCheckpointAt
        self.lastCheckpointObservation = lastCheckpointObservation
        self.activeFailures = activeFailures
        self.unavailableWindowIDs = unavailableWindowIDs
        self.eventCount = max(0, eventCount)
    }
}

public struct UsageEventLedger: Equatable {
    public static let recentEventLimit = 300
    public static let defaultCheckpointInterval: Double = 900
    public static let defaultGapThreshold: Double = 300

    public private(set) var recentEvents: [UsageLedgerEvent]
    public private(set) var state: UsageEventLedgerState

    public init(state: UsageEventLedgerState = UsageEventLedgerState(),
                recentEvents: [UsageLedgerEvent] = []) {
        self.state = state
        self.recentEvents = Array(recentEvents.suffix(Self.recentEventLimit))
    }

    /// Records anomalies immediately and a full account checkpoint at least every 15 minutes.
    /// The latest successful sample is updated on each poll for accurate gap detection.
    @discardableResult
    public mutating func observe(_ observation: UsageLedgerObservation,
                                 checkpointInterval: Double = Self.defaultCheckpointInterval,
                                 gapThreshold: Double = Self.defaultGapThreshold) -> [UsageLedgerEvent] {
        guard observation.capturedAt.isFinite, observation.capturedAt >= 0,
              checkpointInterval.isFinite, checkpointInterval > 0,
              gapThreshold.isFinite, gapThreshold >= 0 else { return [] }
        let normalized = normalizedObservation(observation)
        var generated: [UsageLedgerEvent] = []
        let previous = state.latestObservation
        var forceCheckpoint = previous == nil
        var accountChanged = false
        var hasAnomaly = false
        var comparisonUnsafe = false

        if let previous {
            let elapsed = normalized.capturedAt - previous.capturedAt
            if elapsed > gapThreshold {
                generated.append(event(timestamp: normalized.capturedAt, kind: .dataGap,
                                       sourceID: "codex.account", accountKey: normalized.accountKey,
                                       previousAt: previous.capturedAt, gapSeconds: elapsed,
                                       detailCode: "pollGap"))
                forceCheckpoint = true
                hasAnomaly = true
                comparisonUnsafe = true
            } else if elapsed < 0 {
                generated.append(event(timestamp: normalized.capturedAt, kind: .sourceCorrection,
                                       sourceID: "codex.account", accountKey: normalized.accountKey,
                                       previousAt: previous.capturedAt,
                                       detailCode: "clockMovedBackward"))
                forceCheckpoint = true
                hasAnomaly = true
                comparisonUnsafe = true
            }

            if let oldAccount = previous.accountKey, let newAccount = normalized.accountKey,
               oldAccount != newAccount {
                generated.append(event(timestamp: normalized.capturedAt, kind: .accountSwitch,
                                       sourceID: "codex.account", accountKey: newAccount,
                                       previousAccountKey: oldAccount, previousAt: previous.capturedAt))
                state.unavailableWindowIDs = []
                forceCheckpoint = true
                accountChanged = true
                hasAnomaly = true
                comparisonUnsafe = true
            } else if previous.accountKey != normalized.accountKey {
                state.unavailableWindowIDs = []
                forceCheckpoint = true
                comparisonUnsafe = true
            }

            let sameAccount = previous.accountKey != nil && previous.accountKey == normalized.accountKey
            if sameAccount && !accountChanged && elapsed >= 0 {
                let comparison = compareWindows(previous: previous, current: normalized,
                                                timestamp: normalized.capturedAt)
                generated.append(contentsOf: comparison.events)
                state.unavailableWindowIDs = comparison.unavailableWindowIDs
                if !comparison.events.isEmpty {
                    forceCheckpoint = true
                    hasAnomaly = true
                    comparisonUnsafe = true
                }

                if let oldTotal = previous.accountTokenTotal,
                   let newTotal = normalized.accountTokenTotal, newTotal < oldTotal {
                    generated.append(event(timestamp: normalized.capturedAt, kind: .sourceCorrection,
                                           sourceID: "codex.accountTokens", accountKey: normalized.accountKey,
                                           previousValue: oldTotal, currentValue: newTotal,
                                           previousAt: previous.tokenObservedAt ?? previous.capturedAt,
                                           detailCode: "accountTokenCounterDecreased"))
                    forceCheckpoint = true
                    hasAnomaly = true
                    comparisonUnsafe = true
                }
            }
        }

        if normalized.quotaHealth == .fresh, recover("codex.quota", at: normalized.capturedAt,
                                                      accountKey: normalized.accountKey, into: &generated) {
            forceCheckpoint = true
            comparisonUnsafe = true
        }
        if normalized.tokenHealth == .fresh, recover("codex.accountTokens", at: normalized.capturedAt,
                                                      accountKey: normalized.accountKey, into: &generated) {
            forceCheckpoint = true
            comparisonUnsafe = true
        } else if let error = normalized.tokenErrorCode,
                  normalized.tokenHealth == .error || normalized.tokenHealth == .unavailable {
            generated.append(contentsOf: failureEvents(sourceID: "codex.accountTokens",
                                                       timestamp: normalized.capturedAt,
                                                       accountKey: normalized.accountKey,
                                                       errorCode: error, repeatInterval: 900))
        }

        if let lastCheckpoint = state.lastCheckpointAt,
           normalized.capturedAt - lastCheckpoint >= checkpointInterval {
            forceCheckpoint = true
        }
        if hasAnomaly { forceCheckpoint = true }
        if forceCheckpoint {
            let comparison = !comparisonUnsafe && previous?.accountKey == normalized.accountKey &&
                state.lastCheckpointObservation?.accountKey == normalized.accountKey
                ? state.lastCheckpointObservation : nil
            generated.append(event(timestamp: normalized.capturedAt, kind: .checkpoint,
                                   sourceID: "codex.account", accountKey: normalized.accountKey,
                                   observation: normalized, previousObservation: comparison))
            state.lastCheckpointAt = normalized.capturedAt
            state.lastCheckpointObservation = normalized
        }
        state.latestObservation = normalized
        append(generated)
        return generated
    }

    @discardableResult
    public mutating func recordFailure(sourceID: String, timestamp: Double, accountKey: String?,
                                       errorCode: String, repeatInterval: Double = 900) -> [UsageLedgerEvent] {
        let emitted = failureEvents(sourceID: sourceID, timestamp: timestamp, accountKey: accountKey,
                                    errorCode: errorCode, repeatInterval: repeatInterval)
        append(emitted)
        return emitted
    }

    private mutating func failureEvents(sourceID: String, timestamp: Double, accountKey: String?,
                                        errorCode: String, repeatInterval: Double) -> [UsageLedgerEvent] {
        let source = sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = errorCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !code.isEmpty, timestamp.isFinite, timestamp >= 0,
              repeatInterval.isFinite, repeatInterval >= 0 else { return [] }
        if let active = state.activeFailures[source], active.code == code,
           timestamp >= active.lastEventAt, timestamp - active.lastEventAt < repeatInterval {
            return []
        }
        let startedAt = state.activeFailures[source].flatMap { $0.code == code ? $0.startedAt : nil } ?? timestamp
        let next = UsageEventFailureState(code: code, startedAt: startedAt, lastEventAt: timestamp,
                                          accountKey: accountKey)
        state.activeFailures[source] = next
        return [event(timestamp: timestamp, kind: .sourceFailure, sourceID: source,
                      accountKey: accountKey, previousAt: startedAt, detailCode: code)]
    }

    public mutating func restoreRecentEvents(_ events: [UsageLedgerEvent]) {
        recentEvents = Array(events.suffix(Self.recentEventLimit))
    }

    private mutating func recover(_ sourceID: String, at timestamp: Double, accountKey: String?,
                                  into generated: inout [UsageLedgerEvent]) -> Bool {
        guard let failure = state.activeFailures[sourceID] else { return false }
        guard failure.accountKey == nil || accountKey == nil || failure.accountKey == accountKey else {
            state.activeFailures.removeValue(forKey: sourceID)
            return false
        }
        state.activeFailures.removeValue(forKey: sourceID)
        generated.append(event(timestamp: timestamp, kind: .sourceRecovered, sourceID: sourceID,
                               accountKey: accountKey, previousAt: failure.startedAt,
                               detailCode: failure.code))
        return true
    }

    private mutating func append(_ generated: [UsageLedgerEvent]) {
        guard !generated.isEmpty else { return }
        recentEvents.append(contentsOf: generated)
        if recentEvents.count > Self.recentEventLimit {
            recentEvents.removeFirst(recentEvents.count - Self.recentEventLimit)
        }
        state.eventCount += generated.count
    }

    private func event(timestamp: Double, kind: UsageLedgerEventKind, sourceID: String,
                       accountKey: String? = nil, previousAccountKey: String? = nil,
                       windowID: String? = nil, windowName: String? = nil,
                       previousValue: Double? = nil, currentValue: Double? = nil,
                       previousAt: Double? = nil, gapSeconds: Double? = nil,
                       detailCode: String? = nil,
                       observation: UsageLedgerObservation? = nil,
                       previousObservation: UsageLedgerObservation? = nil) -> UsageLedgerEvent {
        UsageLedgerEvent(timestamp: timestamp, kind: kind, sourceID: sourceID,
                         accountKey: accountKey, previousAccountKey: previousAccountKey,
                         windowID: windowID, windowName: windowName,
                         previousValue: previousValue, currentValue: currentValue,
                         previousAt: previousAt, gapSeconds: gapSeconds,
                         detailCode: detailCode, observation: observation,
                         previousObservation: previousObservation)
    }

    private func normalizedObservation(_ observation: UsageLedgerObservation) -> UsageLedgerObservation {
        let windows = observation.quotaWindows.compactMap { window -> UsageLedgerWindow? in
            let id = window.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            let used = window.usedPercent.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
            let reset = window.resetsAt.flatMap { $0.isFinite ? $0 : nil }
            return UsageLedgerWindow(id: id,
                                     name: window.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                     usedPercent: used, windowDurationMins: window.windowDurationMins,
                                     resetsAt: reset)
        }
        let account = observation.accountKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAccount = account?.isEmpty == true ? nil : account
        let total = observation.accountTokenTotal.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let tokenTime = observation.tokenObservedAt.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        return UsageLedgerObservation(capturedAt: observation.capturedAt, accountKey: cleanAccount,
                                      quotaWindows: windows, quotaHealth: observation.quotaHealth,
                                      quotaErrorCode: observation.quotaErrorCode,
                                      accountTokenTotal: total, tokenObservedAt: tokenTime,
                                      tokenHealth: observation.tokenHealth,
                                      tokenErrorCode: observation.tokenErrorCode)
    }

    private func compareWindows(previous: UsageLedgerObservation, current: UsageLedgerObservation,
                                timestamp: Double) -> (events: [UsageLedgerEvent], unavailableWindowIDs: [String]) {
        let oldWindows = Dictionary(previous.quotaWindows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newWindows = Dictionary(current.quotaWindows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var unavailable = Set(state.unavailableWindowIDs)
        var generated: [UsageLedgerEvent] = []

        for id in oldWindows.keys.sorted() where newWindows[id] == nil {
            guard let old = oldWindows[id] else { continue }
            if unavailable.insert(id).inserted {
                generated.append(event(timestamp: timestamp, kind: .windowUnavailable,
                                       sourceID: "codex.quota", accountKey: current.accountKey,
                                       windowID: id, windowName: old.name,
                                       previousValue: old.usedPercent, previousAt: previous.capturedAt,
                                       detailCode: "windowMissing"))
            }
        }
        for id in newWindows.keys.sorted() {
            guard let nowWindow = newWindows[id] else { continue }
            let old = oldWindows[id]
            if nowWindow.usedPercent == nil {
                if unavailable.insert(id).inserted, let old {
                    generated.append(event(timestamp: timestamp, kind: .windowUnavailable,
                                           sourceID: "codex.quota", accountKey: current.accountKey,
                                           windowID: id, windowName: nowWindow.name,
                                           previousValue: old.usedPercent, previousAt: previous.capturedAt,
                                           detailCode: "invalidWindowValue"))
                }
                continue
            }
            if unavailable.remove(id) != nil {
                generated.append(event(timestamp: timestamp, kind: .windowRestored,
                                       sourceID: "codex.quota", accountKey: current.accountKey,
                                       windowID: id, windowName: nowWindow.name,
                                       previousValue: old?.usedPercent,
                                       currentValue: nowWindow.usedPercent, detailCode: "windowReturned"))
            }
            guard let old, let previousUsed = old.usedPercent,
                  let currentUsed = nowWindow.usedPercent else { continue }
            let resetChanged = materiallyDifferent(old.resetsAt, nowWindow.resetsAt)
            let durationChanged = old.windowDurationMins != nowWindow.windowDurationMins
            if currentUsed < previousUsed {
                let resetBoundaryPassed = old.resetsAt.map { $0 <= timestamp } ?? false
                let kind: UsageLedgerEventKind = (resetChanged || resetBoundaryPassed) ? .windowReset : .sourceCorrection
                generated.append(event(timestamp: timestamp, kind: kind, sourceID: "codex.quota",
                                       accountKey: current.accountKey, windowID: id,
                                       windowName: nowWindow.name, previousValue: previousUsed,
                                       currentValue: currentUsed, previousAt: previous.capturedAt,
                                       detailCode: kind == .windowReset ? "usageDroppedAtBoundary" : "usageValueDecreased"))
            } else if resetChanged {
                generated.append(event(timestamp: timestamp, kind: .windowReset,
                                       sourceID: "codex.quota", accountKey: current.accountKey,
                                       windowID: id, windowName: nowWindow.name,
                                       previousValue: previousUsed, currentValue: currentUsed,
                                       previousAt: previous.capturedAt, detailCode: "resetBoundaryChanged"))
            } else if durationChanged {
                generated.append(event(timestamp: timestamp, kind: .sourceCorrection,
                                       sourceID: "codex.quota", accountKey: current.accountKey,
                                       windowID: id, windowName: nowWindow.name,
                                       previousValue: previousUsed, currentValue: currentUsed,
                                       previousAt: previous.capturedAt, detailCode: "windowDurationChanged"))
            }
        }
        return (generated, unavailable.sorted())
    }

    private func materiallyDifferent(_ first: Double?, _ second: Double?) -> Bool {
        switch (first, second) {
        case (nil, nil): return false
        case let (a?, b?): return abs(a - b) > 60
        default: return true
        }
    }
}
