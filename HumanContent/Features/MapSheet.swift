import SwiftUI

/// 迷雾地图：四张场景画连成一条路。做完的任务越多，散开的雾越多。
struct MapSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @AppStorage("map.seen") private var seenRaw = "board,theater,fire,tower"
    @State private var selected: String?
    @State private var fresh: Set<String> = []
    @State private var denied = 0

    private var seen: Set<String> { Set(seenRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        SheetScaffold(title: "迷雾地图") {
            header
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { scene in
                    panel(scene)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if store.unlockAll {
                Text("演示模式：全部地点已开门。").font(.footnote).foregroundStyle(Theme.dim)
            }
        }
        .safeAreaInset(edge: .bottom) { detail }
        .onAppear(perform: reveal)
    }

    private var header: some View {
        let done = store.completed
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(done)").font(Theme.brush(44)).foregroundStyle(Theme.ember)
            VStack(alignment: .leading, spacing: 2) {
                Text("项任务整件做完").font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                if let next = Atlas.next(completed: store.gateCount) {
                    Text("再做完 \(next.need - store.gateCount) 项，\(next.name)开门").font(.footnote).foregroundStyle(Theme.dim)
                } else {
                    Text("山庄的雾全散了").font(.footnote).foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private func panel(_ scene: Int) -> some View {
        let open = Atlas.sceneOpen(scene, completed: store.gateCount)
        let places = Atlas.places.filter { $0.scene == scene }.sorted { $0.need < $1.need }
        return Image(Atlas.sceneArt[scene])
            .resizable()
            .aspectRatio(1024.0 / 644.0, contentMode: .fit)
            .saturation(open ? 1 : 0.1)
            .brightness(open ? 0 : -0.22)
            .blur(radius: open ? 0 : 5)
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    ZStack(alignment: .topLeading) {
                        if !open { Theme.night.opacity(0.45) }
                        trail(places, w: w, h: h)
                            .stroke(Theme.paper.opacity(open ? 0.75 : 0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
                        ForEach(places) { place in
                            pin(place)
                                .position(x: CGFloat(place.x) * w, y: CGFloat(place.y) * h)
                        }
                        Text(Atlas.scenes[scene])
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.text.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.night.opacity(0.7), in: Capsule())
                            .padding(10)
                    }
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.8), value: open)
    }

    /// 从画的上沿进来，依次经过各个地点，从下沿出去。
    private func trail(_ places: [Place], w: CGFloat, h: CGFloat) -> Path {
        var points = [CGPoint(x: w * 0.5, y: 0)]
        points += places.sorted { $0.y < $1.y }.map { CGPoint(x: CGFloat($0.x) * w, y: CGFloat($0.y) * h) }
        points.append(CGPoint(x: w * 0.5, y: h))
        var path = Path()
        path.move(to: points[0])
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let mid = (a.y + b.y) / 2
            path.addCurve(to: b, control1: CGPoint(x: a.x, y: mid), control2: CGPoint(x: b.x, y: mid))
        }
        return path
    }

    private func pin(_ place: Place) -> some View {
        let open = store.isOpen(place.id)
        let chosen = selected == place.id
        let isNew = fresh.contains(place.id)
        return Button {
            selected = place.id
            sfx(open ? .scan : .lock, strength: 0.7)
            if !open { withAnimation(.default) { denied += 1 } }
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    if !open { Image(systemName: "lock.fill").font(.system(size: 9)) }
                    Text(place.name).font(Theme.brush(14))
                }
                .foregroundStyle(open ? Theme.ink : Theme.text.opacity(0.8))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(open ? (isNew ? Theme.ember : Theme.paper) : Theme.raised, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay {
                    if chosen { RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Theme.ember, lineWidth: 2) }
                }
                Circle().fill(open ? Theme.ember : Theme.dim).frame(width: 7, height: 7)
            }
            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
            .background {
                if !open { Ellipse().fill(Theme.night.opacity(0.7)).frame(width: 110, height: 70).blur(radius: 16) }
            }
            .scaleEffect(isNew ? 1.18 : (chosen ? 1.08 : 1))
            .modifier(Shake(amount: chosen && !open ? CGFloat(denied) : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(open ? "\(place.name)，已开门" : "\(place.name)，还差 \(place.need - store.gateCount) 项")
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selected, let place = Atlas.place(id) {
            let open = store.isOpen(id)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(place.name).font(Theme.brush(22)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(open ? "已开门" : "做完 \(place.need) 项开门").font(.caption).foregroundStyle(open ? Theme.moss : Theme.dim)
                }
                Text(place.feature).font(.subheadline).foregroundStyle(Theme.text.opacity(0.85))
                if open {
                    Button("进去") {
                        sfx(.open)
                        stage.enter(id)
                    }
                    .buttonStyle(.ember)
                } else {
                    Meter(value: Double(store.gateCount) / Double(max(1, place.need)))
                    Button("去任务板，还差 \(place.need - store.gateCount) 项") { stage.go(.tasks) }
                        .buttonStyle(.quiet)
                }
            }
            .padding(16)
            .background(Theme.raised)
            .transition(.move(edge: .bottom))
        }
    }

    /// 打开地图时，把上次看过之后新开的地点亮一下。
    private func reveal() {
        let open = Set(Atlas.places.filter { store.isOpen($0.id) }.map(\.id))
        let newly = open.subtracting(seen)
        guard !newly.isEmpty, !store.unlockAll else { return }
        seenRaw = open.union(seen).sorted().joined(separator: ",")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            sfx(.unlock)
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { fresh = newly }
            selected = Atlas.places.filter { newly.contains($0.id) }.max { $0.need < $1.need }?.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.5)) { fresh = [] }
        }
    }
}
