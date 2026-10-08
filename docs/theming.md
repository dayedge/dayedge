# Theming

- Themes: Opal (default), Apple Light, Apple Dark, Apple System, One Dark Pro, Graphite Pro, Quartz Pro, Frost. Persisted as `appearance.theme`; unknown ids ⇒ Opal.
- `ThemePalette`: the semantic colour/typography/surface contract. `AppTheme`: shared fonts, dimensions, spacing, symbols.
- Views read `@Environment(\.themePalette)`. Never read the theme id in a view, never cache palette colours in statics, never hard-code colours.
- Use the specific token groups (`content`, `editor`, `sourcePresentation`, `calendarHeader`, …) over generic chrome tokens.
- Calendar/list/service identity colours come from the source; the palette controls only their presentation.
- Every independent hosting tree (windows, tooltips, HUD) is wrapped in `ThemedRoot`; keep its identity stable across theme changes.
- Liquid Glass (macOS 26) only on Frost's floating/elevated controls; must degrade to blur, and to solid with Reduce Transparency. Increase Contrast: denser tints, no optical decoration.

## Adding a theme
1. Complete palette (or copy one and override), including foregrounds on coloured fills, interaction states, opaque search surface, meeting fallbacks.
2. Register a `ThemeDefinition` in `ThemeCatalog.themes` (stable id, title, appearance policy, factory). System-following themes provide both palettes.
3. Tests for appearance/persistence; check both appearances, Increase Contrast, Reduce Transparency. Keep the Opal baseline fixture.
