import AppKit
import SwiftUI

/// A blank calendar "page" outline — a thick solid top cap (echoing the
/// real Calendar.app icon's header band) over a slightly rounded
/// rectangle frame, with the strategy's number centered inside. Dates
/// use up to two digits; event counts are already capped by the strategy.
///
/// The top-right corner can carry one `MenuBarCornerGlyph` (e.g. the "+"
/// for more than 9), cut as a true transparent gap out of the frame (a
/// `.destinationOut` halo in a compositing group) — everything here
/// renders as one solid template color, so without an actual erased gap
/// the badge would just visually fuse into the frame's own stroke instead
/// of reading as a distinct overlapping badge. Shapes, not `Canvas`: each
/// `Canvas` draw briefly allocated ~130 MB of rendering buffers.
struct MenuBarBadgeIcon: View {
    let value: Int
    var cornerGlyph: MenuBarCornerGlyph?
    var inkColor: Color = .black

    private static let frameSize = CGSize(width: 18, height: 15)
    private static let cornerRadius: CGFloat = 2.5
    private static let topCapHeight: CGFloat = 3.5
    private static let strokeWidth: CGFloat = 1.3
    private static let badgeDiameter: CGFloat = 6
    private static let haloDiameter: CGFloat = badgeDiameter + 4.5
    /// Room kept on every side so the frame's own stroke never lands
    /// flush against the canvas edge — a stroke is centered on its path,
    /// so with zero margin the half of it that falls outside the canvas
    /// gets clipped, rendering that edge visibly thinner than the others
    /// (this is why the left edge previously looked thinner than the
    /// right — the right one had margin only because it happened to
    /// double as the badge's overflow room, the left had none at all).
    private static let strokeMargin: CGFloat = strokeWidth / 2 + 0.2
    /// Extra canvas room the badge needs to overlap past the frame's own
    /// top-right corner without being clipped — kept small so the badge
    /// mostly sits *on* the corner rather than floating outside it.
    private static let badgeOverflow: CGFloat = 4.5
    private static let canvasSize = CGSize(
        width: frameSize.width + strokeMargin * 2 + badgeOverflow,
        height: frameSize.height + strokeMargin * 2 + badgeOverflow
    )

    /// Exposed so `CallJoinIcon` can match this icon's vertical placement
    /// within a shared canvas height — this icon's own drawn content
    /// isn't centered in its canvas (more room is reserved above, for the
    /// "+" badge's overflow, than below), so simply giving two menu bar
    /// icons the same *total* canvas height isn't enough to align them on
    /// the same visual center; both need the same top/bottom split too.
    static var topContentInset: CGFloat { strokeMargin + badgeOverflow }
    static var bottomContentInset: CGFloat { strokeMargin }
    static var totalCanvasHeight: CGFloat { canvasSize.height }
    static var totalCanvasWidth: CGFloat { canvasSize.width }

    /// Side of the square each corner glyph's glyph is drawn into.
    fileprivate static let glyphSize: CGFloat = badgeDiameter + 2.5

    /// The frame: flush margin on the left/bottom; the top/right side
    /// additionally carries `badgeOverflow` so the "+" badge has room to
    /// overlap past that corner without being clipped.
    private static let frameRect = CGRect(
        x: strokeMargin, y: strokeMargin + badgeOverflow,
        width: frameSize.width, height: frameSize.height
    )

    var body: some View {
        let frameRect = Self.frameRect
        ZStack(alignment: .topLeading) {
            // Paths at the icon's own (fractional) coordinates, in shapes
            // spanning the whole icon: a framed, offset shape is snapped to
            // whole pixels, half a pixel off the drawing it replaced.
            IconPathShape(path: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .path(in: frameRect))
                .stroke(inkColor, lineWidth: Self.strokeWidth)

            // A solid, thick top band with rounded top corners matching the
            // frame's own — reads as a proper calendar "header," the way
            // Apple's own Calendar icon does.
            IconPathShape(path: Path(
                roundedRect: CGRect(x: frameRect.minX, y: frameRect.minY, width: frameRect.width, height: Self.topCapHeight),
                cornerRadii: RectangleCornerRadii(
                    topLeading: Self.cornerRadius, bottomLeading: 0,
                    bottomTrailing: 0, topTrailing: Self.cornerRadius
                ),
                style: .continuous
            ))
            .fill(inkColor)

            Text("\(value)")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: frameRect.width - Self.strokeWidth * 2)
                .position(x: frameRect.midX, y: frameRect.midY + 1.5)

            if let cornerGlyph {
                // Overlapping well onto the frame's top-right corner rather
                // than sitting mostly outside it in the reserved margin.
                let badgeCenter = CGPoint(x: frameRect.maxX - 1, y: frameRect.minY + 1)
                // The clear gap that separates the badge from the frame's
                // stroke/cap beneath it — otherwise, since everything here
                // renders as one solid template color, the glyph would just
                // visually fuse into the frame's own line with no separation.
                IconPathShape(path: Path(ellipseIn: CGRect(
                    x: badgeCenter.x - Self.haloDiameter / 2, y: badgeCenter.y - Self.haloDiameter / 2,
                    width: Self.haloDiameter, height: Self.haloDiameter)))
                    .fill(inkColor)
                    .blendMode(.destinationOut)
                IconPathShape(path: cornerGlyph.glyph(in: CGRect(
                    x: badgeCenter.x - Self.glyphSize / 2, y: badgeCenter.y - Self.glyphSize / 2,
                    width: Self.glyphSize, height: Self.glyphSize)))
                    .fill(inkColor)
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height, alignment: .topLeading)
        // The halo erases only within the icon.
        .compositingGroup()
    }
}

/// A path in the icon's own coordinates, drawn as a shape.
private struct IconPathShape: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path { path }
}

extension MenuBarCornerGlyph {
    /// The badge's solid glyph, filling `rect` — a square centered on the
    /// calendar's top-right corner, already cleared by the shared halo.
    /// Keep glyphs bold and filled: hairlines vanish at this size.
    func glyph(in rect: CGRect) -> Path {
        switch self {
        case .tasksDue:
            // A ring, not a dot: reads as an open to-do, like a
            // Reminders checkbox.
            let lineWidth: CGFloat = 1.5
            let ring = rect.insetBy(dx: 1 + lineWidth / 2, dy: 1 + lineWidth / 2)
            return Path(ellipseIn: ring).strokedPath(StrokeStyle(lineWidth: lineWidth))
        case .overflow:
            // Two thick crossed bars — not a filled circle with the plus
            // cut out of it (that read as a dot with a faint hairline
            // cross, not a plus).
            let thickness: CGFloat = 2.1
            let arms = rect.insetBy(dx: 1, dy: 1)
            var path = Path()
            path.addRect(CGRect(x: arms.minX, y: arms.midY - thickness / 2, width: arms.width, height: thickness))
            path.addRect(CGRect(x: arms.midX - thickness / 2, y: arms.minY, width: thickness, height: arms.height))
            return path
        }
    }
}

extension MenuBarBadgeIcon {
    /// Renders to an `NSImage` marked as a template — macOS re-tints
    /// template images for light/dark menu bars from their alpha channel
    /// alone, so the actual drawn color above (plain black) doesn't
    /// matter, only its shape (and, for the badge, its cut-out gaps).
    @MainActor
    static func render(value: Int, cornerGlyph: MenuBarCornerGlyph?) -> NSImage? {
        let renderer = ImageRenderer(content: MenuBarBadgeIcon(value: value, cornerGlyph: cornerGlyph))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}
