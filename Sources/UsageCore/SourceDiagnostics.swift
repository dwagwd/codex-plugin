import Foundation

public enum SourceHealth: String, Codable, CaseIterable {
    case fresh
    case stale
    case unavailable
    case error
    case paused
    case disabled
}

public func sourceHealth(lastSuccessAt: Double?, now: Double, staleAfterSeconds: Double,
                         enabled: Bool = true, paused: Bool = false,
                         errorCode: String? = nil) -> SourceHealth {
    guard enabled else { return .disabled }
    if paused { return .paused }
    guard now.isFinite, staleAfterSeconds.isFinite, staleAfterSeconds > 0 else { return .unavailable }
    guard let lastSuccessAt, lastSuccessAt.isFinite else { return errorCode == nil ? .unavailable : .error }
    guard now >= lastSuccessAt else { return .stale }
    return now - lastSuccessAt <= staleAfterSeconds ? .fresh : .stale
}

/// A credential-free operational record for one data source.
public struct SourceDiagnostic: Codable, Equatable {
    public let id: String
    public let health: SourceHealth
    public let enabled: Bool
    public let lastAttemptAt: Double?
    public let lastSuccessAt: Double?
    public let ageSeconds: Double?
    public let staleAfterSeconds: Double
    public let lastErrorCode: String?
    public let consecutiveFailures: Int
    public let nextAttemptAt: Double?

    public init(id: String, health: SourceHealth, enabled: Bool = true,
                lastAttemptAt: Double? = nil, lastSuccessAt: Double? = nil,
                ageSeconds: Double? = nil, staleAfterSeconds: Double,
                lastErrorCode: String? = nil, consecutiveFailures: Int = 0,
                nextAttemptAt: Double? = nil) {
        self.id = id
        self.health = health
        self.enabled = enabled
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.ageSeconds = ageSeconds
        self.staleAfterSeconds = staleAfterSeconds
        self.lastErrorCode = lastErrorCode
        self.consecutiveFailures = max(0, consecutiveFailures)
        self.nextAttemptAt = nextAttemptAt
    }
}
