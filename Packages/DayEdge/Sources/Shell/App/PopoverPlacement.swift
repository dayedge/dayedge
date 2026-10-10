import Foundation

struct PopoverAnchor: Equatable {
    let point: CGPoint
    let visibleFrame: CGRect
}

struct PopoverPlacement: Equatable {
    let windowOrigin: CGPoint
    let arrowX: CGFloat

    init(anchor: PopoverAnchor, windowSize: CGSize, arrowInset: CGFloat) {
        let frame = anchor.visibleFrame
        let maxX = max(frame.minX, frame.maxX - windowSize.width)
        let originX = min(max(anchor.point.x - windowSize.width / 2, frame.minX), maxX)
        windowOrigin = CGPoint(x: originX, y: anchor.point.y - windowSize.height - 1)
        arrowX = min(max(anchor.point.x - originX, arrowInset), windowSize.width - arrowInset)
    }
}
