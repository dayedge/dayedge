import Foundation

/// Wall time and sleeping, injected so tests control both.
public protocol IndexClock: Sendable {
    func now() -> Date
    func sleep(for duration: Duration) async throws
}

public struct SystemIndexClock: IndexClock {
    public init() {}
    public func now() -> Date { Date() }
    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
