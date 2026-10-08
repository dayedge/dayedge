import Foundation

/// Source of reminders, kept separate from EventKit's *event* store: Tasks
/// never touches calendars, and the UI never learns where tasks come from.
/// `EventKitTaskProvider` is the real one; the mock backs tests and
/// development. Nothing above this seam imports EventKit.
@MainActor
package protocol TaskDataProviding: AnyObject {
    var accessStatus: SourceAccessStatus { get }
    /// False when the source has no user-defined order, so "Reminders
    /// Order" would only be an arbitrary one.
    var supportsManualOrder: Bool { get }
    /// Opens where the user can change a denied permission, if anywhere.
    func openAccessSettings()
    /// Asks for permission if it hasn't been asked yet; returns the status
    /// afterwards.
    func requestAccess() async -> SourceAccessStatus
    /// Every list, including ones the app ignores, so Settings can offer
    /// them. Empty without access.
    func lists() async -> [CalendarSource]
    func tasks(_ query: TaskQuery) async throws -> [TaskItem]
    /// Applies `change` and returns the task as the source actually stored
    /// it, which can differ (a repeating reminder advancing, normalized
    /// fields). nil when the source can't say.
    func apply(_ change: TaskChange, toTaskID id: String) async throws -> TaskItem?
    func delete(taskID id: String) async throws
    func create(_ draft: TaskDraft) async throws -> TaskItem
    /// Fires (coalesced) whenever the underlying data may have changed,
    /// including through our own writes.
    var changes: AsyncStream<Void> { get }
    /// Brings the task up in the source's own app.
    func revealInSourceApp(taskID id: String)
}
