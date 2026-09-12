import Foundation

/// Sanitized snapshots, never credentials, transcripts, or context-window percentages.
public struct ProviderSnapshot: Codable {
    public let provider: String
    public let account: String
    public let updatedAt: Double
    public let limits: LimitsResponse
    public func isValid(now: Double, expectedProvider: String) -> Bool {
        provider == expectedProvider && ["claude", "antigravity", "cursor"].contains(provider)
        && !account.isEmpty && account.count <= 128
        && updatedAt.isFinite && updatedAt <= now + 5 && updatedAt >= now - 31 * 86400
        && limits.windows().count <= 32
        && limits.windows().allSatisfy { $0.id.count <= 200 && $0.name.count <= 200 }
    }
}
