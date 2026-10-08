import AppKit
import Observation
import SwiftUI
import UI

@MainActor
@Observable
final class CompactMeetingHUDInteractionState {
    var customReminderRequest: UUID?
    var isCustomReminderPresented = false
    var hasFocusedControl = false
}

enum CompactHUDFocus: Hashable {
    case title
    case reminderAction
    case reminderMenu
}

/// The calendar popover's shared surface and text language, compressed into
/// a floating meeting strip.
struct MeetingHUDView: View {
    @Environment(\.themePalette) var theme
    @Environment(\.timeFormat) var timeFormat

    let occurrence: MeetingHUDOccurrence
    let interactionState: CompactMeetingHUDInteractionState
    var onJoin: () -> Void = {}
    /// The single click on the visible reminder icon — "come back exactly
    /// when I need to join." The controller (not this view) decides
    /// whether that means "at the meeting's start" or "in 1 minute,"
    /// since only it knows the real wall-clock time at the moment of the
    /// click; this view only *displays* that distinction (tooltip/label).
    var onSnoozeSmart: () -> Void = {}
    /// Alternative reminder durations, always relative to now.
    var onSnoozeDuration: (TimeInterval) -> Void = { _ in }
    /// Window-controller concern, not a scanning/occurrence concern —
    /// wired directly by `MeetingHUDWindowController` when it builds this
    /// view, not routed through `MeetingHUDController`.
    var onResetPosition: () -> Void = {}
    var onDismiss: () -> Void = {}
    /// Drag-to-reposition, bridged out to `MeetingHUDWindowController`
    /// (which alone can actually move the `NSPanel`) — see `dragLayer`'s
    /// doc comment for why this is a hit-testing z-order trick rather
    /// than `NSWindow.isMovableByWindowBackground`.
    var onDragChanged: () -> Void = {}
    var onDragEnded: () -> Void = {}

    @State var isShowingEventDetail = false
    @State var isShowingCustomReminder = false
    @State var isTitleHovered = false
    @State var isReminderActionHovered = false
    @State var isReminderMenuHovered = false
    @State var lastEventDetailDismissAt: Date = .distantPast
    @FocusState var focusedControl: CompactHUDFocus?

    /// Transparent margin around the visible card. A window clips to its
    /// frame, so the panel must include room for the surface shadow;
    /// the card's own visible size and position remain unchanged.
    static let shadowMargin: CGFloat = 20

    var body: some View {
        cardContent
            .padding(Self.shadowMargin)
            .onChange(of: interactionState.customReminderRequest) { _, request in
                if request != nil { isShowingCustomReminder = true }
            }
            .onChange(of: isShowingCustomReminder) { _, showing in
                interactionState.isCustomReminderPresented = showing
            }
            .onChange(of: occurrence.id) { _, _ in
                isShowingCustomReminder = false
            }
            .onChange(of: focusedControl) { _, focused in
                interactionState.hasFocusedControl = focused != nil
            }
    }

    /// A `ZStack` rather than attaching the drag gesture straight to the
    /// content: the whole HUD is one SwiftUI-hosted `NSView`, so AppKit's
    /// own `isMovableByWindowBackground` can't tell "over Join" from
    /// "over the title text" — it either drags everywhere (breaking
    /// button clicks, which is exactly what happened) or nowhere.
    /// `dragLayer` sits *behind* the real content in z-order instead:
    /// Join/Snooze/More/Dismiss and the event title occlude it at their
    /// own frames and consume clicks normally, while the timing text and
    /// empty space have nothing above them and fall through to the drag
    /// layer's gesture.
    private var cardContent: some View {
        ZStack {
            dragLayer
            HStack(alignment: .center, spacing: 12) {
                leftGroup
                Spacer(minLength: 24)
                rightGroup
            }
            .padding(.leading, 16)
            .padding(.trailing, 15)
            .padding(.vertical, 10)
        }
        .frame(height: 64)
        .frame(minWidth: 480, maxWidth: 640)
        .floatingSurface(radius: FloatingSurface.compactRadius, role: .transient)
        .shadow(color: theme.floatingShadow, radius: 14, x: 0, y: 4)
    }

    private var dragLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                // The window controller reads the pointer in stable AppKit
                // screen coordinates. A zero-distance gesture lets it capture
                // the real mouse-down position before moving the very window
                // that owns this SwiftUI coordinate space; a plain click has
                // zero delta and therefore never visibly moves the HUD.
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onDragChanged() }
                    .onEnded { _ in onDragEnded() }
            )
            .contextMenu {
                resetPositionMenuItem
            }
    }
}
