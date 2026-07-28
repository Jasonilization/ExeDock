import SwiftUI

/// The GitHub "Octocat" mark, traced from GitHub's own 16x16 Octicon (`mark-github`) path data so it
/// renders crisply at any size and tints like an SF Symbol (via `.foregroundStyle`) instead of
/// needing a bundled raster asset - this package doesn't have an asset-catalog/resource pipeline set
/// up (`Package.swift` explicitly excludes `Resources`, which exists only for the app icon).
struct GitHubMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()
        path.move(to: pt(8, 0))
        path.addCurve(to: pt(0, 8), control1: pt(3.58, 0), control2: pt(0, 3.58))
        path.addCurve(to: pt(5.47, 15.59), control1: pt(0, 11.54), control2: pt(2.29, 14.53))
        path.addCurve(to: pt(6.02, 15.21), control1: pt(5.87, 15.66), control2: pt(6.02, 15.42))
        path.addCurve(to: pt(6.01, 13.72), control1: pt(6.02, 15.02), control2: pt(6.01, 14.39))
        path.addCurve(to: pt(3.32, 12.78), control1: pt(4.00, 14.09), control2: pt(3.48, 13.23))
        path.addCurve(to: pt(2.50, 11.65), control1: pt(3.23, 12.55), control2: pt(2.84, 11.84))
        path.addCurve(to: pt(2.49, 11.12), control1: pt(2.22, 11.50), control2: pt(1.82, 11.13))
        path.addCurve(to: pt(3.72, 11.94), control1: pt(3.12, 11.11), control2: pt(3.57, 11.70))
        path.addCurve(to: pt(6.05, 12.60), control1: pt(4.44, 13.15), control2: pt(5.59, 12.81))
        path.addCurve(to: pt(6.56, 11.53), control1: pt(6.12, 12.08), control2: pt(6.33, 11.73))
        path.addCurve(to: pt(2.92, 7.58), control1: pt(4.78, 11.33), control2: pt(2.92, 10.64))
        path.addCurve(to: pt(3.74, 5.43), control1: pt(2.92, 6.71), control2: pt(3.23, 5.99))
        path.addCurve(to: pt(3.82, 3.31), control1: pt(3.66, 5.23), control2: pt(3.38, 4.41))
        path.addCurve(to: pt(6.02, 4.13), control1: pt(3.82, 3.31), control2: pt(4.49, 3.10))
        path.addCurve(to: pt(8.02, 3.86), control1: pt(6.66, 3.95), control2: pt(7.34, 3.86))
        path.addCurve(to: pt(10.02, 4.13), control1: pt(8.70, 3.86), control2: pt(9.38, 3.95))
        path.addCurve(to: pt(12.22, 3.31), control1: pt(11.55, 3.09), control2: pt(12.22, 3.31))
        path.addCurve(to: pt(12.30, 5.43), control1: pt(12.66, 4.41), control2: pt(12.38, 5.23))
        path.addCurve(to: pt(13.12, 7.58), control1: pt(12.81, 5.99), control2: pt(13.12, 6.70))
        path.addCurve(to: pt(9.47, 11.53), control1: pt(13.12, 10.65), control2: pt(11.25, 11.33))
        path.addCurve(to: pt(10.01, 13.01), control1: pt(9.76, 11.78), control2: pt(10.01, 12.26))
        path.addCurve(to: pt(10.00, 15.21), control1: pt(10.01, 14.08), control2: pt(10.00, 14.94))
        path.addCurve(to: pt(10.55, 15.59), control1: pt(10.00, 15.42), control2: pt(10.15, 15.67))
        // The source path closes this last stretch with a circular arc (radius 8.013, centered on
        // (8, 8)); approximated here as a single cubic bezier since the span is under 72 degrees.
        path.addCurve(to: pt(16, 8), control1: pt(13.81, 14.49), control2: pt(16, 11.44))
        path.addCurve(to: pt(8, 0), control1: pt(16, 3.58), control2: pt(12.42, 0))
        path.closeSubpath()
        return path
    }
}
