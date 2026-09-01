import SwiftUI

/// The real background treatment behind the whole dashboard, one real SwiftUI view per skin -
/// ported directly from that skin's own HTML preview's `body` background (the same gradients,
/// grids, and textures, not an approximation of them). "I mean the background, design, boxes,
/// everything... check your own html... make exactly that," per live feedback - color/corner-radius
/// tokens alone were never going to get a skin looking like its own preview; the background is
/// most of what actually reads as a different visual world.
struct SkinBackground: View {
    let skin: PlaydockSkin

    var body: some View {
        switch skin {
        case .luxury:
            Color(nsColor: .windowBackgroundColor)
        case .glass:
            ZStack {
                LinearGradient(colors: [Color(red: 0.96, green: 0.95, blue: 1.0), Color(red: 0.93, green: 0.95, blue: 0.98)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.purple.opacity(0.28), .clear], center: UnitPoint(x: 0.15, y: -0.1), startRadius: 10, endRadius: 480)
                RadialGradient(colors: [.pink.opacity(0.26), .clear], center: UnitPoint(x: 1.0, y: 0.15), startRadius: 10, endRadius: 420)
                RadialGradient(colors: [.mint.opacity(0.24), .clear], center: UnitPoint(x: 0.4, y: 1.05), startRadius: 10, endRadius: 400)
            }
        case .brutalist:
            Color(red: 0.996, green: 0.965, blue: 0.894)
        case .cyber:
            ZStack {
                Color(red: 0.02, green: 0.027, blue: 0.039)
                GridPattern(spacing: 28, color: Color(red: 0, green: 0.94, blue: 1).opacity(0.06))
            }
        case .soft:
            Color(red: 0.90, green: 0.905, blue: 0.933)
        case .editorial:
            Color(red: 0.933, green: 0.941, blue: 0.902)
        case .pixel:
            ZStack {
                Color(red: 0.102, green: 0.11, blue: 0.173)
                DotPattern(spacing: 24, dotSize: 3, color: Color(red: 0.161, green: 0.212, blue: 0.435))
            }
        case .console:
            ZStack {
                LinearGradient(colors: [Color(white: 0.11), Color(white: 0.10)], startPoint: .top, endPoint: .bottom)
                DiagonalStripes(spacing: 4, angle: .degrees(115), color: .white.opacity(0.02))
            }
        case .minimal:
            Color(nsColor: .textBackgroundColor)
        case .vapor:
            ZStack {
                LinearGradient(colors: [Color(red: 0.102, green: 0.043, blue: 0.18), Color(red: 0.176, green: 0.039, blue: 0.306), Color(red: 0.302, green: 0.059, blue: 0.361)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(red: 1, green: 0.18, blue: 0.90).opacity(0.33), .clear], center: UnitPoint(x: 0.2, y: 0), startRadius: 10, endRadius: 520)
                RadialGradient(colors: [Color(red: 0, green: 0.9, blue: 1).opacity(0.3), .clear], center: UnitPoint(x: 1.0, y: 0.3), startRadius: 10, endRadius: 460)
                VaporSun().frame(width: 220, height: 220).position(x: 900, y: 130)
                PerspectiveGrid(color: Color(red: 1, green: 0.18, blue: 0.90).opacity(0.35))
                    .frame(height: 220)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

/// The neon striped "retrowave sun" - concentric rings alternating between two colors, matching
/// the CSS `repeating-linear-gradient` circle from the Vaporwave preview.
private struct VaporSun: View {
    var body: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { i in
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(i.isMultiple(of: 2) ? Color(red: 1, green: 0.87, blue: 0.35) : Color(red: 1, green: 0.18, blue: 0.9), lineWidth: 12)
                    .frame(width: CGFloat(220 - i * 22), height: CGFloat(220 - i * 22))
            }
        }
        .blur(radius: 1)
        .opacity(0.55)
    }
}

/// A perspective-tilted neon grid floor, matching the Vaporwave preview's CSS 3D-transformed grid.
private struct PerspectiveGrid: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let horizonY: CGFloat = 0
                let rows = 10
                for row in 0...rows {
                    let t = CGFloat(row) / CGFloat(rows)
                    let y = horizonY + t * t * size.height
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(color.opacity(0.5 - t * 0.35)), lineWidth: 1)
                }
                let cols = 14
                for col in 0...cols {
                    let t = CGFloat(col) / CGFloat(cols) - 0.5
                    var path = Path()
                    path.move(to: CGPoint(x: size.width / 2 + t * size.width * 0.3, y: 0))
                    path.addLine(to: CGPoint(x: size.width / 2 + t * size.width * 2.2, y: size.height))
                    context.stroke(path, with: .color(color.opacity(0.3)), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
        .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
    }
}

/// A faint repeating grid of hairlines, matching the Cyber Terminal preview's CSS background-image
/// grid.
private struct GridPattern: View {
    let spacing: CGFloat
    let color: Color
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color), lineWidth: 1)
                x += spacing
            }
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color), lineWidth: 1)
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// A repeating dot grid, matching the Pixel Arcade preview's CSS radial-gradient dot background.
private struct DotPattern: View {
    let spacing: CGFloat
    let dotSize: CGFloat
    let color: Color
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)), with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// A subtle diagonal hairline texture, matching the Console Unit preview's brushed-panel
/// repeating-linear-gradient.
private struct DiagonalStripes: View {
    let spacing: CGFloat
    let angle: Angle
    let color: Color
    var body: some View {
        Canvas { context, size in
            let diagonal = sqrt(size.width * size.width + size.height * size.height)
            var offset: CGFloat = -diagonal
            while offset < diagonal {
                var path = Path()
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset + diagonal * CGFloat(tan(angle.radians)), y: diagonal))
                context.stroke(path, with: .color(color), lineWidth: 1)
                offset += spacing
            }
        }
        .allowsHitTesting(false)
        .clipped()
    }
}
