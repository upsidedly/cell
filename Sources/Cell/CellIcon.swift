import AppKit

enum CellIcon {
    @MainActor static func draw(in rect: CGRect) {
        let unit = rect.width / 100
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        let ink = NSColor(calibratedWhite: 0.16, alpha: 1)
        ink.setStroke(); ink.setFill()
        let body = NSBezierPath(roundedRect: CGRect(origin: point(14, 30),
            size: CGSize(width: 65 * unit, height: 40 * unit)), xRadius: 7 * unit, yRadius: 7 * unit)
        body.lineWidth = 6 * unit
        body.stroke()
        NSBezierPath(roundedRect: CGRect(origin: point(23, 39),
            size: CGSize(width: 38 * unit, height: 22 * unit)), xRadius: 3 * unit, yRadius: 3 * unit).fill()
        NSBezierPath(roundedRect: CGRect(origin: point(86, 42),
            size: CGSize(width: 4 * unit, height: 16 * unit)), xRadius: 2 * unit, yRadius: 2 * unit).fill()
    }
}
