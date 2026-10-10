import SwiftUI

/// Shared geometry, typography and symbols. Colors live in ThemePalette.
package enum AppTheme {
    package enum ScrollEdge {
        package static let effectHeight: CGFloat = 64
        package static let totalHeight: CGFloat = effectHeight + 16
        package static let blurRadius: CGFloat = 1
        package static let tallHeader = ScrollEdgeDissolve.Configuration(fadeStrength: 3, opaqueHeight: 32, overscan: 8,
                                                                        blurRadius: 4, surfaceRole: .window)
    }

    /// A new event's time: overlaps an accepted event / one not accepted /
    /// free.
    package enum Conflict {
        package static let dotSize: CGFloat = 6
    }

    package enum MeetingTakeover {
        package static let contentWidth: CGFloat = 760
        package static let referenceContentHeight: CGFloat = 630
        package static let iconDiameter: CGFloat = 44
        package static let metadataFontSize: CGFloat = 17
        package static let titleFontSize: CGFloat = 60
        package static let eventTimeFontSize: CGFloat = 22
        package static let statusFontSize: CGFloat = 20
        package static let timerFontSize: CGFloat = 120
        package static let identityTimerGap: CGFloat = 46
        package static let timerActionGap: CGFloat = 42
        package static let actionSlotHeight: CGFloat = 154
        package static let joinWidth: CGFloat = 450
        package static let joinHeight: CGFloat = 72
    }

    package static let cornerRadius: CGFloat = 18
    package static let horizontalPadding: CGFloat = 18

    /// SF Symbols with one meaning across the app.
    package enum Symbol {
        /// A time or time range: event times, a reminder's due time.
        package static let time = "clock"
    }

    /// Keyboard keycaps — shortcut hints, not buttons. One look everywhere;
    /// `large` for the full-screen meeting takeover, `compact` for the
    /// command palette's footer.
    package enum Keycap {
        package static let largeFont = Font.system(size: 13, weight: .medium).monospacedDigit()
        package static let largeRadius: CGFloat = 5

        package static let compactFont = Font.system(size: 10, weight: .medium)
        package static let compactRadius: CGFloat = 4
        package static let compactMinWidth: CGFloat = 18
        package static let compactHeight: CGFloat = 16

        package static let actionLabelFont = Font.system(size: 11)
    }

    /// `CalendarDateTile`: a tiny calendar page.
    package enum DateTile {
        package static let tileWidth: CGFloat = 30
        package static let tileHeight: CGFloat = 35
        package static let tileRadius: CGFloat = 2.5
        package static let weekdayBandHeight: CGFloat = 8.5
        package static let weekdayFont = Font.system(size: 6.5, weight: .semibold)
        package static let dayFont = Font.system(size: 12, weight: .bold).monospacedDigit()
        package static let monthFont = Font.system(size: 9.5)
    }

    /// Search results: the agenda's rows with a tiny calendar date tile in
    /// front, so results from many days stay dense.
    package enum Search {
        /// Tile plus its gap; reserved on every row (tile or not) so event
        /// and task geometry never shifts.
        package static let dateColumnWidth: CGFloat = 33
        /// Preview results sit under Search, indented as its children.
        package static let nestedLeadingInset: CGFloat = 16
        /// Between the Search row and its preview: enough that their
        /// selection surfaces don't touch.
        package static let previewTopGap: CGFloat = 1
        /// Time and its glyphs in a compact result: one width, so every
        /// title starts at the same x.
        package static let timeColumnWidth: CGFloat = 112
        /// The palette preview leaves Join out: time plus a glyph or two.
        package static let timeColumnWidthWithoutJoin: CGFloat = 100
    }

    /// The mixed agenda's row geometry: two fixed anchors, one for every
    /// marker's center and one where all content starts. A task ring and an
    /// event dot differ in size, but neither moves either anchor — so rows
    /// line up whatever mix of events and tasks a day has, and a bigger
    /// marker never pushes the text.
    package enum AgendaRow {
        /// A regular row's content height (time line over title) — what a
        /// still-loading search row reserves.
        package static let placeholderHeight: CGFloat = 33
        /// Every marker's horizontal center, from the row's leading edge —
        /// as far left as keeps a task ring visibly inside a selected row's
        /// rounded surface (which starts 8pt in).
        package static let markerCenterX: CGFloat = 19
        /// Where every row's content (times, titles, metadata) starts: a task
        /// ring's edge sits 7pt from the text, an event dot's 11pt.
        package static let contentLeadingX: CGFloat = 35

        /// Derived — rows never pad by hand. The slot is a layout device
        /// wide enough for the ring's click area, centered on the axis.
        package static let markerSlotWidth: CGFloat = 24
        package static let leadingInset: CGFloat = markerCenterX - markerSlotWidth / 2
        package static let markerToContent: CGFloat = contentLeadingX - leadingInset - markerSlotWidth
        /// Markers are centered on the first text line, this far below the
        /// row content's top.
        package static let firstLineCenter: CGFloat = 8
        /// A task ring's click area: larger than the ring itself (and still
        /// inside a row's rounded highlight).
        package static let ringHitTarget: CGFloat = 22
    }
    package static let dotSize: CGFloat = 4

    package enum Metrics {
        package static let popoverWidth: CGFloat = 420
        package static let popoverPointerInset: CGFloat = AppTheme.cornerRadius + 16
        package static let popoverHeight: CGFloat = 700
        package static let dayWeatherTopGap: CGFloat = PeriodHeader.subtitleToContent
        package static let dayWeatherContentGap: CGFloat = 14
        package static let dayTimelineTopGap: CGFloat = 8
        package static let dayCellHeight: CGFloat = 26
        package static let timelineHourHeight: CGFloat = 60
        package static let timelineHourRuleOffset: CGFloat = 7
        package static let currentTimeCapsuleHeight: CGFloat = 18
        package static let currentTimeCapsuleLeadingInset: CGFloat = 9
        /// Width of the left-hand label column shared by every hour label
        /// (1–23) and the all-day lane's own "all-day" label — sized for
        /// the latter, the longer of the two, so it always sits on one
        /// line at its normal size rather than wrapping or shrinking.
        package static let timelineHorizontalInset: CGFloat = 12
        package static let timelineLabelGutterWidth: CGFloat = 50
        /// The gap between a gutter label and the grid content beside it —
        /// shared so the all-day lane's content lines up exactly with the
        /// hourly timeline's, rather than each recomputing its own offset.
        package static let timelineGutterSpacing: CGFloat = 8
        package static let timelineLabelTrailingEdge = timelineHorizontalInset + timelineLabelGutterWidth
        package static let timelineEventLeadingEdge = timelineLabelTrailingEdge + timelineGutterSpacing
    }

    /// Shared by the month and day headers' secondary line ("22 workdays",
    /// "2 events"): one style, one title→subtitle relationship.
    package enum PeriodHeader {
        package static let font = Font.system(size: 13, weight: .medium)
        package static let titleToSubtitle: CGFloat = 3
        /// Subtitle → whatever the view places below the header.
        package static let subtitleToContent: CGFloat = 10
        package static let subtitleHeight: CGFloat = 16
    }

    /// Ask: the same shell, type and radius family as the command
    /// palette — the composer is the palette's field, moved to the bottom.
    package enum Chat {
        /// Header → first message: the same breathing room other views have.
        package static let headerToContent: CGFloat = 8
        package static let messageSpacing: CGFloat = 14
        /// Between prose and a day's object rows (and between days) inside
        /// one assistant turn.
        package static let partSpacing: CGFloat = 12
        /// The ↓ that jumps back to the newest text, above the composer.
        package static let jumpButtonSize: CGFloat = 30
        package static let jumpButtonGap: CGFloat = 10
        /// The day above a group of referenced events and tasks: small,
        /// quiet, bound tightly to its rows (which add their own padding).
        package static let dateContextFont = Font.system(size: 11.5, weight: .semibold)
        package static let dateContextToRows: CGFloat = 3
        /// Native dates: the day number is the anchor, the rest is quieter.
        package static let dateNumberFont = Font.system(size: 16, weight: .semibold).monospacedDigit()
        package static let dateMetaFont = Font.system(size: 11.5, weight: .medium)
        package static let dateLabelFont = Font.system(size: 11)
        /// A date's own horizontal padding (its hover surface), compensated
        /// so its text lines up with the column it belongs to.
        package static let dateInset: CGFloat = 6
        /// Strip columns: roomier for up to four days, tighter for a week.
        package static let dateColumnWide: CGFloat = 70
        package static let dateColumnNarrow: CGFloat = 50
        /// The user's own words, in their bubble.
        package static let messageFont = Font.system(size: 13)
        /// Assistant prose: calmer than the event and task rows it frames,
        /// so the real objects keep at least equal authority.
        package static let assistantFont = Font.system(size: 12.5)
        package static let userBubbleRadius: CGFloat = 12
        package static let userBubblePaddingH: CGFloat = 11
        package static let userBubblePaddingV: CGFloat = 7
        /// A user turn never spans the full width (~¾ of the content).
        package static let userBubbleMaxWidth: CGFloat = 290

        /// The toolbar row's height: the composer sits in it.
        package static let composerMinHeight: CGFloat = 42
        package static let composerInset: CGFloat = 12
        /// Glyph → text, as in the search field.
        package static let composerIconGap: CGFloat = 10
        /// The composer's width as it arrives from the search field: about
        /// the collapsed field's ("Search" and its magnifier). It widens to
        /// the full row from there.
        package static let composerArrivingWidth: CGFloat = 96
        package static let composerMaxLines = 5
        package static let sendDiameter: CGFloat = 24

        package static let cardRadius: CGFloat = 12
        package static let cardPadding: CGFloat = 12
        package static let cardSpacing: CGFloat = 10
        package static let cardHeadlineFont = Font.system(size: 12, weight: .semibold)
        package static let cardTitleFont = Font.system(size: 13.5, weight: .semibold)
        package static let cardDetailFont = Font.system(size: 12)
        package static let cardFieldLabelWidth: CGFloat = 62
        package static let cardNoteFont = Font.system(size: 11.5)
        // Receipts: one quiet line per change.
        package static let receiptFont = Font.system(size: 12)

        /// Suggestion chips: identical, neutral, monochrome.
        package static let chipHeight: CGFloat = 30
        package static let chipPaddingH: CGFloat = 12
        package static let chipIconGap: CGFloat = 6
        package static let chipSpacing: CGFloat = 8
        /// Chips → composer.
        package static let chipsToComposer: CGFloat = 12
    }

    /// Settings window: the popup's own palette, laid out as System
    /// Settings-style grouped forms.
    package enum Settings {
        package static let groupRadius: CGFloat = 10
        package static let rowHeight: CGFloat = 40
        package static let contentMaxWidth: CGFloat = 560
        package static let sidebarWidth: CGFloat = 210
        /// Height of the (hidden) title bar strip holding the traffic
        /// lights and the back/forward buttons.
        package static let titlebarHeight: CGFloat = 52
    }

    /// Tasks view: completion ring and attention accent.
    package enum Tasks {
        package static let navigatorHeight: CGFloat = 28
        /// The Tasks view's own ring.
        package static let ringSize: CGFloat = 16
        /// A task embedded among events (agenda, day view): a clearly larger
        /// hollow ring than an event's dot, so it still reads as a control.
        package static let embeddedRingSize: CGFloat = 18
        package static let ringStroke: CGFloat = 1.5
        /// Day view: a timed task's card on the hour grid. Its height is its
        /// content's (`TimedTaskCardMetrics`), never a duration.
        package static let timelineCardGap: CGFloat = 2
        package static let timelineCardPaddingH: CGFloat = 10
        package static let timelineCardMinWidth: CGFloat = 150
        /// A lone card is narrower than an event block: a point, not a span.
        package static let timelineCardMaxWidthFraction: CGFloat = 0.8
        package static let timelineCardRadius: CGFloat = 8
        /// The ring's click area inside a card — which has room for more
        /// than a row does.
        package static let timelineCardRingHitTarget: CGFloat = 24
        /// Card top → ring center: the ring sits exactly on the due-time line.
        package static let timelineCardRingCenter: CGFloat = TimedTaskCardMetrics.verticalPadding + AppTheme.AgendaRow.firstLineCenter
        /// Inside a timeline card: ring edge to text.
        package static let timelineCardRingToText: CGFloat = 8
    }

    package enum TextStyle {
        package static let monthTitle = Font.system(size: 26, weight: .bold, design: .rounded)
        package static let weekNumber = Font.system(size: 9, weight: .medium).monospacedDigit()
        package static let weekdayLabel = Font.system(size: 10, weight: .semibold)
        package static let dayNumber = Font.system(size: 13, weight: .medium)
        package static let sectionHeader = Font.system(size: 12, weight: .semibold)
        package static let eventTime = Font.system(size: 12, weight: .regular).monospacedDigit()
        package static let eventTitle = Font.system(size: 13, weight: .semibold)
        package static let eventSubtitle = Font.system(size: 12, weight: .regular)
        package static let footer = Font.system(size: 13, weight: .medium)
    }
}

/// How much room a row takes: `.regular` in the agenda, `.compact`
/// where a row is a reference inside other content (chat).
package enum AgendaRowDensity {
    case regular, compact

    package var verticalPadding: CGFloat {
        switch self {
        case .regular: return 6
        case .compact: return 3
        }
    }
}
