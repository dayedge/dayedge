import AppKit
import Observation
import SwiftUI
import XCTest

@testable import Shell
@testable import UI

@MainActor
final class AppearanceTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "AppearanceTests-\(UUID().uuidString)")!
    }

    func testMissingAndUnknownThemeUseGraphiteProDark() {
        let d = defaults()
        let store = AppearanceStore(defaults: d, observesSystem: false)
        XCTAssertEqual(store.themeID, "graphite-pro")
        XCTAssertEqual(store.colorScheme, .dark)
        d.set("removed-theme", forKey: AppearanceStore.themeKey)
        let restored = AppearanceStore(defaults: d, observesSystem: false)
        XCTAssertEqual(restored.themeID, "graphite-pro")
    }

    func testAllThemeSelectionsPersistAndRestore() {
        let d = defaults()
        let store = AppearanceStore(defaults: d, observesSystem: false)
        XCTAssertEqual(Set(ThemeCatalog.themes.map(\.id)).count, 8)
        for definition in ThemeCatalog.themes {
            store.selectTheme(definition.id)
            XCTAssertEqual(d.string(forKey: AppearanceStore.themeKey), definition.id)
            XCTAssertEqual(AppearanceStore(defaults: d, observesSystem: false).themeID, definition.id)
        }
        store.selectTheme("invalid")
        XCTAssertEqual(store.themeID, "graphite-pro")
    }

    func testFixedThemesIgnoreSystemAppearanceAndSystemThemeFollowsIt() {
        let store = AppearanceStore(defaults: defaults(), observesSystem: false)
        for (id, scheme) in [("opal", ColorScheme.dark), ("apple-light", .light), ("apple-dark", .dark), ("one-dark-pro", .dark), ("graphite-pro", .dark), ("quartz-pro", .light)] {
            store.selectTheme(id)
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                store.updateSystemAppearance(NSAppearance(named: name)!)
                XCTAssertEqual(store.colorScheme, scheme)
                XCTAssertEqual(store.preferredColorScheme, scheme)
            }
        }
        store.selectTheme("apple-system")
        XCTAssertNil(store.preferredColorScheme)
        for (name, light) in [(NSAppearance.Name.aqua, true), (.darkAqua, false)] {
            store.updateSystemAppearance(NSAppearance(named: name)!)
            XCTAssertEqual(store.palette.isLight, light)
            XCTAssertEqual(store.colorScheme, light ? .light : .dark)
        }
    }

    func testSelectionInvalidatesObserversWithoutReplacingStore() {
        let store = AppearanceStore(defaults: defaults(), observesSystem: false)
        let changed = expectation(description: "Palette invalidates its observer")
        withObservationTracking {
            _ = store.palette.background
        } onChange: {
            changed.fulfill()
        }
        store.selectTheme("apple-light")
        wait(for: [changed], timeout: 1)
        XCTAssertTrue(store.palette.isLight)
    }

    func testAppleLightHasContrastingTodayTextAndSubduedEventFill() {
        let p = ThemePalette.appleLight
        assertColor(p.todayText, .white)
        assertColor(p.selectedDayText, p.primaryText, appearance: .aqua)
        XCTAssertLessThan(p.eventFillOpacity, ThemePalette.appleDark.eventFillOpacity)
        assertColor(p.background, .white)
        assertColor(p.todayAccent, Color(nsColor: .systemRed), appearance: .aqua)
    }

    func testAppleLightUsesNeutralCalendarHierarchyAndSelection() {
        let light = ThemePalette.appleLight
        assertColor(light.calendarHeader.yearText, light.primaryText.opacity(0.72), appearance: .aqua)
        assertColor(light.calendarHeader.todayTitleText, light.primaryText, appearance: .aqua)
        assertColor(light.selectedWeekBand, .clear, appearance: .aqua)
        assertColor(light.selectedDayFill, Color.black.opacity(0.075), appearance: .aqua)
        XCTAssertEqual(light.calendarHeader.titleFont, .system(size: 26, weight: .bold))
        XCTAssertEqual(light.calendarHeader.yearFont, .system(size: 26, weight: .regular))
        XCTAssertTrue(light.viewSwitcherUsesMaterial)
        XCTAssertFalse(ThemePalette.opal.viewSwitcherUsesMaterial)
        assertColor(ThemePalette.opal.calendarHeader.yearText, ThemePalette.opal.accentRed)
        let store = AppearanceStore(defaults: defaults(), observesSystem: false)
        store.selectTheme("apple-system")
        store.updateSystemAppearance(NSAppearance(named: .aqua)!)
        assertColor(store.palette.selectedWeekBand, .clear, appearance: .aqua)
        XCTAssertTrue(store.palette.viewSwitcherUsesMaterial)
    }

    func testAppleDarkSharesNeutralHierarchyWithLight() {
        let dark = ThemePalette.appleDark
        let light = ThemePalette.appleLight
        assertColor(dark.calendarHeader.yearText, dark.primaryText.opacity(0.72))
        assertColor(dark.calendarHeader.todayTitleText, dark.primaryText)
        assertColor(dark.selectedWeekBand, .clear)
        assertColor(dark.selectedDayFill, Color.white.opacity(0.12))
        assertColor(dark.chrome.rowSelection, Color.white.opacity(0.065))
        assertColor(dark.chrome.slotSelected, Color.white.opacity(0.12))
        XCTAssertEqual(dark.calendarHeader.titleFont, light.calendarHeader.titleFont)
        XCTAssertEqual(dark.calendarHeader.yearFont, light.calendarHeader.yearFont)
        XCTAssertTrue(dark.viewSwitcherUsesMaterial)
        assertColor(dark.todayAccent, Color(nsColor: .systemRed))
        XCTAssertEqual(dark.eventFillOpacity, 0.55)
        let store = AppearanceStore(defaults: defaults(), observesSystem: false)
        store.selectTheme("apple-system")
        store.updateSystemAppearance(NSAppearance(named: .darkAqua)!)
        assertColor(store.palette.selectedWeekBand, .clear)
        assertColor(store.palette.calendarHeader.yearText, dark.calendarHeader.yearText)
        XCTAssertTrue(store.palette.viewSwitcherUsesMaterial)
    }

    func testTakeoverFixedBackdropsAreOpalsWhateverTheTheme() {
        let d = defaults()
        for (choice, style) in [(TakeoverBackdropChoice.graphite, TakeoverBackdropStyle.graphite), (.frosted, .frostedGlass)] {
            d.set(choice.rawValue, forKey: MeetingHUDSettings.takeoverBackdropKey)
            for theme in [ThemePalette.opal, .appleLight, .graphitePro, .quartzPro] {
                XCTAssertEqual(TakeoverBackdropStyle.current(defaults: d, theme: theme), style)
            }
            let fixed = try! XCTUnwrap(choice.fixedTheme)
            XCTAssertEqual(fixed.colorScheme, .dark)
            assertColor(fixed.palette.background, ThemePalette.opal.background)
        }
    }

    func testTakeoverThemeBackdropIsTheDefaultAndAdaptsLightContrast() {
        let d = defaults()
        XCTAssertEqual(TakeoverBackdropChoice.stored(in: d), .theme)
        XCTAssertNil(TakeoverBackdropChoice.theme.fixedTheme)
        XCTAssertEqual(TakeoverBackdropStyle.current(defaults: d), .graphite)
        let light = TakeoverBackdropStyle.current(defaults: d, theme: .appleLight)
        XCTAssertEqual(light.material, TakeoverBackdropStyle.graphite.material)
        XCTAssertEqual(light.floorOpacity, 0)
        assertColor(light.dimming, ThemePalette.appleLight.meetingTakeover.dimming, appearance: .aqua)
    }

    // Exact pre-theming palette: protects the legacy look during future theme changes.
    func testOpalPreservesOriginalPalette() {
        let p = ThemePalette.opal
        let original_background = Color(red: 0.11, green: 0.11, blue: 0.115)
        let original_selectedWeekBand = Color.white.opacity(0.06)
        let original_selectedDayFill = Color.white.opacity(0.32)
        let original_todayFill = Color(red: 0.30, green: 0.62, blue: 1.0).opacity(0.55)
        let original_primaryText = Color.white
        let original_secondaryText = Color.white.opacity(0.55)
        let original_dimmedText = Color.white.opacity(0.28)
        let original_timelineCapsule = original_background.opacity(0.9)
        let original_controlSurface = Color.black.opacity(0.35)
        let original_searchSurface = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x13 / 255)
        let original_SecondaryControl_fill = Color.white.opacity(0.035)
        let original_SecondaryControl_hover = Color.white.opacity(0.07)
        let original_SecondaryControl_pressed = Color.white.opacity(0.10)
        let original_SecondaryControl_border = Color.white.opacity(0.08)
        let original_SecondaryControl_divider = Color.white.opacity(0.07)
        let original_accentRed = Color(red: 0.93, green: 0.23, blue: 0.23)
        let original_currentTimeCapsule = original_accentRed.opacity(0.8)
        let original_destructiveRed = Color(nsColor: .systemRed)
        let original_accentBlue = Color(red: 0.30, green: 0.62, blue: 1.0)
        let original_successGreen = Color.green
        let original_Conflict_busy = Color(nsColor: .systemRed)
        let original_Conflict_unconfirmed = Color(nsColor: .systemYellow)
        let original_Conflict_free = Color(nsColor: .systemGreen)
        let original_holidayTint = Color(nsColor: .systemRed).opacity(0.65)
        let original_weekendDayTint = original_accentBlue.opacity(0.9)
        let original_dotOrange = Color(red: 0.95, green: 0.66, blue: 0.16)
        let original_selectionYellow = Color(red: 1.0, green: 0.84, blue: 0.3)
        let original_MeetingTakeover_dimming = Color.black.opacity(0.20)
        let original_MeetingTakeover_highContrastDimming = Color.black.opacity(0.35)
        let original_MeetingTakeover_opaqueFallback = Color(red: 0.19, green: 0.20, blue: 0.23)
        let original_MeetingTakeover_approaching = Color(red: 1.0, green: 0.72, blue: 0.38)
        let original_MeetingTakeover_started = Color(red: 1.0, green: 0.43, blue: 0.40)
        let original_MeetingTakeover_actionSurface = Color.white.opacity(0.17)
        let original_MeetingTakeover_actionSurfaceHover = Color.white.opacity(0.24)
        let original_MeetingTakeover_actionKeyline = Color.white.opacity(0.18)
        let original_Keycap_largeFill = Color.white.opacity(0.15)
        let original_Keycap_largeGlyph = Color.white.opacity(0.75)
        let original_Keycap_compactFill = Color.white.opacity(0.07)
        let original_Keycap_compactStroke = Color.white.opacity(0.1)
        let original_Keycap_compactGlyph = Color.white.opacity(0.78)
        let original_Keycap_actionLabel = Color.white.opacity(0.68)
        let original_DateTile_tileFill = Color.white.opacity(0.06)
        let original_DateTile_tileBorder = Color.white.opacity(0.1)
        let original_DateTile_weekdayBand = Color(red: 0.62, green: 0.20, blue: 0.19)
        let original_DateTile_weekdayTint = Color.white
        let original_DateTile_dayTint = original_primaryText
        let original_DateTile_todayTint = original_accentBlue
        let original_DateTile_monthTint = original_secondaryText.opacity(0.8)
        let original_Search_groupLabelTint = original_secondaryText
        let original_PeriodHeader_color = Color.white.opacity(0.6)
        let original_Chat_toolbarIcon = Color.white.opacity(0.70)
        let original_Chat_toolbarIconHover = Color.white.opacity(0.90)
        let original_Chat_toolbarIconDisabled = Color.white.opacity(0.25)
        let original_Chat_inlineTitle = Color.white.opacity(0.85)
        let original_Chat_jumpButtonBorder = Color.white.opacity(0.12)
        let original_Chat_dateHoverFill = Color.white.opacity(0.05)
        let original_Chat_assistantText = Color.white.opacity(0.84)
        let original_Chat_userBubbleFill = original_accentBlue.mix(with: .black, by: 0.28)
        let original_Chat_userBubbleText = Color.white
        let original_Chat_accent = original_Chat_userBubbleFill
        let original_Chat_composerFill = Color.white.opacity(0.06)
        let original_Chat_composerStroke = Color.white.opacity(0.10)
        let original_Chat_composerStrokeIncreased = Color.white.opacity(0.20)
        let original_Chat_composerFocusedStroke = Color.white.opacity(0.16)
        let original_Chat_composerText = Color.white.opacity(0.90)
        let original_Chat_composerPlaceholder = Color.white.opacity(0.40)
        let original_Chat_sendEnabledGlyph = Color.white
        let original_Chat_sendDisabledFill = Color.white.opacity(0.10)
        let original_Chat_sendDisabledGlyph = Color.white.opacity(0.30)
        let original_Chat_stopFill = Color.white.opacity(0.18)
        let original_Chat_stopGlyph = Color.white.opacity(0.90)
        let original_Chat_cardFill = Color.white.opacity(0.07)
        let original_Chat_cardStroke = Color.white.opacity(0.12)
        let original_Chat_cardHeadline = Color.white.opacity(0.62)
        let original_Chat_destructive = original_accentRed
        let original_Chat_receiptDone = Color.green.opacity(0.85)
        let original_Chat_receiptMuted = Color.white.opacity(0.45)
        let original_Chat_chipFill = Color.white.opacity(0.06)
        let original_Chat_chipHoverFill = Color.white.opacity(0.10)
        let original_Chat_chipPressedFill = Color.white.opacity(0.14)
        let original_Chat_chipBorder = Color.white.opacity(0.10)
        let original_Chat_chipBorderIncreased = Color.white.opacity(0.20)
        let original_Chat_chipLabel = Color.white.opacity(0.85)
        let original_Chat_chipLabelHover = Color.white
        let original_Chat_chipIcon = Color.white.opacity(0.55)
        let original_Chat_chipIconHover = Color.white.opacity(0.75)
        let original_Settings_background = original_background
        let original_Settings_sidebarBackground = Color(red: 0.085, green: 0.085, blue: 0.09)
        let original_Settings_groupFill = Color.white.opacity(0.045)
        let original_Settings_groupBorder = original_SecondaryControl_border
        let original_Settings_divider = original_SecondaryControl_divider
        let original_Settings_primaryText = original_primaryText
        let original_Settings_secondaryText = original_secondaryText
        let original_Settings_tint = original_accentBlue
        let original_Settings_granted = Color(nsColor: .systemGreen)
        let original_Settings_denied = Color(nsColor: .systemRed)
        let original_Settings_pending = Color.white.opacity(0.35)
        let original_Settings_attention = Color(nsColor: .systemOrange)
        let original_Tasks_attentionTint = original_accentRed.opacity(0.85)
        let original_Tasks_timelineCardFill = Color.white.opacity(0.09)
        let original_Tasks_timelineCardHoverFill = Color.white.opacity(0.12)
        let original_Tasks_timelineCardSelectedFill = Color.white.opacity(0.16)
        let original_Tasks_timelineCardKeyline = Color.white.opacity(0.08)
        let original_Tasks_timelineDueTick = original_secondaryText.opacity(0.5)
        assertColor(p.background, original_background)
        assertColor(p.selectedWeekBand, original_selectedWeekBand)
        assertColor(p.selectedDayFill, original_selectedDayFill)
        assertColor(p.todayFill, original_todayFill)
        assertColor(p.primaryText, original_primaryText)
        assertColor(p.secondaryText, original_secondaryText)
        assertColor(p.dimmedText, original_dimmedText)
        assertColor(p.currentTimeCapsule, original_currentTimeCapsule)
        assertColor(p.timelineCapsule, original_timelineCapsule)
        assertColor(p.controlSurface, original_controlSurface)
        assertColor(p.searchSurface, original_searchSurface)
        assertColor(p.secondaryControl.fill, original_SecondaryControl_fill)
        assertColor(p.secondaryControl.hover, original_SecondaryControl_hover)
        assertColor(p.secondaryControl.pressed, original_SecondaryControl_pressed)
        assertColor(p.secondaryControl.border, original_SecondaryControl_border)
        assertColor(p.secondaryControl.divider, original_SecondaryControl_divider)
        assertColor(p.accentRed, original_accentRed)
        assertColor(p.destructiveRed, original_destructiveRed)
        assertColor(p.controlAccent, original_accentBlue)
        assertColor(p.successGreen, original_successGreen)
        assertColor(p.conflict.busy, original_Conflict_busy)
        assertColor(p.conflict.unconfirmed, original_Conflict_unconfirmed)
        assertColor(p.conflict.free, original_Conflict_free)
        assertColor(p.holidayTint, original_holidayTint)
        assertColor(p.weekendDayTint, original_weekendDayTint)
        assertColor(p.dotOrange, original_dotOrange)
        assertColor(p.detailSelectionAccent, original_selectionYellow)
        assertColor(p.meetingTakeover.dimming, original_MeetingTakeover_dimming)
        assertColor(p.meetingTakeover.highContrastDimming, original_MeetingTakeover_highContrastDimming)
        assertColor(p.meetingTakeover.opaqueFallback, original_MeetingTakeover_opaqueFallback)
        assertColor(p.meetingTakeover.approaching, original_MeetingTakeover_approaching)
        assertColor(p.meetingTakeover.started, original_MeetingTakeover_started)
        assertColor(p.meetingTakeover.actionSurface, original_MeetingTakeover_actionSurface)
        assertColor(p.meetingTakeover.actionSurfaceHover, original_MeetingTakeover_actionSurfaceHover)
        assertColor(p.meetingTakeover.actionKeyline, original_MeetingTakeover_actionKeyline)
        assertColor(p.keycap.largeFill, original_Keycap_largeFill)
        assertColor(p.keycap.largeGlyph, original_Keycap_largeGlyph)
        assertColor(p.keycap.compactFill, original_Keycap_compactFill)
        assertColor(p.keycap.compactStroke, original_Keycap_compactStroke)
        assertColor(p.keycap.compactGlyph, original_Keycap_compactGlyph)
        assertColor(p.keycap.actionLabel, original_Keycap_actionLabel)
        assertColor(p.dateTile.tileFill, original_DateTile_tileFill)
        assertColor(p.dateTile.tileBorder, original_DateTile_tileBorder)
        assertColor(p.dateTile.weekdayBand, original_DateTile_weekdayBand)
        assertColor(p.dateTile.weekdayTint, original_DateTile_weekdayTint)
        assertColor(p.dateTile.dayTint, original_DateTile_dayTint)
        assertColor(p.dateTile.todayTint, original_DateTile_todayTint)
        assertColor(p.dateTile.monthTint, original_DateTile_monthTint)
        assertColor(p.search.groupLabelTint, original_Search_groupLabelTint)
        assertColor(p.periodHeader.color, original_PeriodHeader_color)
        assertColor(p.chat.toolbarIcon, original_Chat_toolbarIcon)
        assertColor(p.chat.toolbarIconHover, original_Chat_toolbarIconHover)
        assertColor(p.chat.toolbarIconDisabled, original_Chat_toolbarIconDisabled)
        assertColor(p.chat.inlineTitle, original_Chat_inlineTitle)
        assertColor(p.chat.jumpButtonBorder, original_Chat_jumpButtonBorder)
        assertColor(p.chat.dateHoverFill, original_Chat_dateHoverFill)
        assertColor(p.chat.assistantText, original_Chat_assistantText)
        assertColor(p.chat.userBubbleFill, original_Chat_userBubbleFill)
        assertColor(p.chat.userBubbleText, original_Chat_userBubbleText)
        assertColor(p.chat.accent, original_Chat_accent)
        assertColor(p.chat.composerFill, original_Chat_composerFill)
        assertColor(p.chat.composerStroke, original_Chat_composerStroke)
        assertColor(p.chat.composerStrokeIncreased, original_Chat_composerStrokeIncreased)
        assertColor(p.chat.composerFocusedStroke, original_Chat_composerFocusedStroke)
        assertColor(p.chat.composerText, original_Chat_composerText)
        assertColor(p.chat.composerPlaceholder, original_Chat_composerPlaceholder)
        assertColor(p.chat.sendEnabledGlyph, original_Chat_sendEnabledGlyph)
        assertColor(p.chat.sendDisabledFill, original_Chat_sendDisabledFill)
        assertColor(p.chat.sendDisabledGlyph, original_Chat_sendDisabledGlyph)
        assertColor(p.chat.stopFill, original_Chat_stopFill)
        assertColor(p.chat.stopGlyph, original_Chat_stopGlyph)
        assertColor(p.chat.cardFill, original_Chat_cardFill)
        assertColor(p.chat.cardStroke, original_Chat_cardStroke)
        assertColor(p.chat.cardHeadline, original_Chat_cardHeadline)
        assertColor(p.chat.destructive, original_Chat_destructive)
        assertColor(p.chat.receiptDone, original_Chat_receiptDone)
        assertColor(p.chat.receiptMuted, original_Chat_receiptMuted)
        assertColor(p.chat.chipFill, original_Chat_chipFill)
        assertColor(p.chat.chipHoverFill, original_Chat_chipHoverFill)
        assertColor(p.chat.chipPressedFill, original_Chat_chipPressedFill)
        assertColor(p.chat.chipBorder, original_Chat_chipBorder)
        assertColor(p.chat.chipBorderIncreased, original_Chat_chipBorderIncreased)
        assertColor(p.chat.chipLabel, original_Chat_chipLabel)
        assertColor(p.chat.chipLabelHover, original_Chat_chipLabelHover)
        assertColor(p.chat.chipIcon, original_Chat_chipIcon)
        assertColor(p.chat.chipIconHover, original_Chat_chipIconHover)
        assertColor(p.settings.background, original_Settings_background)
        assertColor(p.settings.sidebarBackground, original_Settings_sidebarBackground)
        assertColor(p.settings.groupFill, original_Settings_groupFill)
        assertColor(p.settings.groupBorder, original_Settings_groupBorder)
        assertColor(p.settings.divider, original_Settings_divider)
        assertColor(p.settings.primaryText, original_Settings_primaryText)
        assertColor(p.settings.secondaryText, original_Settings_secondaryText)
        assertColor(p.settings.tint, original_Settings_tint)
        assertColor(p.settings.granted, original_Settings_granted)
        assertColor(p.settings.denied, original_Settings_denied)
        assertColor(p.settings.pending, original_Settings_pending)
        assertColor(p.settings.attention, original_Settings_attention)
        assertColor(p.tasks.attentionTint, original_Tasks_attentionTint)
        assertColor(p.tasks.timelineCardFill, original_Tasks_timelineCardFill)
        assertColor(p.tasks.timelineCardHoverFill, original_Tasks_timelineCardHoverFill)
        assertColor(p.tasks.timelineCardSelectedFill, original_Tasks_timelineCardSelectedFill)
        assertColor(p.tasks.timelineCardKeyline, original_Tasks_timelineCardKeyline)
        assertColor(p.tasks.timelineDueTick, original_Tasks_timelineDueTick)
        assertColor(p.detail.hoverFill, Color.white.opacity(0.06))
        assertColor(p.detail.activeFill, Color.white.opacity(0.10))
        assertColor(p.floatingKeyline, Color.white.opacity(0.09))
        assertColor(p.floatingShadow, Color.black.opacity(0.28))
    }

    func testOpalPreservesExtractedControlStates() {
        let p = ThemePalette.opal
        assertColor(p.nativeControlAccent, Color.accentColor)
        assertColor(p.chrome.rowHover, Color.white.opacity(0.06))
        assertColor(p.chrome.rowSelection, Color.white.opacity(0.09))
        assertColor(p.chrome.gridRule, Color.white.opacity(0.08))
        assertColor(p.chrome.inputFill, Color.white.opacity(0.065))
        assertColor(p.chrome.inputFocus, Color.white.opacity(0.11))
        assertColor(p.chrome.slotSelected, Color.white.opacity(0.20))
        assertColor(p.chrome.slotSelectedPressed, Color.white.opacity(0.28))
        assertColor(p.chrome.searchScrim, Color.black.opacity(0.10))
        assertColor(p.chrome.tooltipShadow, Color.black.opacity(0.35))
        assertColor(p.meetingTakeover.metadataHover, Color.white.opacity(0.78))
        assertColor(p.meetingTakeover.quietActionFill, Color.white.opacity(0.08))
        assertColor(p.keycap.onAccentLargeGlyph, Color.white.opacity(0.75))
        assertColor(p.keycap.onAccentLargeFill, Color.white.opacity(0.15))
    }

    func testExtractedStateTokensPreserveExistingAppearance() {
        for p in [ThemePalette.opal, .appleLight, .appleDark] {
            let appearance: NSAppearance.Name = p.isLight ? .aqua : .darkAqua
            let colors: [(Color, Color)] = [
                (p.content.detailSelectionFill, p.detailSelectionAccent.opacity(0.16)),
                (p.content.tentativeText, p.primaryText.opacity(0.65)),
                (p.content.tentativeMetadata, p.secondaryText.opacity(0.7)),
                (p.content.cancelledText, p.secondaryText),
                (p.content.cancelledMetadata, p.dimmedText),
                (p.content.cancelledTimelineText, p.primaryText.opacity(0.5)),
                (p.content.cancelledTimelineFill, p.secondaryText.opacity(0.12)),
                (p.content.ongoingIndicator, p.accentRed.opacity(0.8)),
                (p.content.quietMetadata, p.secondaryText.opacity(0.6)),
                (p.content.subduedMetadata, p.secondaryText.opacity(0.7)),
                (p.content.detailMetadata, p.secondaryText.opacity(0.8)),
                (p.content.sourceLabelFallback, p.primaryText.opacity(0.92)),
                (p.editor.text, p.primaryText.opacity(0.92)),
                (p.editor.focusRing, p.nativeControlAccent.opacity(0.75)),
                (p.editor.selectionFill, p.nativeControlAccent.opacity(0.85))
            ]
            for (actual, expected) in colors { assertColor(actual, expected, appearance: appearance) }
            let strengths = p.sourcePresentation
            XCTAssertEqual(strengths.completedTaskOpacity, 0.5)
            XCTAssertEqual(strengths.taskHoverCheckOpacity, 0.55)
            XCTAssertEqual(strengths.readOnlyTaskOpacity, 0.45)
            XCTAssertEqual(strengths.tentativeMarkerOpacity, 0.7)
            XCTAssertEqual(strengths.eventBorderOpacity, 0.5)
            XCTAssertEqual(strengths.tentativeStripeOpacity, 0.45)
            XCTAssertEqual(strengths.joinFillOpacity, 0.15)
            XCTAssertEqual(strengths.allDayFillOpacity, 0.22)
            XCTAssertEqual(strengths.allDayHoverFillOpacity, 0.30)
            XCTAssertEqual(strengths.allDayBorderOpacity, 0.28)
            XCTAssertEqual(strengths.allDayHoverBorderOpacity, 0.32)
            XCTAssertEqual(strengths.timelineMetadataOpacity, 0.75)
            XCTAssertEqual(strengths.timelineGlyphOpacity, 0.7)
        }
    }

    func testAppleBubbleRefinementLeavesEveryOtherPaletteColorUnchanged() {
        func colors(_ value: Any, prefix: String = "") -> [String: Color] {
            if let color = value as? Color { return [prefix: color] }
            if value is Font || value is Double || value is Bool { return [:] }
            var result: [String: Color] = [:]
            for child in Mirror(reflecting: value).children {
                guard let label = child.label else { continue }
                result.merge(colors(child.value, prefix: prefix.isEmpty ? label : "\(prefix).\(label)")) { a, _ in a }
            }
            return result
        }
        for (refined, original, appearance) in [
            (ThemePalette.appleLight, ThemePalette.appleSystemLight, NSAppearance.Name.aqua),
            (ThemePalette.appleDark, ThemePalette.appleSystemDark, NSAppearance.Name.darkAqua)
        ] {
            let actual = colors(refined.values)
            let baseline = colors(original.values)
            XCTAssertEqual(Set(actual.keys), Set(baseline.keys))
            for (path, color) in actual where path != "chat.userBubbleFill" {
                assertColor(color, baseline[path]!, appearance: appearance)
            }
            assertColor(refined.chat.userBubbleText, .white, appearance: appearance)
            assertColor(refined.chat.userBubbleFill,
                Color(nsColor: .systemBlue).mix(with: .gray, by: 0.08)
                    .mix(with: .black, by: refined.isLight ? 0.10 : 0.18), appearance: appearance)
            let store = AppearanceStore(defaults: defaults(), observesSystem: false)
            store.selectTheme("apple-system")
            store.updateSystemAppearance(NSAppearance(named: appearance)!)
            assertColor(store.palette.chat.userBubbleFill, original.chat.userBubbleFill, appearance: appearance)
        }
    }

    func testProfessionalDarkThemesHaveReadableTextAndPrimaryActions() {
        func contrast(_ foreground: Color, _ background: Color) -> Double {
            func luminance(_ color: Color) -> Double {
                let rgb = NSColor(color).usingColorSpace(.deviceRGB)!
                let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { value in
                    let v = Double(value)
                    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
                }
                return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
            }
            let a = luminance(foreground), b = luminance(background)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        for p in [ThemePalette.oneDarkPro, .graphitePro] {
            XCTAssertFalse(p.isLight)
            let d = defaults()
            d.set(TakeoverBackdropChoice.theme.rawValue, forKey: MeetingHUDSettings.takeoverBackdropKey)
            assertColor(TakeoverBackdropStyle.current(defaults: d, theme: p).dimming, p.meetingTakeover.dimming)
            XCTAssertGreaterThanOrEqual(contrast(p.primaryText, p.background), 7)
            XCTAssertGreaterThanOrEqual(contrast(p.secondaryText, p.background), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(p.chat.userBubbleText, p.chat.userBubbleFill), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(p.onAccentText, p.nativeControlAccent), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(p.onAccentText, p.controlAccent), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(p.todayText, p.todayFill), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(p.currentTimeText, p.currentTimeCapsule), 4.5)
            assertColor(p.selectedWeekBand, .clear)
            XCTAssertEqual(p.calendarHeader.titleFont, ThemePalette.appleDark.calendarHeader.titleFont)
        }
    }

    /// The bottom selector and Settings are the view switcher's siblings:
    /// the same height and surface in every theme, a keyline only where the
    /// theme draws compact controls with one.
    func testPersistentChromeIsTheSwitchersFamilyInEveryTheme() {
        XCTAssertEqual(PersistentChromeMetrics.height, ViewModeSwitcherView.width(folded: true))
        for definition in ThemeCatalog.themes {
            for scheme in [ColorScheme.light, .dark] {
                let p = definition.palette(scheme)
                let appearance: NSAppearance.Name = p.isLight ? .aqua : .darkAqua
                assertColor(p.persistentChromeSurface, p.controlSurface, appearance: appearance)
                assertColor(p.persistentChromeHoverSurface, p.chrome.slotHover, appearance: appearance)
                assertColor(p.persistentChromeDivider, p.chrome.divider, appearance: appearance)
                XCTAssertEqual(p.persistentChromeKeyline == nil, p.compactControl == nil, definition.id)
            }
        }
        // Translucent over the agenda: a material under every theme's chrome
        // (Frost's is its own glass role); a smoked tint only where asked.
        for p in [ThemePalette.opal, .appleLight, .appleDark, .graphitePro, .quartzPro, .oneDarkPro] {
            XCTAssertNotNil(p.persistentChromeMaterial)
        }
        XCTAssertNil(ThemePalette.frost(light: true).persistentChromeMaterial)
        XCTAssertNotNil(ThemePalette.frost(light: true).surfaces?.floatingControl)
        XCTAssertEqual(ThemePalette.graphitePro.persistentChromeTintOpacity, 0.8)
        XCTAssertEqual(ThemePalette.quartzPro.persistentChromeTintOpacity, 0.85)
        XCTAssertEqual(ThemePalette.appleLight.persistentChromeTintOpacity, 1)
        XCTAssertNil(ThemePalette.appleLight.persistentChromeKeyline)
        XCTAssertNotNil(ThemePalette.graphitePro.persistentChromeKeyline)
        XCTAssertNotNil(ThemePalette.quartzPro.persistentChromeKeyline)
    }

    /// Frost's agenda is one continuous frosted surface: day headers on the
    /// agenda's own material, not sticking, a hairline between days. Every
    /// other theme keeps its sticky, backed headers exactly as they were.
    func testOnlyFrostTradesStickyHeaderBandsForAHairline() {
        for light in [true, false] {
            let frost = ThemePalette.frost(light: light)
            XCTAssertFalse(frost.pinsAgendaSectionHeaders)
            XCTAssertEqual(frost.agendaPinnedViews, [])
            XCTAssertTrue(frost.showsAgendaSectionSeparator)
            assertColor(frost.agendaHeaderFill(for: .inlineAgenda), .clear)
            assertColor(frost.agendaHeaderFill(for: .popoverAgenda), .clear)
        }
        for p in [ThemePalette.opal, .appleLight, .appleDark, .appleSystemLight, .appleSystemDark,
                  .oneDarkPro, .graphitePro, .quartzPro] {
            XCTAssertTrue(p.pinsAgendaSectionHeaders)
            XCTAssertEqual(p.agendaPinnedViews, [.sectionHeaders])
            XCTAssertFalse(p.showsAgendaSectionSeparator)
            XCTAssertNil(p.agendaHeader)
        }
    }

    func testPaletteCopiesAreOneSharedReference() {
        XCTAssertEqual(MemoryLayout<ThemePalette>.size, MemoryLayout<AnyObject>.size)
        let copy = ThemePalette.appleLight
        XCTAssertTrue(copy.sharesStorage(with: .appleLight))
    }

    func testEditingAPaletteCopyNeverChangesTheOriginal() {
        let original = ThemePalette.appleLight
        var edited = original
        edited.background = .red
        edited.calendarHeader.yearText = .red
        edited.chat.toolbarIcon = .red
        edited.sourcePresentation.joinFillOpacity = 0.9
        XCTAssertFalse(edited.sharesStorage(with: original))
        for color in [edited.background, edited.calendarHeader.yearText, edited.chat.toolbarIcon] {
            assertColor(color, .red, appearance: .aqua)
        }
        XCTAssertEqual(edited.sourcePresentation.joinFillOpacity, 0.9)
        assertColor(ThemePalette.appleLight.background, .white, appearance: .aqua)
        assertColor(ThemePalette.appleLight.calendarHeader.yearText,
                    ThemePalette.appleSystemLight.calendarHeader.yearText, appearance: .aqua)
        assertColor(ThemePalette.appleLight.chat.toolbarIcon,
                    ThemePalette.appleSystemLight.chat.toolbarIcon, appearance: .aqua)
        XCTAssertEqual(ThemePalette.appleLight.sourcePresentation.joinFillOpacity, 0.15)
        // Derived themes built from the same base stay their own.
        XCTAssertFalse(ThemePalette.quartzPro.sharesStorage(with: .appleLight))
        XCTAssertFalse(ThemePalette.graphitePro.sharesStorage(with: .appleDark))
    }

    func testThemeSwitchesHandOutADifferentPaletteAndTheSameThemeTheSameOne() {
        let store = AppearanceStore(defaults: defaults(), observesSystem: false)
        store.selectTheme("graphite-pro")
        let graphite = store.palette
        XCTAssertTrue(store.palette.sharesStorage(with: graphite))
        store.selectTheme("quartz-pro")
        XCTAssertFalse(store.palette.sharesStorage(with: graphite))
        XCTAssertTrue(store.palette.sharesStorage(with: .quartzPro))
        for id in ["frost", "apple-system"] {
            store.selectTheme(id)
            store.updateSystemAppearance(NSAppearance(named: .aqua)!)
            let light = store.palette
            XCTAssertTrue(store.palette.sharesStorage(with: light), id)
            XCTAssertTrue(light.isLight, id)
            store.updateSystemAppearance(NSAppearance(named: .darkAqua)!)
            XCTAssertFalse(store.palette.sharesStorage(with: light), id)
            XCTAssertFalse(store.palette.isLight, id)
        }
    }

    func testQuartzProIsAnOpaqueReadableLightTheme() {
        func contrast(_ foreground: Color, _ background: Color) -> Double {
            func luminance(_ color: Color) -> Double {
                let c = NSColor(color).usingColorSpace(.sRGB)!
                return [c.redComponent, c.greenComponent, c.blueComponent].map { value -> Double in
                    let v = Double(value)
                    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
                }.enumerated().map { $1 * [0.2126, 0.7152, 0.0722][$0] }.reduce(0, +)
            }
            let a = luminance(foreground), b = luminance(background)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        let p = ThemePalette.quartzPro
        XCTAssertTrue(p.isLight)
        XCTAssertNil(p.surfaces)
        XCTAssertFalse(p.viewSwitcherUsesMaterial)
        XCTAssertGreaterThanOrEqual(contrast(p.primaryText, p.background), 7)
        XCTAssertGreaterThanOrEqual(contrast(p.secondaryText, p.background), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(p.onAccentText, p.nativeControlAccent), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(p.onAccentText, p.controlAccent), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(p.todayText, p.todayFill), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(p.currentTimeText, p.currentTimeCapsule), 4.5)
        assertColor(p.calendarHeader.yearText, p.secondaryText)
        assertColor(p.selectedWeekBand, .clear)
        // The canvas is not white: working surfaces sit above it.
        XCTAssertLessThan(contrast(p.background, .white), contrast(p.chrome.rowSelection, .white))
        XCTAssertGreaterThan(contrast(p.background, .white), contrast(p.searchSurface, .white))
    }

    func testGraphiteKeepsNeutralSelectionAndCalmsOnlyLargeEventSurfaces() {
        let p = ThemePalette.graphitePro
        assertColor(p.floatingKeyline, .white.opacity(0.08))
        assertColor(p.calendarHeader.yearText, p.secondaryText)
        assertColor(p.content.detailSelectionFill, p.chrome.rowSelection)
        assertColor(p.editor.selectionFill, p.chrome.rowSelection)
        assertColor(p.detailSelectionAccent, p.secondaryText)
        XCTAssertEqual(p.eventFillOpacity, 0.28)
        XCTAssertEqual(p.eventFillSaturation, 0.90)
        XCTAssertEqual(p.sourcePresentation.tentativeStripeOpacity, 0.32)
        XCTAssertEqual(p.sourcePresentation.tentativeStripeSaturation, 0.85)
        for other in [ThemePalette.opal, .appleLight, .appleDark, .appleSystemLight, .appleSystemDark, .oneDarkPro] {
            XCTAssertNil(other.workingSurface)
            XCTAssertNil(other.compactControl)
            XCTAssertEqual(other.semanticActionMix, 0)
            XCTAssertEqual(other.eventFillSaturation, 1)
            XCTAssertEqual(other.sourcePresentation.tentativeStripeOpacity, 0.45)
            XCTAssertEqual(other.sourcePresentation.tentativeStripeSaturation, 1)
            XCTAssertEqual(other.sourcePresentation.eventHoverBrightness, 0.06)
            XCTAssertEqual(other.sourcePresentation.eventOngoingBrightness, 0.035)
        }
    }

    func testSharedEditorTokensPreserveOtherThemes() {
        for p in [ThemePalette.opal, .appleLight, .appleDark, .appleSystemLight, .appleSystemDark, .oneDarkPro] {
            let appearance: NSAppearance.Name = p.isLight ? .aqua : .darkAqua
            let pairs: [(Color, Color)] = [
                (p.editor.titleText, p.primaryText), (p.editor.labelText, p.secondaryText),
                (p.editor.placeholderText, p.secondaryText), (p.editor.panelFill, p.chrome.rowHover),
                (p.editor.fieldFill, p.chrome.inputFill), (p.editor.fieldHoverFill, p.chrome.inputHover),
                (p.editor.fieldFocusedFill, p.chrome.inputFocus), (p.editor.fieldKeyline, p.chrome.inputKeyline),
                (p.editor.overlapBusyText, p.secondaryText), (p.editor.overlapUnconfirmedText, p.secondaryText)
            ]
            for (actual, expected) in pairs { assertColor(actual, expected, appearance: appearance) }
            XCTAssertEqual(p.editor.nativePlaceholderOpacity, 1)
        }
        let graphite = ThemePalette.graphitePro
        assertColor(graphite.editor.titleText, graphite.primaryText)
        assertColor(graphite.editor.labelText, graphite.secondaryText)
        assertColor(graphite.editor.fieldKeyline, .white.opacity(0.055))
        assertColor(graphite.editor.focusRing, .white.opacity(0.18))
        assertColor(graphite.editor.overlapBusyText, graphite.conflict.busy)
        XCTAssertEqual(graphite.editor.nativePlaceholderOpacity, 0.52)
    }

    func testFrostFollowsSystemAndOnlyMaterialThemesOptIn() throws {
        let store = AppearanceStore(defaults: defaults(), observesSystem: false)
        for definition in ThemeCatalog.themes where definition.id != "frost" {
            XCTAssertNil(definition.palette(.light).surfaces)
            XCTAssertNil(definition.palette(.dark).surfaces)
        }
        store.selectTheme("frost")
        XCTAssertNil(store.preferredColorScheme)
        for (name, light) in [(NSAppearance.Name.aqua, true), (.darkAqua, false)] {
            store.updateSystemAppearance(NSAppearance(named: name)!)
            let p = store.palette
            XCTAssertEqual(p.isLight, light)
            let surfaces = try XCTUnwrap(p.surfaces)
            guard case .desktop(.popover) = surfaces.window.backing else {
                return XCTFail("Window needs real desktop-backed blur")
            }
            guard case .local = surfaces.nested.backing else { return XCTFail("Nested editors keep local material") }
            for role in [SurfaceRole.elevated, .transient, .floatingControl, .selectedFloatingControl] {
                guard case .desktop(.popover) = surfaces[role].backing else {
                    return XCTFail("Floating glass must sample real background, not compound shell opacity")
                }
            }
            for role in [SurfaceRole.floatingControl, .selectedFloatingControl, .elevated, .transient] {
                XCTAssertTrue(surfaces[role].usesLiquidGlassOptics)
                XCTAssertNotNil(surfaces[role].lighting)
            }
            for role in [SurfaceRole.window, .nested, .control, .selection, .hover] {
                XCTAssertFalse(surfaces[role].usesLiquidGlassOptics)
                XCTAssertNil(surfaces[role].lighting)
            }
            XCTAssertGreaterThan(surfaces.selectedFloatingControl.tintOpacity, surfaces.floatingControl.tintOpacity)
            XCTAssertGreaterThan(surfaces.elevated.tintOpacity, surfaces.floatingControl.tintOpacity)
            let apple = light ? ThemePalette.appleLight : .appleDark
            assertColor(p.chat.userBubbleFill, apple.chat.userBubbleFill, appearance: name)
            assertColor(p.chat.userBubbleText, apple.chat.userBubbleText, appearance: name)
            for role in [SurfaceRole.control, .selection, .hover] {
                guard case .solid = surfaces[role].backing else { return XCTFail("Rows and controls must not add blur layers") }
            }
            for role in SurfaceRole.allCases {
                XCTAssertEqual(surfaces[role].effectiveOpacity(reduceTransparency: true, increaseContrast: false), 1)
                XCTAssertGreaterThanOrEqual(surfaces[role].effectiveOpacity(reduceTransparency: false, increaseContrast: true), 0.94)
            }
            assertColor(p.calendarHeader.yearText, p.secondaryText, appearance: name)
            assertColor(p.selectedWeekBand, .clear, appearance: name)
            assertColor(p.contentBackdrop, .clear, appearance: name)
            XCTAssertEqual(p.calendarHeader.titleFont, ThemePalette.appleLight.calendarHeader.titleFont)
            XCTAssertEqual(p.calendarHeader.yearFont, ThemePalette.appleLight.calendarHeader.yearFont)
            XCTAssertEqual(p.sourcePresentation.tentativeMarkerOpacity, ThemePalette.appleLight.sourcePresentation.tentativeMarkerOpacity)
        }
    }

    func testFrostTextContrastOnOpaqueMaterialFallbacks() throws {
        func luminance(_ color: Color) -> Double {
            let c = NSColor(color).usingColorSpace(.sRGB)!
            let values = [c.redComponent, c.greenComponent, c.blueComponent].map { value -> Double in
                let v = Double(value)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
        }
        func contrast(_ a: Color, _ b: Color) -> Double {
            let x = luminance(a), y = luminance(b)
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        for light in [true, false] {
            let p = ThemePalette.frost(light: light)
            let surfaces = try XCTUnwrap(p.surfaces)
            for role in [SurfaceRole.window, .nested, .elevated, .transient] {
                let fill = try XCTUnwrap(surfaces[role].tint)
                XCTAssertGreaterThanOrEqual(contrast(p.primaryText, fill), 7)
                XCTAssertGreaterThanOrEqual(contrast(p.secondaryText, fill), 4.5)
                XCTAssertGreaterThanOrEqual(contrast(p.editor.placeholderText, fill), 3)
            }
            XCTAssertGreaterThanOrEqual(contrast(p.todayText, p.todayFill), 4.5)
        }
    }

    private func assertColor(
        _ actual: Color, _ expected: Color, appearance: NSAppearance.Name = .darkAqua,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let a = NSColor(actual).usingColorSpace(.deviceRGB)!
            let b = NSColor(expected).usingColorSpace(.deviceRGB)!
            XCTAssertEqual(a.redComponent, b.redComponent, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(a.greenComponent, b.greenComponent, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(a.blueComponent, b.blueComponent, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(a.alphaComponent, b.alphaComponent, accuracy: 0.0001, file: file, line: line)
        }
    }
}
