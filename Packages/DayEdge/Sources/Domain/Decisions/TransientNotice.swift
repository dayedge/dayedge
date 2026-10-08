import Foundation
import Observation

package enum NoticeStyle: Equatable {
    case information
    case success
    case warning
    case error

    package var defaultDuration: TimeInterval {
        switch self {
        case .information, .success: 3
        case .warning: 4
        case .error: 4.5
        }
    }
}

package struct NoticeAction {
    package let title: String
    package let handler: @MainActor () -> Void

    package init(title: String, handler: @escaping @MainActor () -> Void) {
        self.title = title
        self.handler = handler
    }
}

package struct TransientNotice: Identifiable {
    package let id: UUID
    package let style: NoticeStyle
    package let title: String
    package let message: String?
    package let action: NoticeAction?
    package let duration: TimeInterval

    package init(
        id: UUID = UUID(), style: NoticeStyle, title: String,
        message: String? = nil, action: NoticeAction? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.style = style
        self.title = title
        self.message = message
        self.action = action
        self.duration = duration ?? (action == nil ? style.defaultDuration : 5.5)
    }

    package static func information(title: String, message: String? = nil) -> Self {
        Self(style: .information, title: title, message: message)
    }

    package static func success(title: String, message: String? = nil, action: NoticeAction? = nil) -> Self {
        Self(style: .success, title: title, message: message, action: action)
    }

    package static func warning(title: String, message: String? = nil) -> Self {
        Self(style: .warning, title: title, message: message)
    }

    package static func error(title: String, message: String? = nil) -> Self {
        Self(style: .error, title: title, message: message)
    }

    package var accessibilityAnnouncement: String {
        let content = [title, message].compactMap { $0 }.joined(separator: ". ")
        guard let action else { return content }
        return "\(content). \(action.title) available."
    }

    package func hasSameContent(as other: Self) -> Bool {
        style == other.style && title == other.title && message == other.message && action?.title == other.action?.title
    }
}

/// One notice per the app window. Repeated feedback refreshes its lifetime;
/// a different notice replaces it. The timer is suspended while an action
/// can be reached with the pointer.
@MainActor
@Observable
package final class NoticeCenter {
    package private(set) var currentNotice: TransientNotice?
    private var dismissalTask: Task<Void, Never>?
    private var deadline: Date?
    private var remaining: TimeInterval = 0
    private var isHovering = false

    package init() {}

    package func show(_ notice: TransientNotice) {
        if let currentNotice, currentNotice.hasSameContent(as: notice) {
            self.currentNotice = TransientNotice(
                id: currentNotice.id, style: notice.style, title: notice.title,
                message: notice.message, action: notice.action, duration: notice.duration
            )
        } else {
            currentNotice = notice
        }
        isHovering = false
        remaining = max(notice.duration, 0)
        startTimer()
    }

    package func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        deadline = nil
        isHovering = false
        currentNotice = nil
    }

    package func dismissIfPassive() {
        guard currentNotice?.action == nil else { return }
        dismiss()
    }

    package func setHovering(_ hovering: Bool, for id: UUID) {
        guard currentNotice?.id == id, currentNotice?.action != nil, isHovering != hovering else { return }
        isHovering = hovering
        if hovering {
            if let deadline { remaining = max(deadline.timeIntervalSinceNow, 0) }
            dismissalTask?.cancel()
            dismissalTask = nil
            deadline = nil
        } else {
            startTimer()
        }
    }

    package func performAction(for id: UUID) {
        guard let notice = currentNotice, notice.id == id, let action = notice.action else { return }
        dismiss()
        action.handler()
    }

    private func startTimer() {
        dismissalTask?.cancel()
        guard let id = currentNotice?.id, !isHovering else { return }
        deadline = Date().addingTimeInterval(remaining)
        let delay = remaining
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard !Task.isCancelled, self?.currentNotice?.id == id else { return }
            self?.dismiss()
        }
    }
}
