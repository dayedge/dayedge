# Theming

- Themes: Opal (default), Apple Light, Apple Dark, Apple System, One Dark Pro, Graphite Pro, Quartz Pro, Frost. Persisted as `appearance.theme`; unknown ids ⇒ Opal.
- `ThemePalette`: the semantic colour/typography/surface contract. `AppTheme`: shared fonts, dimensions, spacing, symbols.
- Views read `@Environment(\.themePalette)`. Never read the theme id in a view, never cache palette colours in statics, never hard-code colours.
- Use the specific token groups (`content`, `editor`, `sourcePresentation`, `calendarHeader`, …) over generic chrome tokens.
- Settings picker values use `settings.primaryText`; switches and accent actions use `settings.tint`.
- Calendar/list/service identity colours come from the source; the palette controls only their presentation.
- Command Window structure and selection: `theme.workspace` (`WorkspaceStyle.swift`) — grid hairline < section separator < structural divider, the neutral selected surface, the month grid's surfaces (displayed month a shade apart from its neighbours; the selected day tinted with the today accent), the day strip's meeting opacity — derived from each theme's own chrome tokens, never set per theme. Draw rules with `WorkspaceRule(role)` (one pixel). Shared views that also live in the popover read `\.panelLayout` (`gridRule(in:)`); the popover stays `.compact` and unchanged.
- Every independent hosting tree (windows, tooltips, HUD) is wrapped in `ThemedRoot`; keep its identity stable across theme changes.
- Liquid Glass (macOS 26) only on Frost's floating/elevated controls; must degrade to blur, and to solid with Reduce Transparency. Increase Contrast: denser tints, no optical decoration.

## Adding a theme
1. Complete palette (or copy one and override), including foregrounds on coloured fills, interaction states, opaque search surface, meeting fallbacks.
2. Register a `ThemeDefinition` in `ThemeCatalog.themes` (stable id, title, appearance policy, factory). System-following themes provide both palettes.
3. Tests for appearance/persistence; check both appearances, Increase Contrast, Reduce Transparency. Keep the Opal baseline fixture.
