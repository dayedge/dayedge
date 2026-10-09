import SwiftUI

/// Whether `floatingTopBar` floats over the scroll content (macOS 26's
/// safe-area bar) instead of sitting above it. Scroll-position math needs
/// to know, since pinned headers then rest below the bar.
package enum FloatingBar {
    package static var overlapsContent: Bool {
        #if HAS_MACOS26_SDK
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}

extension View {
    /// Native top-edge blur used when scrollable content moves underneath
    /// a unified macOS toolbar.
    @ViewBuilder
    package func liquidGlassTopScrollEdge() -> some View {
        #if HAS_MACOS26_SDK
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Applies macOS 26's real "Liquid Glass" scroll-edge effect
    /// (`.scrollEdgeEffectStyle`) where available — genuine system-rendered
    /// progressive blur for content scrolling under a floating bar, not a
    /// hand-rolled fade. Confirmed (via a standalone spike) to require a
    /// real SwiftUI `ScrollView`, and it also needs the floating bar to be a
    /// registered safe-area accessory (`floatingFooterBar` below), not a
    /// plain overlay sibling. Compiled out entirely on the plain Command
    /// Line Tools SDK (see `Package.swift`'s `HAS_MACOS26_SDK` condition).
    @ViewBuilder
    package func liquidGlassBottomScrollEdge() -> some View {
        #if HAS_MACOS26_SDK
        if #available(macOS 26.0, *) {
            // Keep one stable visual treatment across scrolling phases;
            // `.automatic` may transition between context-dependent edge
            // treatments as momentum ends and the bar settles.
            self.scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Attaches a floating bottom bar the "real" way on macOS 26+
    /// (`.safeAreaBar`, a registered system-bar accessory — required for
    /// `liquidGlassBottomScrollEdge()`'s blur to actually appear on
    /// content scrolled underneath it) and falls back to a plain
    /// `ZStack` overlay everywhere else, so this project stays buildable
    /// without Xcode's SDK even though that path won't render the glass
    /// effect.
    /// With a custom dissolve, use a plain safe-area inset instead of native bar optics.
    @ViewBuilder
    package func floatingFooterBar<Footer: View>(usesNativeEffect: Bool = true, @ViewBuilder footer: @escaping () -> Footer) -> some View {
        #if HAS_MACOS26_SDK
        if #available(macOS 26.0, *) {
            // Keep the content's identity when switching calendar modes.
            self.safeAreaBar(edge: .bottom, spacing: 0) {
                if usesNativeEffect { footer() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !usesNativeEffect { footer() }
            }
        } else {
            ZStack(alignment: .bottom) {
                self.safeAreaInset(edge: .bottom, spacing: 0) {
                    if !usesNativeEffect { footer() }
                }
                if usesNativeEffect { footer() }
            }
        }
        #else
        ZStack(alignment: .bottom) {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                if !usesNativeEffect { footer() }
            }
            if usesNativeEffect { footer() }
        }
        #endif
    }

    /// Registers a compact header as a native top bar so scrolling content
    /// receives the same system edge blend used by the floating footer.
    /// `usesNativeEffect: false` reserves the same space without native bar optics.
    @ViewBuilder
    package func floatingTopBar<Header: View>(usesNativeEffect: Bool = true, @ViewBuilder header: @escaping () -> Header) -> some View {
        #if HAS_MACOS26_SDK
        if #available(macOS 26.0, *) {
            self.safeAreaBar(edge: .top, spacing: 0) {
                if usesNativeEffect { header() }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !usesNativeEffect { header() }
            }
        } else {
            VStack(spacing: 0) {
                if usesNativeEffect { header() }
                self.safeAreaInset(edge: .top, spacing: 0) {
                    if !usesNativeEffect { header() }
                }
            }
        }
        #else
        VStack(spacing: 0) {
            if usesNativeEffect { header() }
            self.safeAreaInset(edge: .top, spacing: 0) {
                if !usesNativeEffect { header() }
            }
        }
        #endif
    }
}
