import AppKit
import SwiftUI

/// Rendering roles, independent of component identity and geometry.
package enum SurfaceRole: CaseIterable {
    case window, nested, elevated, transient, floatingControl, selectedFloatingControl, selectedNavigation, control, selection, hover
}

package struct SurfaceElevation {
    package var color: Color
    package var radius: CGFloat
    package var x: CGFloat = 0
    package var y: CGFloat

    package init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

package struct SurfaceLighting {
    package var interiorLight: Color
    package var interiorShade: Color
    package var edgeShade: Color
    package var startPoint: UnitPoint = .topLeading
    package var endPoint: UnitPoint = .bottomTrailing
}

package struct SurfaceTreatment {
    package enum Backing {
        case solid
        /// Desktop-backed blur for the shell and bounded floating chrome; never rows or cells.
        case desktop(NSVisualEffectView.Material)
        /// Local blur; only major nested/elevated boundaries, never rows or cells.
        case local(Material)
    }
    package var backing: Backing
    /// Optional role tint; legacy palettes continue supplying their original component fill.
    package var tint: Color?
    package var tintOpacity: Double = 1
    package var keyline: Color?
    package var edgeHighlight: Color?
    package var elevation: SurfaceElevation?
    /// Native optics affect the surface only, never foreground vibrancy or interaction.
    package var usesLiquidGlassOptics = false
    /// Low-contrast directional definition remains visible over a neutral background.
    package var lighting: SurfaceLighting?

    package func effectiveOpacity(reduceTransparency: Bool, increaseContrast: Bool) -> Double {
        if reduceTransparency { return 1 }
        return increaseContrast ? max(tintOpacity, 0.94) : tintOpacity
    }
}

package struct SurfaceTreatments {
    package var window: SurfaceTreatment
    package var nested: SurfaceTreatment
    package var elevated: SurfaceTreatment
    package var transient: SurfaceTreatment
    /// Navigation and compact floating chrome; never used for ordinary rows or form fields.
    package var floatingControl: SurfaceTreatment = .init(backing: .solid)
    /// A denser inset of the floating-control family (active segment or primary icon control).
    package var selectedFloatingControl: SurfaceTreatment = .init(backing: .solid)
    /// Soft active navigation chip; quieter than floating toolbar glass.
    package var selectedNavigation: SurfaceTreatment = .init(backing: .solid)
    package var control: SurfaceTreatment = .init(backing: .solid)
    package var selection: SurfaceTreatment = .init(backing: .solid)
    package var hover: SurfaceTreatment = .init(backing: .solid)

    package subscript(role: SurfaceRole) -> SurfaceTreatment {
        switch role {
        case .window: return window
        case .nested: return nested
        case .elevated: return elevated
        case .transient: return transient
        case .floatingControl: return floatingControl
        case .selectedFloatingControl: return selectedFloatingControl
        case .selectedNavigation: return selectedNavigation
        case .control: return control
        case .selection: return selection
        case .hover: return hover
        }
    }
}

/// Text stays outside the visual effect view, so AppKit vibrancy never alters ink.
package struct DesktopMaterial: NSViewRepresentable {
    package let material: NSVisualEffectView.Material
    package func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }
    package func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

package struct ThemedSurface<SurfaceShape: Shape>: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var scale
    package let role: SurfaceRole
    package let fill: Color
    package let shape: SurfaceShape
    /// Existing interaction state controls material visibility, independently of theme identity.
    package var materialIsActive = true
    /// Optional legacy/native material, supplied by the palette rather than view branches.
    package var fallbackMaterial: Material?

    @ViewBuilder package var body: some View {
        if let treatment = theme.surfaces?[role], materialIsActive {
            treatedSurface(treatment)
        } else if let fallbackMaterial, !reduceTransparency {
            shape.fill(fallbackMaterial)
        } else {
            // Exact legacy ShapeStyle path: no extra masks or compositing at the edge.
            shape.fill(fill)
        }
    }

    private func treatedSurface(_ treatment: SurfaceTreatment) -> some View {
        let tint = treatment.tint ?? fill
        return ZStack {
            if !reduceTransparency {
                switch treatment.backing {
                case .solid: tint
                case .desktop(let material):
                    DesktopMaterial(material: material).allowsHitTesting(false)
                    tint.opacity(treatment.effectiveOpacity(reduceTransparency: false, increaseContrast: contrast == .increased))
                case .local(let material):
                    Rectangle().fill(material)
                    tint.opacity(treatment.effectiveOpacity(reduceTransparency: false, increaseContrast: contrast == .increased))
                }
            } else {
                tint
            }
            if !reduceTransparency, contrast != .increased {
                GlassOptics(shape: shape, enabled: treatment.usesLiquidGlassOptics)
                    .allowsHitTesting(false)
                if let lighting = treatment.lighting {
                    LinearGradient(colors: [lighting.interiorLight, .clear, lighting.interiorShade],
                                   startPoint: lighting.startPoint, endPoint: lighting.endPoint)
                    shape.stroke(LinearGradient(colors: [.clear, lighting.edgeShade],
                                                startPoint: lighting.startPoint, endPoint: lighting.endPoint),
                                 lineWidth: 1 / max(scale, 1))
                }
            }
            if let keyline = treatment.keyline {
                shape.stroke(keyline.opacity(contrast == .increased ? 1 : 0.8), lineWidth: 1 / max(scale, 1))
            }
            if let highlight = treatment.edgeHighlight, !reduceTransparency, contrast != .increased {
                shape.stroke(LinearGradient(colors: [highlight, .clear], startPoint: treatment.lighting?.startPoint ?? .top,
                                            endPoint: treatment.lighting?.endPoint ?? .bottom),
                             lineWidth: 1 / max(scale, 1))
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    package init(role: SurfaceRole, fill: Color, shape: SurfaceShape, materialIsActive: Bool = true, fallbackMaterial: Material? = nil) {
        self.role = role
        self.fill = fill
        self.shape = shape
        self.materialIsActive = materialIsActive
        self.fallbackMaterial = fallbackMaterial
    }
}

extension View {
    package func themedSurface<S: Shape>(_ role: SurfaceRole, fill: Color, in shape: S) -> some View {
        background(ThemedSurface(role: role, fill: fill, shape: shape))
    }

    /// Opt-in elevation leaves solid themes' original rendering path untouched.
    package func surfaceElevation(_ role: SurfaceRole) -> some View {
        modifier(OptionalSurfaceElevationModifier(role: role))
    }

    package func surfaceElevation(_ role: SurfaceRole, fallback: SurfaceElevation) -> some View {
        modifier(SurfaceElevationModifier(role: role, fallback: fallback))
    }
}

private struct SurfaceElevationModifier: ViewModifier {
    @Environment(\.themePalette) private var theme
    let role: SurfaceRole
    let fallback: SurfaceElevation
    func body(content: Content) -> some View {
        let value = theme.surfaces?[role].elevation ?? fallback
        content.shadow(color: value.color, radius: value.radius, x: value.x, y: value.y)
    }
}

private struct OptionalSurfaceElevationModifier: ViewModifier {
    @Environment(\.themePalette) private var theme
    let role: SurfaceRole
    func body(content: Content) -> some View {
        // Keep content identity stable across theme changes, including focused native fields.
        // A zero-radius clear shadow is a no-op for palettes that don't opt in.
        let value = theme.surfaces?[role].elevation ?? .init(color: .clear, radius: 0, y: 0)
        return content.shadow(color: value.color, radius: value.radius, x: value.x, y: value.y)
    }
}

/// An optical layer on an existing material boundary, not a replacement control.
/// Older systems retain the same native blur and theme-provided lighting.
private struct GlassOptics<S: Shape>: View {
    let shape: S
    let enabled: Bool
    @ViewBuilder var body: some View {
        #if HAS_MACOS26_SDK
        if #available(macOS 26.0, *), enabled {
            Color.clear.glassEffect(.clear, in: shape)
        }
        #endif
    }
}

/// Preserve Settings' original native glass exactly for palettes without surface recipes.
/// The component itself only requests a navigation surface; no theme branching in the view.
package struct NavigationSurfaceModifier: ViewModifier {
    @Environment(\.themePalette) private var theme

    @ViewBuilder package func body(content: Content) -> some View {
        #if HAS_MACOS26_SDK
        if #available(macOS 26.0, *) {
            content
                .themedSurface(.floatingControl, fill: .clear, in: Capsule())
                .surfaceElevation(.floatingControl)
                .glassEffect(theme.surfaces == nil ? .regular.interactive() : .identity, in: Capsule())
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content.background(ThemedSurface(role: .floatingControl, fill: .clear, shape: Capsule(),
                                          fallbackMaterial: .ultraThinMaterial))
            .surfaceElevation(.floatingControl)
    }

    package init() {
    }
}
