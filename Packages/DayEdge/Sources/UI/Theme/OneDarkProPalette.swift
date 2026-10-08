import SwiftUI

extension ThemePalette {
    /// One Dark Pro-inspired colors adapted for calendar surfaces and readable native controls.
    /// Reference: https://github.com/Binaryify/OneDark-Pro/blob/master/themes/OneDark-Pro.json
    package static let oneDarkPro: Self = {
        func hex(_ value: UInt32) -> Color {
            Color(red: Double((value >> 16) & 0xff) / 255,
                  green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
        }
        let base = hex(0x282c34)
        let deep = hex(0x21252b)
        let surface = hex(0x2c313a)
        let raised = hex(0x323844)
        let selection = hex(0x3e4451)
        let border = hex(0x454c59)
        let text = hex(0xd7dae0)
        let secondary = hex(0xabb2bf)
        let muted = hex(0x7f8898)
        let blue = hex(0x61afef)
        let purple = hex(0xc678dd)
        let red = hex(0xe06c75)
        let green = hex(0x98c379)
        let amber = hex(0xe5c07b)
        let cyan = hex(0x56b6c2)
        let filledBlue = blue.mix(with: .black, by: 0.42)
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
        p.controlSurface = deep
        p.searchSurface = deep
        p.accentRed = red
        p.destructiveRed = filledRed
        p.nativeControlAccent = filledBlue
        p.controlAccent = filledBlue
        p.successGreen = green
        p.holidayTint = red
        p.weekendDayTint = secondary
        p.dotOrange = amber
        p.detailSelectionAccent = purple
        p.warningYellow = amber
        p.acceptedStatus = green
        p.declinedStatus = red
        p.tentativeStatus = amber
        p.secondaryControl = .init(fill: surface, hover: raised, pressed: selection, border: border, divider: border.opacity(0.6))
        p.conflict = .init(busy: red, unconfirmed: amber, free: green)
        p.floatingKeyline = border
        p.floatingShadow = .black.opacity(0.30)
        p.weatherTooltipFill = deep
        p.eventFillOpacity = 0.40
        p.tentativeEventFillOpacity = 0.10
        p.chrome = .init(
            rowHover: raised, rowSelection: selection, divider: border.opacity(0.6), gridRule: border.opacity(0.4),
            pressedFill: selection, badgeFill: selection, mutedText: secondary, placeholderText: muted,
            inputFill: surface, inputHover: raised, inputFocus: raised, inputKeyline: border,
            slotSelected: selection, slotSelectedPressed: border, slotHover: raised,
            selectionKeyline: blue, ongoingEventKeyline: red.opacity(0.7), keyboardEventKeyline: blue,
            searchScrim: .black.opacity(0.15), searchShadow: .black.opacity(0.25),
            tooltipShadow: .black.opacity(0.40), primaryActionShadow: .black.opacity(0.20))
        p.detail = .init(hoverFill: raised, activeFill: selection)
        p.content = .init(
            detailSelectionFill: purple.opacity(0.14), tentativeText: secondary, tentativeMetadata: muted,
            cancelledText: muted, cancelledMetadata: muted.opacity(0.75), cancelledTimelineText: muted,
            cancelledTimelineFill: surface, ongoingIndicator: red, quietMetadata: muted,
            subduedMetadata: secondary.opacity(0.8), detailMetadata: secondary, sourceLabelFallback: text)
        p.editor = .init(text: text, focusRing: blue.opacity(0.8), selectionFill: filledBlue,
            titleText: text, labelText: secondary, placeholderText: secondary, panelFill: raised,
            fieldFill: surface, fieldHoverFill: raised, fieldFocusedFill: raised, fieldKeyline: border,
            overlapBusyText: secondary, overlapUnconfirmedText: secondary)
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
            tint: blue, granted: green, denied: red, pending: muted, attention: amber)
        p.tasks = .init(
            attentionTint: red, timelineCardFill: surface, timelineCardHoverFill: raised,
            timelineCardSelectedFill: selection, timelineCardKeyline: border, timelineDueTick: cyan)
        p.chat = .init(
            toolbarIcon: secondary, toolbarIconHover: text, toolbarIconDisabled: muted,
            inlineTitle: text, jumpButtonBorder: border, dateHoverFill: raised, assistantText: text,
            userBubbleFill: filledBlue, userBubbleText: .white, accent: filledBlue,
            composerFill: surface, composerStroke: border, composerStrokeIncreased: secondary,
            composerFocusedStroke: blue.opacity(0.7), composerText: text, composerPlaceholder: muted,
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
            primaryActionKeyline: blue.opacity(0.4), secondaryActionKeyline: border,
            sheen: text, floor: deep, dimming: deep.opacity(0.65), highContrastDimming: deep.opacity(0.9),
            opaqueFallback: base, approaching: amber, started: red,
            actionSurface: surface, actionSurfaceHover: raised, actionKeyline: border)
        return p
    }()
}
