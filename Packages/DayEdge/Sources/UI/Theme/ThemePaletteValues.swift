import AppKit
import SwiftUI

/// The palette's values, stored once behind `ThemePalette`.
package struct ThemePaletteValues {
    /// Nil retains the original solid rendering recipes exactly.
    package var surfaces: SurfaceTreatments?
    /// Optional room for floating navigation chrome; nil preserves bare-chevron sizing.
    package var navigationButtonSize: CGSize?
    package var navigationButtonSpacing: CGFloat = 18
    package var agendaHeader: AgendaHeaderColors?
    /// A hairline under each agenda day header — the theme's own decision,
    /// for themes whose headers don't separate days with a band of their own.
    package var showsAgendaSectionSeparator = false
    package var agendaSectionSeparatorColor: Color = .clear
    /// Agenda day headers stick to the top while their day scrolls by. Off
    /// for a theme whose headers have no backing of their own (they'd sit
    /// over the events scrolling beneath them).
    package var pinsAgendaSectionHeaders = true
    /// The agendas' `pinnedViews`, from `pinsAgendaSectionHeaders`.
    package var agendaPinnedViews: PinnedScrollableViews { pinsAgendaSectionHeaders ? [.sectionHeaders] : [] }
    package func agendaHeaderFill(for style: AgendaHeaderStyle) -> Color {
        switch style {
        case .inlineAgenda: return agendaHeader?.inlineAgenda ?? background
        case .popoverAgenda: return agendaHeader?.popoverAgenda ?? .clear
        }
    }
    package var contentBackdrop: Color { surfaces == nil ? background : .clear }
    package var background: Color
    package var calendarHeader: CalendarHeaderStyle
    /// Preserve the existing Apple navigation backing when no surface recipe is supplied.
    package var navigationMaterial: Material? { viewSwitcherUsesMaterial ? .ultraThinMaterial : nil }
    package var viewSwitcherUsesMaterial: Bool
    package var selectedWeekBand: Color
    package var selectedDayFill: Color
    package var todayFill: Color
    package var primaryText: Color
    package var secondaryText: Color
    package var dimmedText: Color
    package var currentTimeCapsule: Color
    package var timelineCapsule: Color
    package var controlSurface: Color
    package var searchSurface: Color
    package var accentRed: Color
    package var destructiveRed: Color
    package var nativeControlAccent: Color
    package var controlAccent: Color
    package var successGreen: Color
    package var holidayTint: Color
    package var weekendDayTint: Color
    package var dotOrange: Color
    package var detailSelectionAccent: Color
    package var secondaryControl: SecondaryControlColors
    package var conflict: ConflictColors
    package var meetingTakeover: MeetingTakeoverColors
    package var keycap: KeycapColors
    package var dateTile: DateTileColors
    package var search: SearchColors
    package var periodHeader: PeriodHeaderColors
    package var chat: ChatColors
    package var settings: SettingsColors
    package var tasks: TasksColors
    package var chrome: ChromeColors
    package var detail: DetailColors
    /// Complete state colors; views must not derive these by dimming base text/accent colors.
    package var content: ContentColors
    package var editor: EditorColors
    /// Strengths applied to externally supplied calendar, list and service identity colors.
    package var sourcePresentation: SourcePresentation
    package var weatherTooltipFill: Color
    package var onAccentText: Color
    package var warningYellow: Color
    package var acceptedStatus: Color
    package var declinedStatus: Color
    package var tentativeStatus: Color
    package var todayText: Color
    package var selectedDayText: Color
    package var todayAccent: Color
    package var currentTimeText: Color
    package var neutralInk: Color
    package var floatingKeyline: Color
    package var floatingShadow: Color
    /// The working tone between the canvas and the controls: floating
    /// details, menus and popovers. Nil keeps each one's own (the window
    /// background, or the system popover material).
    package var workingSurface: Color?
    /// Compact controls — footer pills, Copy Link and the like. Nil keeps
    /// their original fills.
    package var compactControl: CompactControlColors?
    /// How far semantic action tints (a service's Join) are drawn toward
    /// the neutral secondary text: 0 keeps them as they are.
    package var semanticActionMix: Double = 0
    /// The persistent bottom chrome (selector, Settings) floats over the
    /// agenda: a system material blurred beneath it, nil for none (Frost's
    /// own floating-control glass already is one)…
    package var persistentChromeMaterial: Material?
    /// …under the chrome surface color at this opacity, so the content
    /// beneath stays faintly there. Foregrounds are never dimmed.
    package var persistentChromeTintOpacity: Double = 1
    /// Applies only to large Day-view fills, never source markers or borders.
    package var eventFillSaturation: Double = 1
    package var eventFillOpacity: Double
    package var tentativeEventFillOpacity: Double
    package var isLight: Bool

    // swiftlint:disable identifier_name function_body_length - the default theme, one token per line; names follow the design spec (SecondaryControl_fill)
    static func make(apple: Bool, light: Bool, refinedUserBubble: Bool = false) -> Self {
        let ink: Color = light ? .black : .white
        let red = Color(nsColor: .systemRed)
        let blue = Color(nsColor: .controlAccentColor)
        let background = apple ? (light ? Color.white : Color(white: 0.12)) : Color(red: 0.11, green: 0.11, blue: 0.115)
        let selectedWeekBand = apple ? Color.clear : ink.opacity(0.06)
        let selectedDayFill =
            apple ? (light ? Color.black.opacity(0.075) : Color.white.opacity(0.12)) : ink.opacity(0.32)
        let todayFill = apple ? red : Color(red: 0.30, green: 0.62, blue: 1.0).opacity(0.55)
        let primaryText = apple ? Color(nsColor: .labelColor) : ink
        let secondaryText = apple ? Color(nsColor: .secondaryLabelColor) : ink.opacity(0.55)
        let dimmedText = apple ? Color(nsColor: .tertiaryLabelColor) : ink.opacity(0.28)
        let currentTimeCapsule = (apple ? red : Color(red: 0.93, green: 0.23, blue: 0.23)).opacity(0.8)
        let timelineCapsule = background.opacity(0.9)
        let controlSurface = apple ? ink.opacity(light ? 0.045 : 0.08) : Color.black.opacity(0.35)
        let searchSurface =
            apple
            ? (light ? Color(white: 0.97) : Color(white: 0.09))
            : Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x13 / 255)
        let SecondaryControl_fill = ink.opacity(0.035)
        let SecondaryControl_hover = ink.opacity(0.07)
        let SecondaryControl_pressed = ink.opacity(0.10)
        let SecondaryControl_border = ink.opacity(0.08)
        let SecondaryControl_divider = ink.opacity(0.07)
        let accentRed = apple ? red : Color(red: 0.93, green: 0.23, blue: 0.23)
        let destructiveRed = Color(nsColor: .systemRed)
        let controlAccent = apple ? blue : Color(red: 0.30, green: 0.62, blue: 1.0)
        let successGreen = apple ? Color(nsColor: .systemGreen) : Color.green
        let Conflict_busy = Color(nsColor: .systemRed)
        let Conflict_unconfirmed = Color(nsColor: .systemYellow)
        let Conflict_free = Color(nsColor: .systemGreen)
        let holidayTint = Color(nsColor: .systemRed).opacity(0.65)
        let weekendDayTint = apple ? secondaryText : controlAccent.opacity(0.9)
        let dotOrange = Color(red: 0.95, green: 0.66, blue: 0.16)
        let detailSelectionAccent = apple ? blue : Color(red: 1.0, green: 0.84, blue: 0.3)
        let Search_groupLabelTint = secondaryText
        let PeriodHeader_color = ink.opacity(0.6)
        let base = PaletteBase(
            apple: apple,
            light: light,
            refinedUserBubble: refinedUserBubble,
            ink: ink,
            red: red,
            blue: blue,
            background: background,
            primaryText: primaryText,
            secondaryText: secondaryText,
            dimmedText: dimmedText,
            accentRed: accentRed,
            controlAccent: controlAccent,
            detailSelectionAccent: detailSelectionAccent,
            SecondaryControl_border: SecondaryControl_border,
            SecondaryControl_divider: SecondaryControl_divider
        )
        var palette = Self(
            background: background,
            calendarHeader: CalendarHeaderStyle(
                titleFont: apple ? .system(size: 26, weight: .bold) : AppTheme.TextStyle.monthTitle,
                yearFont: apple ? .system(size: 26, weight: .regular) : AppTheme.TextStyle.monthTitle,
                yearText: apple ? primaryText.opacity(0.72) : accentRed,
                todayTitleText: apple ? primaryText : controlAccent),
            viewSwitcherUsesMaterial: apple,
            selectedWeekBand: selectedWeekBand,
            selectedDayFill: selectedDayFill,
            todayFill: todayFill,
            primaryText: primaryText,
            secondaryText: secondaryText,
            dimmedText: dimmedText,
            currentTimeCapsule: currentTimeCapsule,
            timelineCapsule: timelineCapsule,
            controlSurface: controlSurface,
            searchSurface: searchSurface,
            accentRed: accentRed,
            destructiveRed: destructiveRed,
            nativeControlAccent: apple ? blue : Color.accentColor,
            controlAccent: controlAccent,
            successGreen: successGreen,
            holidayTint: holidayTint,
            weekendDayTint: weekendDayTint,
            dotOrange: dotOrange,
            detailSelectionAccent: detailSelectionAccent,
            secondaryControl: SecondaryControlColors(
                fill: SecondaryControl_fill, hover: SecondaryControl_hover, pressed: SecondaryControl_pressed,
                border: SecondaryControl_border, divider: SecondaryControl_divider),
            conflict: ConflictColors(busy: Conflict_busy, unconfirmed: Conflict_unconfirmed, free: Conflict_free),
            meetingTakeover: base.meetingTakeover,
            keycap: base.keycap,
            dateTile: base.dateTile,
            search: SearchColors(groupLabelTint: Search_groupLabelTint),
            periodHeader: PeriodHeaderColors(color: PeriodHeader_color),
            chat: base.chat,
            settings: base.settings,
            tasks: base.tasks,
            chrome: base.chrome,
            detail: DetailColors(hoverFill: ink.opacity(0.06), activeFill: ink.opacity(0.10)),
            content: base.content,
            editor: base.editor,
            sourcePresentation: SourcePresentation(
                completedTaskOpacity: 0.5, taskHoverCheckOpacity: 0.55, readOnlyTaskOpacity: 0.45,
                tentativeMarkerOpacity: 0.7, eventBorderOpacity: 0.5, tentativeStripeOpacity: 0.45,
                joinFillOpacity: 0.15, allDayFillOpacity: 0.22, allDayHoverFillOpacity: 0.30,
                allDayBorderOpacity: 0.28, allDayHoverBorderOpacity: 0.32,
                timelineMetadataOpacity: 0.75, timelineGlyphOpacity: 0.7),
            weatherTooltipFill: light ? Color(white: 0.97) : Color.black.opacity(0.75),
            onAccentText: .white,
            warningYellow: apple ? Color(nsColor: .systemYellow) : .yellow,
            acceptedStatus: apple ? Color(nsColor: .systemGreen) : .green,
            declinedStatus: apple ? red : .red,
            tentativeStatus: apple ? Color(nsColor: .systemYellow) : .yellow,
            todayText: apple ? .white : primaryText,
            selectedDayText: primaryText,
            todayAccent: apple ? red : controlAccent,
            currentTimeText: .white,
            neutralInk: ink,
            floatingKeyline: ink.opacity(0.09),
            floatingShadow: Color.black.opacity(light ? 0.12 : 0.28),
            eventFillOpacity: light ? 0.16 : 0.55,
            tentativeEventFillOpacity: light ? 0.07 : 0.12,
            isLight: light
        )
        // Native-feeling translucency over the agenda: Apple's regular
        // material (about as opaque as a toolbar); the colorful theme a
        // thinner one under its own dark tint.
        palette.persistentChromeMaterial = apple ? .regularMaterial : .ultraThinMaterial
        return palette
    }
    // swiftlint:enable identifier_name function_body_length
}

extension ThemePaletteValues {
    // The persistent chrome — the view switcher, the bottom selector and
    // Settings — is one surface family. Each theme gets it from its own
    // tokens (Frost's material comes with the `.floatingControl` role, the
    // Apple themes' with `navigationMaterial`), never from a theme check.

    /// Its surface: the view switcher's.
    package var persistentChromeSurface: Color { controlSurface }
    /// Hover on a chrome control: the switcher's slot hover.
    package var persistentChromeHoverSurface: Color { chrome.slotHover }
    /// A fine edge, where the theme draws compact controls with one.
    package var persistentChromeKeyline: Color? { compactControl?.keyline }
    /// Between a chrome control's segments (status │ selector).
    package var persistentChromeDivider: Color { chrome.divider }
    /// Icons and the disclosure chevron: quieter than the label.
    package var persistentChromeSecondaryForeground: Color { secondaryText }

    // The wordmark (`Wordmark`): "Day" in the primary tone, a muted
    // slash, "Edge" a little softer than "Day".
    package var wordmarkDay: Color { settings.primaryText }
    package var wordmarkSlash: Color { settings.secondaryText.opacity(0.85) }
    package var wordmarkEdge: Color { settings.primaryText.mix(with: settings.secondaryText, by: 0.45) }

    /// A compact action pill's fill (Copy Link).
    package func compactActionFill(isHovered: Bool) -> Color {
        guard let compactControl else { return isHovered ? chrome.pressedFill : chrome.rowHover }
        return isHovered ? compactControl.hoverSurface : compactControl.surface
    }

    /// A semantic action's tint, restrained as far as the theme asks.
    package func semanticActionTint(_ tint: Color) -> Color {
        semanticActionMix > 0 ? tint.mix(with: secondaryText, by: semanticActionMix) : tint
    }
}
