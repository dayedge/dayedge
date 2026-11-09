import CoreGraphics

/// Where the Command Window opens: centred on the screen it opens on, a
/// little above the middle, at its remembered size — never larger than that
/// screen's visible frame (no menu bar, no Dock), even below its minimum.
struct CommandWindowPlacement: Equatable {
    let frame: CGRect

    /// Room kept free around a window as large as the screen allows.
    static let screenMargin: CGFloat = 24

    init(size: CGSize, minSize: CGSize, visibleFrame: CGRect) {
        let available = visibleFrame.insetBy(dx: Self.screenMargin, dy: Self.screenMargin)
        let width = min(max(size.width, minSize.width), available.width)
        let height = min(max(size.height, minSize.height), available.height)
        // More of the free space below than above: the optical centre.
        let originY = available.minY + (available.height - height) * 0.55
        frame = CGRect(x: (available.midX - width / 2).rounded(), y: originY.rounded(), width: width, height: height)
    }
}
