import SwiftUI

// swiftlint:disable identifier_name - token names follow the design spec (Chat_accent)

/// What every token group of a built-in theme is derived from.
struct PaletteBase {
    let apple: Bool
    let light: Bool
    let refinedUserBubble: Bool
    let ink: Color
    let red: Color
    let blue: Color
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    let dimmedText: Color
    let accentRed: Color
    let controlAccent: Color
    let detailSelectionAccent: Color
    let SecondaryControl_border: Color
    let SecondaryControl_divider: Color
}

extension PaletteBase {
    var meetingTakeover: ThemePaletteValues.MeetingTakeoverColors {
        let MeetingTakeover_dimming = apple && light ? Color.white.opacity(0.80) : Color.black.opacity(0.20)
        let MeetingTakeover_highContrastDimming = apple && light ? Color.white.opacity(0.94) : Color.black.opacity(0.35)
        let MeetingTakeover_opaqueFallback = apple ? background : Color(red: 0.19, green: 0.20, blue: 0.23)
        let MeetingTakeover_approaching =
            apple ? Color(nsColor: .systemOrange) : Color(red: 1.0, green: 0.72, blue: 0.38)
        let MeetingTakeover_started = apple ? red : Color(red: 1.0, green: 0.43, blue: 0.40)
        let MeetingTakeover_actionSurface = ink.opacity(0.17)
        let MeetingTakeover_actionSurfaceHover = ink.opacity(0.24)
        let MeetingTakeover_actionKeyline = ink.opacity(0.18)
        return ThemePaletteValues.MeetingTakeoverColors(
            iconFill: ink.opacity(0.11), iconKeyline: ink.opacity(0.17), metadata: ink.opacity(0.55),
            metadataHover: ink.opacity(0.78), title: ink.opacity(0.96), titleHover: ink,
            disclosure: ink.opacity(0.75), reminderHover: ink.opacity(0.06), menuHover: ink.opacity(0.075),
            menuText: ink.opacity(0.84), strongActionFill: ink.opacity(0.26), strongActionHover: ink.opacity(0.34),
            quietActionFill: ink.opacity(0.08), quietActionHover: ink.opacity(0.14),
            primaryActionKeyline: Color.white.opacity(0.14), secondaryActionKeyline: ink.opacity(0.18),
            sheen: Color.white, floor: Color.black, dimming: MeetingTakeover_dimming,
            highContrastDimming: MeetingTakeover_highContrastDimming,
            opaqueFallback: MeetingTakeover_opaqueFallback, approaching: MeetingTakeover_approaching,
            started: MeetingTakeover_started, actionSurface: MeetingTakeover_actionSurface,
            actionSurfaceHover: MeetingTakeover_actionSurfaceHover, actionKeyline: MeetingTakeover_actionKeyline)
    }

    var keycap: ThemePaletteValues.KeycapColors {
        let Keycap_largeFill = ink.opacity(0.15)
        let Keycap_largeGlyph = ink.opacity(0.75)
        let Keycap_compactFill = ink.opacity(0.07)
        let Keycap_compactStroke = ink.opacity(0.1)
        let Keycap_compactGlyph = ink.opacity(0.78)
        let Keycap_actionLabel = ink.opacity(0.68)
        return ThemePaletteValues.KeycapColors(
            onAccentLargeFill: Color.white.opacity(0.15), onAccentLargeGlyph: Color.white.opacity(0.75),
            largeFill: Keycap_largeFill, largeGlyph: Keycap_largeGlyph, compactFill: Keycap_compactFill,
            compactStroke: Keycap_compactStroke, compactGlyph: Keycap_compactGlyph, actionLabel: Keycap_actionLabel)
    }

    var dateTile: ThemePaletteValues.DateTileColors {
        let DateTile_tileFill = ink.opacity(0.06)
        let DateTile_tileBorder = ink.opacity(0.1)
        let DateTile_weekdayBand = Color(red: 0.62, green: 0.20, blue: 0.19)
        let DateTile_weekdayTint = Color.white
        let DateTile_dayTint = primaryText
        let DateTile_todayTint = apple ? red : controlAccent
        let DateTile_monthTint = secondaryText.opacity(0.8)
        return ThemePaletteValues.DateTileColors(
            tileFill: DateTile_tileFill, tileBorder: DateTile_tileBorder, weekdayBand: DateTile_weekdayBand,
            weekdayTint: DateTile_weekdayTint, dayTint: DateTile_dayTint, todayTint: DateTile_todayTint,
            monthTint: DateTile_monthTint)
    }

    var chat: ThemePaletteValues.ChatColors {
        let Chat_jumpButtonBorder = ink.opacity(0.12)
        let Chat_dateHoverFill = ink.opacity(0.05)
        let Chat_assistantText = ink.opacity(0.84)
        let Chat_accent = apple ? blue.mix(with: .black, by: 0.20) : controlAccent.mix(with: .black, by: 0.28)
        // Native System Blue resolves in the themed window's appearance. A small neutral
        // mix softens saturation; darkening keeps white text readable without luminous blue.
        let Chat_userBubbleFill = refinedUserBubble
            ? Color(nsColor: .systemBlue).mix(with: .gray, by: 0.08).mix(with: .black, by: light ? 0.10 : 0.18)
            : Chat_accent
        let Chat_userBubbleText = Color.white
        let Chat_composerStrokeIncreased = ink.opacity(0.20)
        let Chat_composerText = ink.opacity(0.90)
        let Chat_composerPlaceholder = ink.opacity(0.40)
        let Chat_sendEnabledGlyph = Color.white
        let Chat_sendDisabledFill = ink.opacity(0.10)
        let Chat_sendDisabledGlyph = ink.opacity(0.30)
        let Chat_stopFill = ink.opacity(0.18)
        let Chat_stopGlyph = ink.opacity(0.90)
        let Chat_cardFill = ink.opacity(0.07)
        let Chat_cardStroke = ink.opacity(0.12)
        let Chat_cardHeadline = ink.opacity(0.62)
        let Chat_destructive = accentRed
        let Chat_receiptDone = apple ? Color(nsColor: .systemGreen) : Color.green.opacity(0.85)
        let Chat_receiptMuted = ink.opacity(0.45)
        let Chat_chipFill = ink.opacity(0.06)
        let Chat_chipHoverFill = ink.opacity(0.10)
        let Chat_chipPressedFill = ink.opacity(0.14)
        let Chat_chipBorder = ink.opacity(0.10)
        let Chat_chipBorderIncreased = ink.opacity(0.20)
        let Chat_chipLabel = ink.opacity(0.85)
        let Chat_chipLabelHover = ink
        let Chat_chipIcon = ink.opacity(0.55)
        let Chat_chipIconHover = ink.opacity(0.75)
        return ThemePaletteValues.ChatColors(
            jumpButtonBorder: Chat_jumpButtonBorder, dateHoverFill: Chat_dateHoverFill,
            assistantText: Chat_assistantText, userBubbleFill: Chat_userBubbleFill,
            userBubbleText: Chat_userBubbleText, accent: Chat_accent,
            composerStrokeIncreased: Chat_composerStrokeIncreased, composerText: Chat_composerText,
            composerPlaceholder: Chat_composerPlaceholder, sendEnabledGlyph: Chat_sendEnabledGlyph,
            sendDisabledFill: Chat_sendDisabledFill, sendDisabledGlyph: Chat_sendDisabledGlyph,
            stopFill: Chat_stopFill, stopGlyph: Chat_stopGlyph, cardFill: Chat_cardFill,
            cardStroke: Chat_cardStroke, cardHeadline: Chat_cardHeadline, destructive: Chat_destructive,
            receiptDone: Chat_receiptDone, receiptMuted: Chat_receiptMuted, chipFill: Chat_chipFill,
            chipHoverFill: Chat_chipHoverFill, chipPressedFill: Chat_chipPressedFill, chipBorder: Chat_chipBorder,
            chipBorderIncreased: Chat_chipBorderIncreased, chipLabel: Chat_chipLabel,
            chipLabelHover: Chat_chipLabelHover, chipIcon: Chat_chipIcon, chipIconHover: Chat_chipIconHover)
    }

    var settings: ThemePaletteValues.SettingsColors {
        let Settings_background = background
        let Settings_sidebarBackground =
            apple ? (light ? Color(white: 0.95) : Color(white: 0.10)) : Color(red: 0.085, green: 0.085, blue: 0.09)
        let Settings_groupFill = apple ? (light ? Color.white : ink.opacity(0.045)) : ink.opacity(0.045)
        let Settings_groupBorder = SecondaryControl_border
        let Settings_divider = SecondaryControl_divider
        let Settings_primaryText = primaryText
        let Settings_secondaryText = secondaryText
        let Settings_tint = controlAccent
        let Settings_granted = Color(nsColor: .systemGreen)
        let Settings_denied = Color(nsColor: .systemRed)
        let Settings_pending = ink.opacity(0.35)
        let Settings_attention = Color(nsColor: .systemOrange)
        return ThemePaletteValues.SettingsColors(
            iconGlyph: Color.white.opacity(0.8), iconKeyline: Color.white.opacity(0.08),
            iconDarkening: light ? 0 : 0.5, background: Settings_background,
            sidebarBackground: Settings_sidebarBackground, groupFill: Settings_groupFill,
            groupBorder: Settings_groupBorder, divider: Settings_divider, primaryText: Settings_primaryText,
            secondaryText: Settings_secondaryText, tint: Settings_tint, granted: Settings_granted,
            denied: Settings_denied, pending: Settings_pending, attention: Settings_attention)
    }

    var tasks: ThemePaletteValues.TasksColors {
        let Tasks_attentionTint = accentRed.opacity(0.85)
        let Tasks_timelineCardFill = ink.opacity(0.09)
        let Tasks_timelineCardHoverFill = ink.opacity(0.12)
        let Tasks_timelineCardSelectedFill = ink.opacity(0.16)
        let Tasks_timelineCardKeyline = ink.opacity(0.08)
        let Tasks_timelineDueTick = secondaryText.opacity(0.5)
        return ThemePaletteValues.TasksColors(
            attentionTint: Tasks_attentionTint, timelineCardFill: Tasks_timelineCardFill,
            timelineCardHoverFill: Tasks_timelineCardHoverFill,
            timelineCardSelectedFill: Tasks_timelineCardSelectedFill,
            timelineCardKeyline: Tasks_timelineCardKeyline, timelineDueTick: Tasks_timelineDueTick)
    }

    var chrome: ThemePaletteValues.ChromeColors {
        ThemePaletteValues.ChromeColors(
            rowHover: ink.opacity(apple ? (light ? 0.035 : 0.045) : 0.06),
            rowSelection: ink.opacity(apple ? (light ? 0.05 : 0.065) : 0.09), divider: ink.opacity(0.10),
            gridRule: ink.opacity(0.08), pressedFill: ink.opacity(0.12), badgeFill: ink.opacity(0.15),
            mutedText: ink.opacity(0.55), placeholderText: ink.opacity(0.40),
            slotSelected: ink.opacity(apple ? (light ? 0.08 : 0.12) : 0.20),
            slotSelectedPressed: ink.opacity(apple ? (light ? 0.12 : 0.18) : 0.28),
            slotHover: ink.opacity(apple ? (light ? 0.045 : 0.06) : 0.07),
            selectionKeyline: ink.opacity(0.55), ongoingEventKeyline: ink.opacity(0.38),
            keyboardEventKeyline: ink.opacity(0.70), searchScrim: Color.black.opacity(0.10),
            searchShadow: Color.black.opacity(0.18), tooltipShadow: Color.black.opacity(0.35),
            primaryActionShadow: Color.black.opacity(0.14))
    }

    var content: ThemePaletteValues.ContentColors {
        ThemePaletteValues.ContentColors(
            detailSelectionFill: detailSelectionAccent.opacity(0.16),
            tentativeText: primaryText.opacity(0.65), tentativeMetadata: secondaryText.opacity(0.7),
            cancelledText: secondaryText, cancelledMetadata: dimmedText,
            cancelledTimelineText: primaryText.opacity(0.5), cancelledTimelineFill: secondaryText.opacity(0.12),
            ongoingIndicator: accentRed.opacity(0.8), quietMetadata: secondaryText.opacity(0.6),
            subduedMetadata: secondaryText.opacity(0.7), detailMetadata: secondaryText.opacity(0.8),
            sourceLabelFallback: primaryText.opacity(0.92))
    }

    var editor: ThemePaletteValues.EditorColors {
        ThemePaletteValues.EditorColors(text: primaryText.opacity(0.92),
            focusRing: (apple ? blue : Color.accentColor).opacity(0.75),
            selectionFill: (apple ? blue : Color.accentColor).opacity(0.85),
            titleText: primaryText, labelText: secondaryText, placeholderText: secondaryText,
            panelFill: ink.opacity(apple ? (light ? 0.035 : 0.045) : 0.06),
            fieldFill: ink.opacity(0.065), fieldHoverFill: ink.opacity(0.09),
            fieldFocusedFill: ink.opacity(0.11), fieldKeyline: ink.opacity(0.09),
            overlapBusyText: secondaryText, overlapUnconfirmedText: secondaryText)
    }
}

// swiftlint:enable identifier_name
