import AppKit
import SwiftUI

enum ArrowEdge { case bottom, left, right }

/// Shared bubble outline: used both to mask the blur view (AppKit) and to draw
/// the border/highlight (SwiftUI). Coordinates are top-left origin.
enum BubbleGeometry {
    static let arrow: CGFloat = 10
    static let radius: CGFloat = 12

    static func path(in rect: CGRect, edge: ArrowEdge, offset: CGFloat, drawArrow: Bool) -> CGPath {
        var body = rect
        if drawArrow {
            switch edge {
            case .bottom: body.size.height -= arrow
            case .left: body.origin.x += arrow; body.size.width -= arrow
            case .right: body.size.width -= arrow
            }
        }
        let rounded = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
        guard drawArrow else { return rounded }

        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo > hi ? (lo + hi) / 2 : min(max(v, lo), hi) }
        let tri = CGMutablePath()
        switch edge {
        case .bottom:
            let x = clamp(offset, body.minX + radius + arrow, body.maxX - radius - arrow)
            tri.move(to: CGPoint(x: x - arrow, y: body.maxY - 1))
            tri.addLine(to: CGPoint(x: x, y: rect.maxY))
            tri.addLine(to: CGPoint(x: x + arrow, y: body.maxY - 1))
        case .left:
            let y = clamp(offset, body.minY + radius + arrow, body.maxY - radius - arrow)
            tri.move(to: CGPoint(x: body.minX + 1, y: y - arrow))
            tri.addLine(to: CGPoint(x: rect.minX, y: y))
            tri.addLine(to: CGPoint(x: body.minX + 1, y: y + arrow))
        case .right:
            let y = clamp(offset, body.minY + radius + arrow, body.maxY - radius - arrow)
            tri.move(to: CGPoint(x: body.maxX - 1, y: y - arrow))
            tri.addLine(to: CGPoint(x: rect.maxX, y: y))
            tri.addLine(to: CGPoint(x: body.maxX - 1, y: y + arrow))
        }
        tri.closeSubpath()
        return rounded.union(tri)
    }

    static func maskImage(size: CGSize, edge: ArrowEdge, offset: CGFloat, drawArrow: Bool) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(path(in: rect, edge: edge, offset: offset, drawArrow: drawArrow))
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
    }
}

struct BubbleShape: Shape {
    var edge: ArrowEdge
    var offset: CGFloat
    var drawArrow: Bool
    func path(in rect: CGRect) -> Path {
        Path(BubbleGeometry.path(in: rect, edge: edge, offset: offset, drawArrow: drawArrow))
    }
}

@MainActor
final class PreviewModel: ObservableObject {
    @Published var appName = ""
    @Published var appIcon: NSImage?
    @Published var windows: [WindowInfo] = []
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var hovered: CGWindowID?
    @Published var arrowEdge: ArrowEdge = .bottom
    @Published var arrowOffset: CGFloat = 0
    @Published var popScale: CGFloat = 1

    var onSelect: ((WindowInfo) -> Void)?
    var onClose: ((WindowInfo) -> Void)?
    var onNewWindow: (() -> Void)?
    var onHoverChange: ((WindowInfo?) -> Void)?

    func setHover(_ w: WindowInfo, inside: Bool) {
        if inside {
            guard hovered != w.id else { return }
            hovered = w.id
            onHoverChange?(w)
        } else if hovered == w.id {
            hovered = nil
            onHoverChange?(nil)
        }
    }
}

struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    @AppStorage(Pref.showAppName) private var showAppName = true
    @AppStorage(Pref.perRow) private var perRow = 5
    @AppStorage(Pref.bubbleSize) private var bubbleSize = 0.3
    @AppStorage(Pref.drawTriangle) private var drawTriangle = true
    @AppStorage(Pref.drawHighlight) private var drawHighlight = true

    private let hSpacing: CGFloat = 14

    var body: some View {
        let thumb = Pref.thumbSize(bubble: bubbleSize)
        let count = model.windows.count
        let cols = max(1, min(max(1, perRow), count))
        let rows: [[WindowInfo]] = stride(from: 0, to: count, by: cols).map {
            Array(model.windows[$0..<min($0 + cols, count)])
        }
        let gridWidth = CGFloat(cols) * thumb.width + CGFloat(cols - 1) * hSpacing
        let shape = BubbleShape(edge: model.arrowEdge, offset: model.arrowOffset, drawArrow: drawTriangle)

        VStack(spacing: 8) {
            if showAppName {
                ZStack {
                    Text(model.appName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    HStack {
                        Spacer()
                        Button { model.onNewWindow?() } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("New window")
                    }
                }
                .frame(width: gridWidth)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: hSpacing) {
                        ForEach(rows[i]) { w in
                            ThumbnailCell(model: model, window: w, size: thumb)
                        }
                    }
                }
            }
            .frame(width: gridWidth, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, showAppName ? 6 : 14)
        .padding(.bottom, 12)
        .padding(arrowPadding, drawTriangle ? BubbleGeometry.arrow : 0)
        .background {
            ZStack {
                if drawHighlight {
                    shape.fill(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.0)],
                                              startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)))
                }
                shape.stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .allowsHitTesting(false)
        }
        .scaleEffect(model.popScale, anchor: scaleAnchor)
        .fixedSize()
    }

    private var arrowPadding: Edge.Set {
        switch model.arrowEdge {
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private var scaleAnchor: UnitPoint {
        switch model.arrowEdge {
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }
}

struct ThumbnailCell: View {
    @ObservedObject var model: PreviewModel
    let window: WindowInfo
    let size: CGSize

    @AppStorage(Pref.showCloseButton) private var showClose = true
    @AppStorage(Pref.showMinimizedIndicator) private var showIndicator = true
    @AppStorage(Pref.shadeInvisible) private var shade = true

    private var hovering: Bool { model.hovered == window.id }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                thumbnail
                if shade && window.isInvisible && !hovering {
                    RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.35))
                }
                centerBadge
                if hovering && showClose && window.ax != nil {
                    closeButton
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .offset(x: -6, y: -6)
                }
            }
            .frame(width: size.width, height: size.height)
            .opacity(hovering ? 1 : (window.isInvisible && shade ? 0.6 : 0.88))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(hovering ? 0.85 : 0), lineWidth: 2)
                    .padding(-3)
            )

            Text(window.title.isEmpty ? model.appName : window.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: size.width)
                .foregroundStyle(hovering ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onHover { model.setHover(window, inside: $0) }
        .onTapGesture { model.onSelect?(window) }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder private var thumbnail: some View {
        if let img = model.thumbnails[window.id] {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06))
                if let icon = model.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 44, height: 44).opacity(0.6)
                }
            }
        }
    }

    @ViewBuilder private var centerBadge: some View {
        if showIndicator && !hovering {
            if let n = window.spaceNumber {
                badge(Text("\(n)").font(.system(size: 17, weight: .bold, design: .rounded)))
            } else if window.isHidden {
                badge(Image(systemName: "eye.slash"))
            }
        }
    }

    private func badge<V: View>(_ content: V) -> some View {
        content
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.black.opacity(0.6)))
            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
            .contentShape(Circle())
    }

    private var closeButton: some View {
        Button { model.onClose?(window) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(white: 0.15)))
                .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close window")
    }
}
