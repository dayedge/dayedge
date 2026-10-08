import AppKit
import SwiftUI

package enum AgendaHeaderStyle {
    case inlineAgenda
    case popoverAgenda
}

/// Complete semantic color contract. Geometry and typography remain in AppTheme.
///
/// A value with copy-on-write storage: every copy (one per view that
/// reads it from the environment) is a single reference to shared values,
/// not the ~3 KB of colors themselves. Reads and writes go straight
/// through to `ThemePaletteValues`; a write to a shared palette copies
/// the values first, so editing a copy (`var p = Self.appleLight;
/// p.calendarHeader.yearText = …`) never changes the original.
///
/// A theme switch hands the environment a different storage, so every
/// reader updates; the same theme keeps the same storage, so nothing does.
@dynamicMemberLookup
package struct ThemePalette {
    private final class Storage {
        var values: ThemePaletteValues
        init(_ values: ThemePaletteValues) { self.values = values }
    }

    private var storage: Storage

    package init(_ values: ThemePaletteValues) { storage = Storage(values) }

    /// All the values, read-only (tests, reflection).
    package var values: ThemePaletteValues { storage.values }

    /// Whether two palettes share their values (a theme handed out twice).
    package func sharesStorage(with other: ThemePalette) -> Bool { storage === other.storage }

    package subscript<T>(dynamicMember keyPath: WritableKeyPath<ThemePaletteValues, T>) -> T {
        get { storage.values[keyPath: keyPath] }
        set {
            if !isKnownUniquelyReferenced(&storage) { storage = Storage(storage.values) }
            storage.values[keyPath: keyPath] = newValue
        }
    }

    package subscript<T>(dynamicMember keyPath: KeyPath<ThemePaletteValues, T>) -> T {
        storage.values[keyPath: keyPath]
    }

    package func agendaHeaderFill(for style: AgendaHeaderStyle) -> Color {
        storage.values.agendaHeaderFill(for: style)
    }

    package func compactActionFill(isHovered: Bool) -> Color {
        storage.values.compactActionFill(isHovered: isHovered)
    }

    package func semanticActionTint(_ tint: Color) -> Color {
        storage.values.semanticActionTint(tint)
    }

    package static let opal = ThemePalette(.make(apple: false, light: false))
    package static let appleLight = ThemePalette(.make(apple: true, light: true, refinedUserBubble: true))
    package static let appleDark = ThemePalette(.make(apple: true, light: false, refinedUserBubble: true))
    // System retains its existing bubble treatment; fixed Apple themes opt in independently.
    package static let appleSystemLight = ThemePalette(.make(apple: true, light: true))
    package static let appleSystemDark = ThemePalette(.make(apple: true, light: false))
}
