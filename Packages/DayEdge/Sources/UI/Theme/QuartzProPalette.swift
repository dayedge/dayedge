import SwiftUI

extension ThemePalette {
    /// Quartz Pro: Graphite Pro in daylight. A cool mineral-gray canvas,
    /// near-white working surfaces, graphite type and restrained color —
    /// opaque, flat, hairline-edged, nearly shadowless. Source identity
    /// colors stay vivid; only large fills are calmed.
    ///
    /// Three tones, told apart by luminance alone: the canvas (`canvas`)
    /// dominates; working surfaces (`working` — open search, details,
    /// menus) sit just above it; white is reserved for what's elevated
    /// within them (inner editors, compact controls). Selection and hover
    /// go the other way, a little darker than their surface.
    package static let quartzPro: Self = {
        func hex(_ value: UInt32) -> Color {
            Color(red: Double((value >> 16) & 0xff) / 255,
                  green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
        }
        let canvas = hex(0xececed)
        let working = hex(0xf8f8f9)
        let white = hex(0xffffff)
        let field = hex(0xf2f2f3)
        let hover = hex(0xe5e5e7)
        let selection = hex(0xdedee1)
        let pressed = hex(0xd8d8dc)
        let sidebar = hex(0xe4e4e6)
        let keyline = Color.black.opacity(0.09)
        let divider = Color.black.opacity(0.08)
        let text = hex(0x262628)
        let secondary = hex(0x66666a)
        let muted = hex(0x96969b)
        let accent = hex(0x5a5fc0)
        let red = hex(0xc44b44)
        let green = hex(0x3d8a57)
        let amber = hex(0xb57f27)
        let cyan = hex(0x4a8585)
        var p = Self.appleLight
        p.background = canvas
        p.primaryText = text
        p.secondaryText = secondary
        p.dimmedText = muted
        p.neutralInk = text
        p.calendarHeader.yearText = secondary
        p.calendarHeader.todayTitleText = text
        p.viewSwitcherUsesMaterial = false
        p.selectedWeekBand = .clear
        p.selectedDayFill = selection
        p.selectedDayText = text
        p.todayFill = red
        p.todayText = .white
        p.todayAccent = red
        p.currentTimeCapsule = red
        p.currentTimeText = .white
        p.timelineCapsule = canvas
        p.controlSurface = working
        p.searchSurface = working
        p.workingSurface = working
        p.compactControl = .init(surface: white, hoverSurface: field, keyline: keyline)
        p.semanticActionMix = 0.3
        // Crisp near-white over the agenda: a thin blur under the working
        // tone at ~85%.
        p.persistentChromeMaterial = .ultraThinMaterial
        p.persistentChromeTintOpacity = 0.85
        p.accentRed = red
        p.nativeControlAccent = accent
        p.controlAccent = accent
        p.successGreen = green
        p.holidayTint = red
        p.weekendDayTint = secondary
        p.dotOrange = amber
        p.detailSelectionAccent = secondary
        p.warningYellow = amber
        p.acceptedStatus = green
        p.declinedStatus = red
        p.tentativeStatus = amber
        p.secondaryControl = .init(fill: white, hover: field, pressed: selection, border: keyline, divider: divider)
        p.conflict = .init(busy: red, unconfirmed: amber, free: green)
        p.floatingKeyline = keyline
        p.floatingShadow = .black.opacity(0.06)
        p.weatherTooltipFill = white
        p.eventFillOpacity = 0.14
        p.eventFillSaturation = 0.90
        p.sourcePresentation.tentativeStripeOpacity = 0.32
        p.sourcePresentation.tentativeStripeSaturation = 0.85
        p.tentativeEventFillOpacity = 0.06
        p.chrome = .init(
            rowHover: hover, rowSelection: selection, divider: divider, gridRule: .black.opacity(0.06),
            pressedFill: pressed, badgeFill: selection, mutedText: secondary, placeholderText: muted,
            slotSelected: selection, slotSelectedPressed: pressed, slotHover: hover,
            selectionKeyline: secondary, ongoingEventKeyline: red.opacity(0.6), keyboardEventKeyline: secondary,
            searchScrim: .black.opacity(0.05), searchShadow: .black.opacity(0.08),
            tooltipShadow: .black.opacity(0.14), primaryActionShadow: .black.opacity(0.06))
        p.detail = .init(hoverFill: hex(0xefeff1), activeFill: hex(0xe6e6e9))
        p.content = .init(
            detailSelectionFill: selection, tentativeText: secondary, tentativeMetadata: muted,
            cancelledText: muted, cancelledMetadata: muted.opacity(0.75), cancelledTimelineText: muted,
            cancelledTimelineFill: hover, ongoingIndicator: red, quietMetadata: muted,
            subduedMetadata: secondary.opacity(0.85), detailMetadata: secondary, sourceLabelFallback: text)
        p.editor = .init(text: text, focusRing: .black.opacity(0.22), selectionFill: selection,
            titleText: text, labelText: secondary, placeholderText: muted,
            panelFill: white, fieldFill: field,
            fieldHoverFill: hex(0xededee), fieldFocusedFill: white, fieldKeyline: keyline,
            overlapBusyText: red, overlapUnconfirmedText: amber)
        p.periodHeader.color = secondary
        p.dateTile = .init(
            tileFill: white, tileBorder: keyline, weekdayBand: red, weekdayTint: .white,
            dayTint: text, todayTint: red, monthTint: secondary)
        p.keycap = .init(
            onAccentLargeFill: .white.opacity(0.2), onAccentLargeGlyph: .white.opacity(0.85),
            largeFill: selection, largeGlyph: secondary, compactFill: white, compactStroke: .black.opacity(0.12),
            compactGlyph: secondary, actionLabel: secondary)
        p.settings = .init(
            iconGlyph: .white.opacity(0.9), iconKeyline: keyline, iconDarkening: 0,
            background: canvas, sidebarBackground: sidebar, groupFill: working, groupBorder: keyline,
            divider: divider, primaryText: text, secondaryText: secondary,
            tint: accent, granted: green, denied: red, pending: muted, attention: amber)
        p.tasks = .init(
            attentionTint: red, timelineCardFill: white, timelineCardHoverFill: working,
            timelineCardSelectedFill: selection, timelineCardKeyline: keyline, timelineDueTick: cyan)
        // The user bubble keeps Apple Light's (no more saturated).
        p.chat.jumpButtonBorder = keyline
        p.chat.dateHoverFill = hover
        p.chat.assistantText = text
        p.chat.cardFill = working
        p.chat.cardStroke = keyline
        p.chat.cardHeadline = secondary
        p.chat.destructive = red
        p.chat.receiptDone = green
        p.chat.receiptMuted = muted
        p.chat.chipFill = white
        p.chat.chipHoverFill = field
        p.chat.chipPressedFill = selection
        p.chat.chipBorder = keyline
        p.chat.chipBorderIncreased = secondary
        p.chat.chipLabel = secondary
        p.chat.chipLabelHover = text
        p.chat.chipIcon = muted
        p.chat.chipIconHover = cyan
        p.chat.sendDisabledFill = selection
        p.chat.sendDisabledGlyph = muted
        p.chat.stopFill = selection
        p.chat.stopGlyph = text
        return p
    }()
}
