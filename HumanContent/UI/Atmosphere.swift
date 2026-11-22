import SwiftUI

/// 页面背后是山庄的哪一处。
enum Backdrop {
    case street, square, chapel, docks

    var art: String {
        switch self {
        case .street: return "pano_street"
        case .square: return "pano_square"
        case .chapel: return "pano_chapel"
        case .docks: return "pano_docks"
        }
    }

    /// 画里对准屏幕中线的位置（0…1）。
    var focus: CGFloat {
        switch self {
        case .street: return 0.5
        case .square: return 0.47
        case .chapel: return 0.4
        case .docks: return 0.36
        }
    }

    /// 原画偏暗的场景提亮一点。
    var lift: Double {
        switch self {
        case .street: return 0.08
        case .square: return 0.04
        default: return 0
        }
    }

    /// 灯火在屏幕上的位置。
    var glow: UnitPoint {
        switch self {
        case .street: return UnitPoint(x: 0.56, y: 0.3)
        case .square: return UnitPoint(x: 0.56, y: 0.62)
        case .chapel: return UnitPoint(x: 0.5, y: 0.42)
        case .docks: return UnitPoint(x: 0.3, y: 0.4)
        }
    }
}

/// 夜里的山庄：压暗的场景画、暗角、缓缓移动的雾、忽明忽暗的灯火、垂下来的提线、胶片颗粒，
/// 以及偶尔在暗处睁开的一双眼睛。
struct Atmosphere: View {
    var backdrop: Backdrop = .chapel
    /// 弹出面板里更暗、更安静，不放眼睛。
    var quiet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false
    @State private var sway = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Color.black
                scene(size)
                glow(size)
                scrim
                fog(size)
                strings(size)
                if !quiet && !reduceMotion { LurkingEyes(size: size) }
                Image("grain")
                    .resizable(resizingMode: .tile)
                    .blendMode(.overlay)
                    .opacity(0.22)
                RadialGradient(colors: [.clear, .black.opacity(0.62)], center: .center,
                               startRadius: size.width * 0.3, endRadius: size.height * 0.72)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) { drift = true }
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) { sway = true }
        }
    }

    private func scene(_ size: CGSize) -> some View {
        let height = size.height * 1.08
        let width = height * 1024 / 644
        let slack: CGFloat = 16
        let centered = size.width / 2 - backdrop.focus * width
        let x = min(-slack, max(size.width - width + slack, centered))
        return Image(backdrop.art)
            .resizable()
            .frame(width: width, height: height)
            .saturation(0.74)
            .contrast(1.1)
            .brightness(backdrop.lift)
            .offset(x: x + (drift ? -slack : slack), y: -size.height * 0.04)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(quiet ? 0.5 : 0.18), location: 0),
            .init(color: .black.opacity(quiet ? 0.7 : 0.44), location: 0.3),
            .init(color: .black.opacity(quiet ? 0.86 : 0.72), location: 0.66),
            .init(color: .black.opacity(quiet ? 0.95 : 0.9), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// 灯火：亮度不规则地抖动。
    private func glow(_ size: CGSize) -> some View {
        TimelineView(.periodic(from: .now, by: 0.14)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let n = reduceMotion ? 0 : sin(t * 7.3) * 0.5 + sin(t * 13.1) * 0.3 + sin(t * 2.1) * 0.2
            Circle()
                .fill(RadialGradient(colors: [Theme.ember.opacity(0.34 + 0.12 * n), .clear], center: .center, startRadius: 0, endRadius: 170))
                .frame(width: 340, height: 340)
                .position(x: backdrop.glow.x * size.width, y: backdrop.glow.y * size.height)
                .blendMode(.screen)
        }
    }

    private func fog(_ size: CGSize) -> some View {
        let bank = RadialGradient(colors: [Theme.text.opacity(0.13), .clear], center: .center, startRadius: 0, endRadius: size.width * 0.7)
        return ZStack {
            Circle().fill(bank)
                .frame(width: size.width * 1.4, height: size.width * 1.4)
                .scaleEffect(x: 1, y: 0.22)
                .position(x: size.width * (drift ? 0.72 : 0.3), y: size.height * 0.24)
            Circle().fill(bank)
                .frame(width: size.width * 1.4, height: size.width * 1.4)
                .scaleEffect(x: 1, y: 0.16)
                .position(x: size.width * (drift ? 0.2 : 0.66), y: size.height * 0.5)
        }
    }

    /// 从屏幕顶上垂下来的几根提线，末端打着结，轻轻晃。
    private func strings(_ size: CGSize) -> some View {
        let places: [(x: CGFloat, length: CGFloat, swing: Double)] = [(0.08, 0.17, 1.4), (0.29, 0.08, -2.2), (0.75, 0.12, 1.8), (0.93, 0.22, -1.1)]
        return ZStack(alignment: .topLeading) {
            ForEach(places.indices, id: \.self) { i in
                let place = places[i]
                VStack(spacing: 0) {
                    Rectangle().frame(width: 1, height: place.length * size.height)
                    Circle().frame(width: 4, height: 4)
                }
                .foregroundStyle(Theme.text.opacity(0.26))
                .rotationEffect(.degrees(sway ? place.swing : -place.swing), anchor: .top)
                .offset(x: place.x * size.width)
            }
        }
    }
}

/// 暗处偶尔睁开又闭上的一双眼睛。
private struct LurkingEyes: View {
    let size: CGSize
    @State private var open = false
    @State private var spot = CGPoint(x: 80, y: 160)

    var body: some View {
        HStack(spacing: 8) {
            eye
            eye
        }
        .opacity(open ? 0.9 : 0)
        .position(spot)
        .task { await watch() }
    }

    private var eye: some View {
        Ellipse()
            .fill(Theme.ember)
            .frame(width: 5, height: 3)
            .shadow(color: Theme.ember, radius: 5)
    }

    private func watch() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 6...15) * 1_000_000_000)
            guard !Task.isCancelled, size.width > 80, size.height > 200 else { continue }
            spot = CGPoint(x: CGFloat.random(in: 36...(size.width - 36)),
                           y: CGFloat.random(in: (size.height * 0.08)...(size.height * 0.3)))
            withAnimation(.easeIn(duration: 0.8)) { open = true }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.12)) { open = false }
            try? await Task.sleep(nanoseconds: 260_000_000)
            withAnimation(.easeIn(duration: 0.12)) { open = true }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeOut(duration: 0.3)) { open = false }
        }
    }
}
