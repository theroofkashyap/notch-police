import SwiftUI
import NotchPoliceCore

/// A pill welded to one screen edge, with inverse (bezel) corners so it
/// reads as part of the display rather than a floating sticker.
struct BezelNotchShape: Shape {
    var edge: ScreenEdge = .right
    var curlRadius: CGFloat = NotchMetrics.curl
    var cornerRadius: CGFloat = NotchMetrics.corner

    func path(in rect: CGRect) -> Path {
        let depth = edge.isVertical ? rect.width : rect.height
        let length = edge.isVertical ? rect.height : rect.width
        let canonical = canonicalPath(in: CGRect(x: 0, y: 0, width: depth, height: length))
        return canonical
            .applying(Self.map(edge: edge, depth: depth))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    /// Canonical drawing has the bezel on maxX (the right edge).
    private func canonicalPath(in rect: CGRect) -> Path {
        let corner = min(cornerRadius, rect.width / 2, rect.height / 4)
        let curl = min(curlRadius, rect.height / 2, max(0, rect.width - corner))
        let bodyTop = rect.minY + curl
        let bodyBottom = rect.maxY - curl

        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        if curl > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - curl, y: rect.minY),
                radius: curl,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + corner, y: bodyTop))
        path.addArc(
            center: CGPoint(x: rect.minX + corner, y: bodyTop + corner),
            radius: corner,
            startAngle: .degrees(270),
            endAngle: .degrees(180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyBottom - corner))
        path.addArc(
            center: CGPoint(x: rect.minX + corner, y: bodyBottom - corner),
            radius: corner,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX - curl, y: bodyBottom))
        if curl > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - curl, y: rect.maxY),
                radius: curl,
                startAngle: .degrees(270),
                endAngle: .degrees(360),
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }

    static func map(edge: ScreenEdge, depth: CGFloat) -> CGAffineTransform {
        switch edge {
        case .right:
            return .identity
        case .left:
            return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: depth, ty: 0)
        case .top:
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: depth)
        case .bottom:
            return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        }
    }
}
