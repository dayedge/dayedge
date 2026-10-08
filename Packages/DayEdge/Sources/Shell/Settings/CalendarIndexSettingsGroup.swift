import SwiftUI
import Domain
import UI

/// Settings → Calendars › Index: the local calendar index's health, its
/// progress while filling (with Pause / Resume, the footer button's twin)
/// and Reindex, which erases it and rebuilds it from Calendar — confirmed
/// in the row itself.
struct CalendarIndexSettingsGroup: View {
    @Environment(\.themePalette) private var theme

    let activity: CalendarIndexActivity
    @State private var isConfirmingReindex = false

    var body: some View {
        SettingsGroup(
            header: L10n.tr("calendarindexsettingsgroup.index", "Index"),
            footer: L10n.tr("calendarindexsettingsgroup.dayedge.keeps.a.local.bcdcac", "DayEdge keeps a local copy of your calendars for fast browsing and search. ")
                + L10n.tr(
                    "calendarindexsettingsgroup.reindex.rebuilds.it.871720",
                    "Reindex rebuilds it from Calendar: nearby months are back within seconds, other years fill in the background."
                )
        ) {
            statusRow
            if showsProgress { progressRow }
            if let size = activity.databaseSize {
                SettingsRow(title: L10n.tr("calendarindexsettingsgroup.size.on.disk", "Size on disk")) {
                    Text(size.formatted(.byteCount(style: .file)))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(theme.settings.secondaryText)
                }
            }
            if activity.status != .unavailable { reindexRow }
        }
        .onAppear { activity.refreshSize() }
    }

    // MARK: Status

    private var statusRow: some View {
        SettingsRow(title: L10n.tr("calendarindexsettingsgroup.status", "Status"), subtitle: detail) {
            HStack(spacing: 8) {
                StatusDot(color: color)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.settings.secondaryText)
                if showsProgress {
                    Button(activity.isPaused ? L10n.tr(
                        "calendarindexsettingsgroup.resume",
                        "Resume"
                    ) : L10n.tr(
                        "calendarindexsettingsgroup.pause",
                        "Pause"
                    )) { activity.togglePause() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var title: String {
        switch activity.status {
        case .upToDate: L10n.tr("calendarindexsettingsgroup.up.to.date", "Up to date")
        // swiftlint:disable:next void_function_in_ternary - both localization calls return String
        case .indexing: activity.isReindexing ? L10n.tr("calendarindexsettingsgroup.reindexing", "Reindexing…") : L10n.tr("calendarindexsettingsgroup.indexing", "Indexing…")
        case .paused: L10n.tr("calendarindexsettingsgroup.paused", "Paused")
        case .noAccess: L10n.tr("calendarindexsettingsgroup.waiting.for.calendar.access", "Waiting for Calendar access")
        case .temporary: L10n.tr("calendarindexsettingsgroup.temporary", "Temporary")
        case .unavailable: L10n.tr("calendarindexsettingsgroup.unavailable", "Unavailable")
        }
    }

    private var detail: String? {
        switch activity.status {
        case .indexing:
            switch activity.pacing {
            case .normal: return nil
            case .lowPower: return L10n.tr("calendarindexsettingsgroup.slowed.down.while.low.36b378", "Slowed down while Low Power Mode is on.")
            case .thermal: return L10n.tr("calendarindexsettingsgroup.slowed.down.while.your.mac.is.warm", "Slowed down while your Mac is warm.")
            }
        case .paused: return L10n.tr("calendarindexsettingsgroup.visible.and.nearby.67f062", "Visible and nearby months stay current; other years wait.")
        case .temporary: return L10n.tr("calendarindexsettingsgroup.the.usual.location.bfe52c", "The usual location couldn't be opened; this index isn't kept after quitting.")
        case .unavailable: return L10n.tr("calendarindexsettingsgroup.no.index.could.be.637d27", "No index could be opened, so no events can be shown.")
        case .upToDate, .noAccess: return nil
        }
    }

    private var color: Color {
        switch activity.status {
        case .upToDate: theme.settings.granted
        case .indexing: theme.settings.tint
        case .paused, .noAccess: theme.settings.attention
        case .temporary, .unavailable: theme.settings.denied
        }
    }

    // MARK: Progress

    private var showsProgress: Bool {
        activity.status == .indexing || activity.status == .paused
    }

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: activity.fraction ?? 0)
                .progressViewStyle(.linear)
                .controlSize(.small)
                .tint(activity.isPaused ? theme.settings.secondaryText : theme.settings.tint)
            Text(progressText)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.settings.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var progressText: String {
        guard let fraction = activity.fraction else { return L10n.tr("calendarindexsettingsgroup.starting", "Starting…") }
        return L10n.tr("index.progress.months", "\(Int((fraction * 100).rounded()))% · \(activity.coveredChunks) of \(activity.totalChunks) calendar-months")
    }

    // MARK: Reindex

    private var reindexRow: some View {
        SettingsRow(title: L10n.tr("calendarindexsettingsgroup.rebuild", "Rebuild"),
                    subtitle: isConfirmingReindex ? L10n.tr("calendarindexsettingsgroup.erase.the.index.and.fc56a9", "Erase the index and rebuild it from Calendar?") : nil) {
            HStack(spacing: 8) {
                if isConfirmingReindex {
                    Button(L10n.tr("calendarindexsettingsgroup.cancel", "Cancel")) { isConfirmingReindex = false }
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.small)
                    Button(L10n.tr("calendarindexsettingsgroup.reindex", "Reindex")) {
                        isConfirmingReindex = false
                        activity.reindex()
                    }
                    .controlSize(.small)
                    .tint(theme.settings.denied)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(activity.isReindexing ? L10n.tr(
                        "calendarindexsettingsgroup.reindexing",
                        "Reindexing…"
                    ) : L10n.tr(
                        "calendarindexsettingsgroup.reindex",
                        "Reindex…"
                    )) { isConfirmingReindex = true }
                        .controlSize(.small)
                        .disabled(activity.isReindexing)
                }
            }
        }
    }
}
