import SwiftUI

extension ThemePalette {
    /// Graphite Pro: near-black neutral surfaces and restrained violet accents,
    /// inspired by the supplied Linear dark reference. Source identity colors stay vivid.
    ///
    /// Three tones, told apart by luminance alone: the canvas (`base`) is
    /// the darkest and dominates; working surfaces (`working` — open
    /// search, details, menus) sit visibly above it; controls, hover and
    /// selection (`raised`, `selection`) above those.
    package static let graphitePro: Self = {
        func hex(_ value: UInt32) -> Color {
            Color(red: Double((value >> 16) & 0xff) / 255,
                  green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
        }
        let base = hex(0x111214)
        let deep = hex(0x0c0d0e)
        let surface = hex(0x18191c)
        let working = hex(0x1a1b1e)
        let raised = hex(0x232428)
        let selection = hex(0x2a2b30)
        let border = hex(0x303137)
        let text = hex(0xeeeff1)
        let secondary = hex(0xa4a5ad)
        let muted = hex(0x85868f)
        let accent = hex(0x8b8bd5)
        let red = hex(0xcd7b80)
        let green = hex(0x87b894)
        let amber = hex(0xd2b577)
        let cyan = hex(0x88aaa9)
        let actionFill = accent.mix(with: .black, by: 0.42)
        let filledRed = red.mix(with: .black, by: 0.30)
        var p = Self.appleDark
        p.background = base
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
        p.todayText = deep
        p.todayAccent = red
        p.currentTimeCapsule = red
        p.currentTimeText = deep
        p.timelineCapsule = base
        p.controlSurface = working
        p.searchSurface = working
        p.workingSurface = working
        p.compactControl = .init(surface: raised, hoverSurface: selection, keyline: .white.opacity(0.06))
        p.semanticActionMix = 0.35
        // Smoked graphite over the agenda, not glass: a thin blur under the
        // working tone at ~80%.
        p.persistentChromeMaterial = .ultraThinMaterial
        p.persistentChromeTintOpacity = 0.8
        p.accentRed = red
        p.destructiveRed = filledRed
        p.nativeControlAccent = actionFill
        p.controlAccent = actionFill
        p.successGreen = green
        p.holidayTint = red
        p.weekendDayTint = secondary
        p.dotOrange = amber
        p.detailSelectionAccent = secondary
        p.warningYellow = amber
        p.acceptedStatus = green
        p.declinedStatus = red
        p.tentativeStatus = amber
        p.secondaryControl = .init(fill: surface, hover: raised, pressed: selection, border: border, divider: border.opacity(0.6))
        p.conflict = .init(busy: red, unconfirmed: amber, free: green)
        p.floatingKeyline = .white.opacity(0.08)
        p.floatingShadow = .black.opacity(0.30)
        p.weatherTooltipFill = deep
        p.eventFillOpacity = 0.28
        p.eventFillSaturation = 0.90
        p.sourcePresentation.tentativeStripeOpacity = 0.32
        p.sourcePresentation.tentativeStripeSaturation = 0.85
        p.sourcePresentation.eventHoverBrightness = 0.025
        p.sourcePresentation.eventOngoingBrightness = 0.02
        p.tentativeEventFillOpacity = 0.10
        p.chrome = .init(
            rowHover: raised, rowSelection: selection, divider: border.opacity(0.6), gridRule: border.opacity(0.4),
            pressedFill: selection, badgeFill: selection, mutedText: secondary, placeholderText: muted,
            inputFill: surface, inputHover: raised, inputFocus: raised, inputKeyline: border,
            slotSelected: selection, slotSelectedPressed: border, slotHover: raised,
            selectionKeyline: secondary, ongoingEventKeyline: red.opacity(0.7), keyboardEventKeyline: secondary,
            searchScrim: .black.opacity(0.15), searchShadow: .black.opacity(0.25),
            tooltipShadow: .black.opacity(0.40), primaryActionShadow: .black.opacity(0.20))
        p.detail = .init(hoverFill: raised, activeFill: selection)
        p.content = .init(
            detailSelectionFill: selection, tentativeText: secondary, tentativeMetadata: muted,
            cancelledText: muted, cancelledMetadata: muted.opacity(0.75), cancelledTimelineText: muted,
            cancelledTimelineFill: surface, ongoingIndicator: red, quietMetadata: muted,
            subduedMetadata: secondary.opacity(0.8), detailMetadata: secondary, sourceLabelFallback: text)
        p.editor = .init(text: text, focusRing: .white.opacity(0.18), selectionFill: selection,
            titleText: text, labelText: secondary, placeholderText: hex(0x72737c),
            panelFill: hex(0x1f2024), fieldFill: hex(0x25262a),
            fieldHoverFill: hex(0x292a2e), fieldFocusedFill: hex(0x2c2d32), fieldKeyline: .white.opacity(0.055),
            overlapBusyText: red, overlapUnconfirmedText: amber)
        p.editor.nativePlaceholderOpacity = 0.52
        p.periodHeader.color = secondary
        p.search.groupLabelTint = secondary
        p.dateTile = .init(
            tileFill: surface, tileBorder: border, weekdayBand: filledRed, weekdayTint: .white,
            dayTint: text, todayTint: red, monthTint: secondary)
        p.keycap = .init(
            onAccentLargeFill: .white.opacity(0.15), onAccentLargeGlyph: .white.opacity(0.8),
            largeFill: selection, largeGlyph: secondary, compactFill: raised, compactStroke: border,
            compactGlyph: secondary, actionLabel: secondary)
        p.settings = .init(
            iconGlyph: .white.opacity(0.9), iconKeyline: border, iconDarkening: 0.25,
            background: base, sidebarBackground: deep, groupFill: surface, groupBorder: border.opacity(0.7),
            divider: border.opacity(0.6), primaryText: text, secondaryText: secondary,
            tint: accent, granted: green, denied: red, pending: muted, attention: amber)
        p.tasks = .init(
            attentionTint: red, timelineCardFill: surface, timelineCardHoverFill: raised,
            timelineCardSelectedFill: selection, timelineCardKeyline: border, timelineDueTick: cyan)
        p.chat = .init(
            toolbarIcon: secondary, toolbarIconHover: text, toolbarIconDisabled: muted,
            inlineTitle: text, jumpButtonBorder: border, dateHoverFill: raised, assistantText: text,
            userBubbleFill: actionFill, userBubbleText: .white, accent: actionFill,
            composerFill: surface, composerStroke: border, composerStrokeIncreased: secondary,
            composerFocusedStroke: secondary.opacity(0.7), composerText: text, composerPlaceholder: muted,
            sendEnabledGlyph: .white, sendDisabledFill: selection, sendDisabledGlyph: muted,
            stopFill: selection, stopGlyph: text, cardFill: surface, cardStroke: border,
            cardHeadline: secondary, destructive: red, receiptDone: green, receiptMuted: muted,
            chipFill: surface, chipHoverFill: raised, chipPressedFill: selection,
            chipBorder: border, chipBorderIncreased: secondary, chipLabel: secondary,
            chipLabelHover: text, chipIcon: muted, chipIconHover: cyan)
        p.meetingTakeover = .init(
            iconFill: surface, iconKeyline: border, metadata: secondary, metadataHover: text,
            title: text, titleHover: .white, disclosure: secondary, reminderHover: raised,
            menuHover: raised, menuText: text, strongActionFill: selection, strongActionHover: border,
            quietActionFill: surface, quietActionHover: raised,
            primaryActionKeyline: accent.opacity(0.4), secondaryActionKeyline: border,
            sheen: text, floor: deep, dimming: deep.opacity(0.65), highContrastDimming: deep.opacity(0.9),
            opaqueFallback: base, approaching: amber, started: red,
            actionSurface: surface, actionSurfaceHover: raised, actionKeyline: border)
        return p
    }()
}
