import SwiftUI

extension ThemePalette {
    /// Built once each, so the environment gets the same palette (and its
    /// views no needless update) every time the theme is read.
    package static let frostLight = frost(light: true)
    package static let frostDark = frost(light: false)

    /// One material identity, resolved in the system's light or dark appearance.
    /// Solid colors are also the accessibility fallback and stable semantic-event substrate.
    package static func frost(light: Bool) -> Self {
        let t = FrostTones(light: light)
        var p = light ? Self.appleLight : Self.appleDark
        p.background = t.base
        p.primaryText = t.primary
        p.secondaryText = t.secondary
        p.dimmedText = t.tertiary
        p.calendarHeader.yearText = t.secondary
        p.calendarHeader.todayTitleText = t.primary
        p.controlSurface = t.nested
        p.searchSurface = t.raised
        p.floatingKeyline = t.keyline
        p.floatingShadow = .black.opacity(light ? 0.14 : 0.24)
        p.navigationButtonSize = CGSize(width: 34, height: 30)
        p.navigationButtonSpacing = 4
        // One continuous frosted surface: day headers have no backing of
        // their own — the agenda's material shows through, inline and in
        // popovers alike — so they don't stick (they'd sit over the events
        // scrolling beneath), and days are told apart by a hairline.
        p.agendaHeader = .init(inlineAgenda: .clear, popoverAgenda: .clear)
        p.pinsAgendaSectionHeaders = false
        p.showsAgendaSectionSeparator = true
        p.agendaSectionSeparatorColor = t.ink.opacity(light ? 0.06 : 0.08)
        // Its floating-control glass is the chrome's material already.
        p.persistentChromeMaterial = nil
        p.surfaces = frostSurfaces(t)
        applyFrostChrome(to: &p, t)
        applyFrostContent(to: &p, t)
        return p
    }

    /// Material already contributes opacity and blur. These are *tint* strengths,
    /// not whole-window alpha: let broad environmental chroma survive that layer.
    /// Three rendering families: shell, floating control and elevated glass.
    /// Floating chrome samples desktop blur directly instead of sampling the already
    /// tinted shell a second time. This prevents compounded opacity/flat gray pills.
    private static func frostSurfaces(_ t: FrostTones) -> SurfaceTreatments {
        let light = t.light
        let glassTint = FrostTones.rgb(light ? 0xf5f7fa : 0x303238)
        let elevatedTint = FrostTones.rgb(light ? 0xf6f8fb : 0x383b42)
        let glassEdge = FrostTones.rgb(0xe9eef5)
        let controlLighting = SurfaceLighting(
            interiorLight: .white.opacity(light ? 0.035 : 0.045),
            interiorShade: .black.opacity(light ? 0.025 : 0.055),
            edgeShade: .black.opacity(light ? 0.08 : 0.12))
        let elevatedLighting = SurfaceLighting(
            interiorLight: .white.opacity(light ? 0.02 : 0.03),
            interiorShade: .black.opacity(light ? 0.02 : 0.04),
            edgeShade: .black.opacity(light ? 0.06 : 0.09))
        let controlGlass = SurfaceTreatment(
            backing: .desktop(.popover), tint: glassTint, tintOpacity: light ? 0.10 : 0.12,
            keyline: t.ink.opacity(0.035), edgeHighlight: glassEdge.opacity(light ? 0.38 : 0.20),
            elevation: .init(color: .black.opacity(light ? 0.11 : 0.18), radius: 5, y: 1),
            usesLiquidGlassOptics: true, lighting: controlLighting)
        // Selected navigation inherits real floating-control glass, with quieter
        // optical definition. Unselected chips never activate this recipe.
        var navigationGlass = controlGlass
        navigationGlass.tintOpacity = light ? 0.18 : 0.20
        navigationGlass.edgeHighlight = controlGlass.edgeHighlight?.opacity(0.70)
        navigationGlass.lighting = .init(
            interiorLight: controlLighting.interiorLight.opacity(0.70),
            interiorShade: controlLighting.interiorShade.opacity(0.70),
            edgeShade: controlLighting.edgeShade.opacity(0.70))
        navigationGlass.elevation = nil
        let selectedGlass = SurfaceTreatment(
            backing: .desktop(.popover), tint: elevatedTint, tintOpacity: light ? 0.30 : 0.36,
            keyline: t.ink.opacity(0.045), edgeHighlight: glassEdge.opacity(light ? 0.40 : 0.23),
            elevation: .init(color: .black.opacity(light ? 0.08 : 0.14), radius: 2, y: 1),
            usesLiquidGlassOptics: true, lighting: controlLighting)
        let elevatedGlass = SurfaceTreatment(
            backing: .desktop(.popover), tint: elevatedTint, tintOpacity: light ? 0.28 : 0.34,
            keyline: t.ink.opacity(0.045), edgeHighlight: glassEdge.opacity(light ? 0.30 : 0.17),
            usesLiquidGlassOptics: true, lighting: elevatedLighting)
        var transientGlass = elevatedGlass
        transientGlass.elevation = .init(color: .black.opacity(light ? 0.13 : 0.24), radius: 12, y: 4)
        return SurfaceTreatments(
            window: .init(backing: .desktop(.popover), tint: t.base, tintOpacity: light ? 0.64 : 0.56),
            nested: .init(backing: .local(.regular), tint: t.nested, tintOpacity: light ? 0.52 : 0.58,
                          keyline: t.keyline.opacity(0.6), edgeHighlight: .white.opacity(light ? 0.12 : 0.05)),
            elevated: elevatedGlass,
            transient: transientGlass,
            floatingControl: controlGlass,
            selectedFloatingControl: selectedGlass,
            selectedNavigation: navigationGlass)
    }

    /// Selection, today, the timeline, chrome, details and editors.
    private static func applyFrostChrome(to p: inout Self, _ t: FrostTones) {
        let light = t.light
        p.selectedWeekBand = .clear
        p.selectedDayFill = t.selection
        p.selectedDayText = t.primary
        p.todayAccent = t.coralInk
        p.todayFill = t.coral
        p.todayText = .white
        p.accentRed = t.coralInk
        p.currentTimeCapsule = t.coral
        p.currentTimeText = .white
        p.timelineCapsule = t.base.opacity(0.94)
        p.weekendDayTint = t.secondary
        p.periodHeader.color = t.secondary
        p.chrome.rowHover = t.hover
        p.chrome.rowSelection = t.selection
        p.chrome.pressedFill = t.selection
        p.chrome.divider = t.keyline.opacity(0.65)
        p.chrome.gridRule = t.keyline.opacity(0.45)
        p.chrome.mutedText = t.secondary
        p.chrome.placeholderText = t.tertiary
        p.chrome.slotSelected = light ? .white.opacity(0.50) : .white.opacity(0.16)
        p.chrome.slotSelectedPressed = light ? .white.opacity(0.68) : .white.opacity(0.22)
        p.chrome.slotHover = t.hover
        p.chrome.selectionKeyline = t.secondary
        p.chrome.ongoingEventKeyline = t.coral.opacity(0.65)
        p.chrome.keyboardEventKeyline = t.secondary
        p.chrome.searchShadow = p.floatingShadow
        p.detail = .init(hoverFill: t.hover, activeFill: t.selection)
        p.content.detailSelectionFill = t.selection
        p.content.quietMetadata = t.tertiary
        p.content.subduedMetadata = t.secondary
        p.content.detailMetadata = t.secondary
        p.content.sourceLabelFallback = t.primary
        p.content.ongoingIndicator = t.coralInk
        p.editor = .init(text: t.primary, focusRing: p.nativeControlAccent.opacity(0.65), selectionFill: t.selection,
                         titleText: t.primary, labelText: t.secondary, placeholderText: t.tertiary,
                         panelFill: t.nested, fieldFill: light ? .white.opacity(0.38) : .black.opacity(0.16),
                         fieldHoverFill: light ? .white.opacity(0.58) : .white.opacity(0.09),
                         fieldFocusedFill: light ? .white.opacity(0.70) : .white.opacity(0.14),
                         fieldKeyline: t.ink.opacity(0.10),
                         overlapBusyText: t.coralInk, overlapUnconfirmedText: p.conflict.unconfirmed,
                         nativePlaceholderOpacity: 0.68)
    }

    /// Conflicts, event fills, date tiles, tasks, chat, Settings and the takeover.
    private static func applyFrostContent(to p: inout Self, _ t: FrostTones) {
        let light = t.light
        p.conflict.busy = t.coralInk
        p.eventFillOpacity = light ? 0.18 : 0.27
        p.eventFillSaturation = 0.94
        p.tentativeEventFillOpacity = light ? 0.08 : 0.10
        p.sourcePresentation.tentativeStripeOpacity = light ? 0.30 : 0.34
        p.sourcePresentation.tentativeStripeSaturation = 0.92
        p.dateTile.tileFill = t.hover
        p.dateTile.tileBorder = t.keyline
        p.dateTile.dayTint = t.primary
        p.dateTile.todayTint = t.coralInk
        p.dateTile.monthTint = t.secondary
        p.tasks.attentionTint = t.coralInk
        p.chat.assistantText = t.primary
        p.chat.sendEnabledGlyph = t.primary
        p.chat.sendDisabledGlyph = t.tertiary
        p.chat.composerText = t.primary
        p.chat.composerPlaceholder = t.tertiary
        p.chat.cardFill = t.nested
        p.chat.cardStroke = t.keyline
        p.chat.cardHeadline = t.secondary
        p.chat.chipLabel = t.secondary
        p.chat.chipLabelHover = t.primary
        p.chat.chipIcon = t.tertiary
        p.settings.background = t.base
        p.settings.sidebarBackground = t.base
        p.settings.groupFill = t.nested
        p.settings.groupBorder = t.keyline
        p.settings.divider = p.chrome.divider
        p.settings.primaryText = t.primary
        p.settings.secondaryText = t.secondary
        p.meetingTakeover.opaqueFallback = t.base
    }
}

/// The Frost theme's base tones in one appearance.
private struct FrostTones {
    let light: Bool
    let base: Color
    let nested: Color
    let raised: Color
    let ink: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let keyline: Color
    let hover: Color
    let selection: Color
    let coral: Color
    let coralInk: Color

    init(light: Bool) {
        self.light = light
        base = Self.rgb(light ? 0xf1f2f4 : 0x28292c)
        nested = Self.rgb(light ? 0xf7f8fa : 0x303135)
        raised = Self.rgb(light ? 0xf9fafb : 0x343539)
        ink = light ? .black : .white
        primary = Self.rgb(light ? 0x202124 : 0xf0f0f2)
        secondary = Self.rgb(light ? 0x606165 : 0xb8b9bd)
        tertiary = Self.rgb(light ? 0x85868a : 0x939499)
        keyline = ink.opacity(light ? 0.08 : 0.10)
        hover = ink.opacity(light ? 0.055 : 0.075)
        selection = ink.opacity(light ? 0.095 : 0.13)
        coral = Self.rgb(light ? 0xc3474e : 0xba535b)
        coralInk = light ? coral : Self.rgb(0xdf8a8e)
    }

    static func rgb(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 255) / 255,
              green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255)
    }
}
