import AppKit
import Observation
import SwiftUI
import Domain
import UI

/// Presentation state for the Tasks view: which sections are expanded, the
/// current section, selection, the open detail popover, and the short "just
/// completed" grace period. The reminders themselves, and every write to
/// them, belong to `TaskRepository`.
/// Sections come from the pure `TaskBuckets`, memoized so a long list isn't
/// re-bucketed on every keypress or redraw.
@MainActor
@Observable
package final class TaskStore {
    package static let sortModeKey = "com.dayedge.tasks.sortMode"
    package static let sortDirectionKey = "com.dayedge.tasks.sortDirection"
    /// How long a just-toggled row stays where it was before moving on.
    package static let lingerDuration: Duration = .milliseconds(1500)

    package struct ScrollRequest: Equatable {
        package let id = UUID()
        package let taskID: String
    }

    /// Scroll a section's header to the top of the document.
    package struct JumpRequest: Equatable {
        package let id = UUID()
        package let sectionID: String
    }

    struct CacheKey: Hashable {
        let revision: Int
        let expanded: Set<String>
        let query: String
        let completedExpanded: Bool
        let completedLimit: Int
        let sortMode: TaskSortMode
        let sortDirection: TaskSortDirection
        let hidden: Set<String>
        let excluded: Set<String>
        let lingering: Set<String>
        let minute: Int
    }

    /// Which lists and smart sections are shown (the footer selector and
    /// Settings drive it). Owned by the app, shared with both.
    package let repository: TaskRepository
    /// Shared with the calendar views, so a task behaves the same there.
    package let actions: TaskActions
    package var listVisibility: SourceVisibilityStore { repository.listVisibility }
    package var lists: [CalendarSource] { repository.lists }
    package var tasks: [TaskItem] { repository.tasks }
    package internal(set) var completedExpanded = false
    package internal(set) var completedLimit = TaskBucketOptions.completedBatch
    /// Sections (by `TaskSection.id`) shown in full. Session-only.
    package internal(set) var expandedSectionIDs: Set<String> = []
    /// The one canonical "where am I" in the document; task selection is
    /// separate. Set by chip clicks, ← / →, and (while the user is
    /// scrolling) the scrollspy.
    package internal(set) var activeSectionID: String?
    package internal(set) var lingeringIDs: Set<String> = []
    package internal(set) var selectedTaskID: String?
    package internal(set) var presentedDetailID: String?
    /// The open task as it was when its details opened — placement only
    /// (see `TaskBuckets`), so edits don't move the row until it closes.
    package internal(set) var placementSnapshots: [String: TaskItem] = [:]
    /// Set only by keyboard navigation, so mouse clicks never re-scroll.
    package internal(set) var scrollRequest: ScrollRequest?
    package internal(set) var jumpRequest: JumpRequest?
    /// Order inside list sections (persisted). Smart for new users.
    package internal(set) var sortMode: TaskSortMode
    package internal(set) var sortDirection: TaskSortDirection
    /// The sort menu (⌘S or the rail's sort button).
    package var isSortMenuPresented = false
    /// Bumped when presentation (not data) changes placement.
    package internal(set) var presentationRevision = 0
    /// Changes whenever data or placement does; part of the section cache key.
    package var revision: Int { repository.revision &+ presentationRevision }
    package var noticeCenter: NoticeCenter? { repository.noticeCenter }
    package var accessStatus: SourceAccessStatus { repository.accessStatus }
    /// Loaded, and the answer was "no access": show the explainer, not an
    /// empty list.
    package var needsAccess: Bool { repository.hasLoaded && repository.accessStatus != .granted }
    /// "Reminders Order" only exists when the source has a manual order.
    package var availableSortModes: [TaskSortMode] {
        TaskSortMode.allCases.filter { $0 != .remindersOrder || repository.supportsManualOrder }
    }
    /// Reminders sorted by their own manual order only exist in some sources.
    package var supportsManualOrder: Bool { repository.supportsManualOrder }

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored var lingerTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var cache: (key: CacheKey, sections: [TaskSection])?

    package convenience init(provider: TaskDataProviding,
                             listVisibility: SourceVisibilityStore? = nil,
                             noticeCenter: NoticeCenter? = nil,
                             defaults: UserDefaults = .standard,
                             calendar: Calendar = .autoupdatingCurrent,
                             now: @escaping () -> Date = { Date() }) {
        self.init(
            repository: TaskRepository(
                provider: provider,
                listVisibility: listVisibility ?? SourceVisibilityStore(kind: .taskLists, defaults: defaults),
                noticeCenter: noticeCenter, defaults: defaults, calendar: calendar, now: now
            ),
            defaults: defaults, calendar: calendar, now: now
        )
    }

    package init(repository: TaskRepository,
                 defaults: UserDefaults = .standard,
                 calendar: Calendar = .autoupdatingCurrent,
                 now: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        let storedMode = defaults.string(forKey: Self.sortModeKey).flatMap(TaskSortMode.init(rawValue:)) ?? .smart
        self.sortMode = storedMode == .remindersOrder && !repository.supportsManualOrder ? .smart : storedMode
        self.sortDirection = defaults.string(forKey: Self.sortDirectionKey).flatMap(TaskSortDirection.init(rawValue:)) ?? .ascending
        self.actions = TaskActions(repository: repository)
    }

    /// First load (later ones happen on their own, see `TaskRepository`).
    package func load() async {
        await repository.loadIfNeeded()
    }

    /// The Tasks tab is now the front one.
    package func activate() async { await repository.activate() }

    package func performAccessAction() async { await repository.performAccessAction() }

    /// A task that just arrived (created from Quick Add): its row settles in
    /// with a brief emphasis.
    package internal(set) var arrivingTaskID: String?
    @ObservationIgnored var arrivalTask: Task<Void, Never>?
}
