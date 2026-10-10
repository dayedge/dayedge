import AppKit
import SwiftUI

extension ThemePaletteValues {
    package struct AgendaHeaderColors {
        package var inlineAgenda: Color
        package var popoverAgenda: Color
    }

    package struct CalendarHeaderStyle {
        package var titleFont: Font
        package var yearFont: Font
        package var yearText: Color
        package var todayTitleText: Color
    }

    package struct SecondaryControlColors {
        package var fill: Color
        package var hover: Color
        package var pressed: Color
        package var border: Color
        package var divider: Color
    }

    package struct ConflictColors {
        package var busy: Color
        package var unconfirmed: Color
        package var free: Color
    }

    package struct MeetingTakeoverColors {
        package var iconFill: Color
        package var iconKeyline: Color
        package var metadata: Color
        package var metadataHover: Color
        package var title: Color
        package var titleHover: Color
        package var disclosure: Color
        package var reminderHover: Color
        package var menuHover: Color
        package var menuText: Color
        package var strongActionFill: Color
        package var strongActionHover: Color
        package var quietActionFill: Color
        package var quietActionHover: Color
        package var primaryActionKeyline: Color
        package var secondaryActionKeyline: Color
        package var sheen: Color
        package var floor: Color

        package var dimming: Color
        package var highContrastDimming: Color
        package var opaqueFallback: Color
        package var approaching: Color
        package var started: Color
        package var actionSurface: Color
        package var actionSurfaceHover: Color
        package var actionKeyline: Color
    }

    package struct KeycapColors {
        package var onAccentLargeFill: Color
        package var onAccentLargeGlyph: Color
        package var largeFill: Color
        package var largeGlyph: Color
        package var compactFill: Color
        package var compactStroke: Color
        package var compactGlyph: Color
        package var actionLabel: Color
    }

    package struct DateTileColors {
        package var tileFill: Color
        package var tileBorder: Color
        package var weekdayBand: Color
        package var weekdayTint: Color
        package var dayTint: Color
        package var todayTint: Color
        package var monthTint: Color
    }

    package struct PeriodHeaderColors {
        package var color: Color
    }

    package struct ChatColors {
        package var jumpButtonBorder: Color
        package var dateHoverFill: Color
        package var assistantText: Color
        package var userBubbleFill: Color
        package var userBubbleText: Color
        package var accent: Color
        package var composerStrokeIncreased: Color
        package var composerText: Color
        package var composerPlaceholder: Color
        package var sendEnabledGlyph: Color
        package var sendDisabledFill: Color
        package var sendDisabledGlyph: Color
        package var stopFill: Color
        package var stopGlyph: Color
        package var cardFill: Color
        package var cardStroke: Color
        package var cardHeadline: Color
        package var destructive: Color
        package var receiptDone: Color
        package var receiptMuted: Color
        package var chipFill: Color
        package var chipHoverFill: Color
        package var chipPressedFill: Color
        package var chipBorder: Color
        package var chipBorderIncreased: Color
        package var chipLabel: Color
        package var chipLabelHover: Color
        package var chipIcon: Color
        package var chipIconHover: Color
    }

    package struct SettingsColors {
        package var iconGlyph: Color
        package var iconKeyline: Color
        package var iconDarkening: Double
        package var background: Color
        package var sidebarBackground: Color
        package var groupFill: Color
        package var groupBorder: Color
        package var divider: Color
        package var primaryText: Color
        package var secondaryText: Color
        package var tint: Color
        package var granted: Color
        package var denied: Color
        package var pending: Color
        package var attention: Color
    }

    package struct TasksColors {
        package var attentionTint: Color
        package var timelineCardFill: Color
        package var timelineCardHoverFill: Color
        package var timelineCardSelectedFill: Color
        package var timelineCardKeyline: Color
        package var timelineDueTick: Color
    }

    package struct ChromeColors {
        package var rowHover: Color
        package var rowSelection: Color
        package var divider: Color
        package var gridRule: Color
        package var pressedFill: Color
        package var badgeFill: Color
        package var mutedText: Color
        package var placeholderText: Color
        package var slotSelected: Color
        package var slotSelectedPressed: Color
        package var slotHover: Color
        package var selectionKeyline: Color
        package var ongoingEventKeyline: Color
        package var keyboardEventKeyline: Color
        package var searchScrim: Color
        package var searchShadow: Color
        package var tooltipShadow: Color
        package var primaryActionShadow: Color
    }

    package struct DetailColors {
        package var hoverFill: Color
        package var activeFill: Color
    }

    package struct ContentColors {
        package var detailSelectionFill: Color
        package var tentativeText: Color
        package var tentativeMetadata: Color
        package var cancelledText: Color
        package var cancelledMetadata: Color
        package var cancelledTimelineText: Color
        package var cancelledTimelineFill: Color
        package var ongoingIndicator: Color
        package var quietMetadata: Color
        package var subduedMetadata: Color
        package var detailMetadata: Color
        package var sourceLabelFallback: Color
    }

    package struct EditorColors {
        package var text: Color
        package var focusRing: Color
        package var selectionFill: Color
        package var titleText: Color
        package var labelText: Color
        package var placeholderText: Color
        package var panelFill: Color
        package var fieldFill: Color
        package var fieldHoverFill: Color
        package var fieldFocusedFill: Color
        package var fieldKeyline: Color
        package var overlapBusyText: Color
        package var overlapUnconfirmedText: Color
        /// Native plain text fields own their placeholder ink; attenuate it only while empty.
        package var nativePlaceholderOpacity: Double = 1
    }

    package struct SourcePresentation {
        package var completedTaskOpacity: Double
        package var taskHoverCheckOpacity: Double
        package var readOnlyTaskOpacity: Double
        package var tentativeMarkerOpacity: Double
        package var eventBorderOpacity: Double
        package var tentativeStripeOpacity: Double
        package var tentativeStripeSaturation: Double = 1
        package var eventHoverBrightness: Double = 0.06
        package var eventOngoingBrightness: Double = 0.035
        package var joinFillOpacity: Double
        package var allDayFillOpacity: Double
        package var allDayHoverFillOpacity: Double
        package var allDayBorderOpacity: Double
        package var allDayHoverBorderOpacity: Double
        package var timelineMetadataOpacity: Double
        package var timelineGlyphOpacity: Double
    }

    package struct CompactControlColors {
        package var surface: Color
        package var hoverSurface: Color
        package var keyline: Color
    }
}
