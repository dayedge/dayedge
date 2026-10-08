import Foundation

/// One conversation's short handles for the objects its tools returned:
/// `E1` (event), `T2` (task), `D3` (day), … The model copies these (reliable and cheap, unlike raw
/// EventKit ids); the app maps them back to stable ids. The same object
/// keeps its handle for the whole conversation, so follow-ups work.
///
/// Tools run off the main actor while the chat reads on it, hence the lock.
package final class ChatReferenceRegistry: @unchecked Sendable {
    package init() {}

    private let lock = NSLock()
    private var referencesByHandle: [String: ChatObjectReference] = [:]
    private var handlesByKey: [String: String] = [:]
    private var eventCount = 0
    private var taskCount = 0
    private var dayCount = 0

    /// The handle for `reference`, minting one the first time. A later call
    /// refreshes the stored snapshot.
    package func handle(for reference: ChatObjectReference) -> String {
        lock.withLock {
            let key = Self.key(for: reference)
            if let handle = handlesByKey[key] {
                referencesByHandle[handle] = reference
                return handle
            }
            let handle: String
            switch reference {
            case .event: eventCount += 1; handle = "E\(eventCount)"
            case .task: taskCount += 1; handle = "T\(taskCount)"
            case .day: dayCount += 1; handle = "D\(dayCount)"
            }
            handlesByKey[key] = handle
            referencesByHandle[handle] = reference
            return handle
        }
    }

    package func reference(for handle: String) -> ChatObjectReference? {
        lock.withLock { referencesByHandle[handle] }
    }

    /// How a handle appears in tool output and in the model's answer.
    package static func token(_ handle: String) -> String { "[[\(handle)]]" }

    private static func key(for reference: ChatObjectReference) -> String {
        switch reference {
        case .event(let event): return "event|\(event.id)|\(event.day.timeIntervalSinceReferenceDate)"
        case .task(let task): return "task|\(task.id)|\(task.day.timeIntervalSinceReferenceDate)"
        case .day(let day): return "day|\(day.day.timeIntervalSinceReferenceDate)"
        }
    }
}
