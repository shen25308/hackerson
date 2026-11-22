import SwiftUI

struct PuppetsRoot: View {
    var body: some View {
        NavigationStack {
            PuppetsView()
        }
        .tabChrome()
    }
}

/// 木偶工坊：同行的木偶、换人、抽到的牌。
struct PuppetsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @State private var drawing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                companion
                FatePersonaRow()
                roster
                strategy
                cards
            }
            .page()
            .padding(.vertical, 12)
        }
        .nightBackground(.docks)
        .navigationTitle("木偶工坊")
        .fullScreenCover(isPresented: $drawing) {
            DrawView().preferredColorScheme(.dark)
        }
    }

    private var companion: some View {
        let xp = store.xp
        let into = xp % Rules.xpPerLevel
        return HStack(alignment: .top, spacing: 14) {
            Image(store.role.art)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 106)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.role.name).font(Theme.brush(26)).foregroundStyle(Theme.text)
                    Text("Lv.\(store.level)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ember)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Meter(value: Double(store.hp) / 100, color: Theme.rose)
                    Text("生命 \(store.hp) / 100").font(.caption).foregroundStyle(Theme.dim)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Meter(value: Double(into) / Double(Rules.xpPerLevel))
                    Text("经验 \(xp) · 再 \(Rules.xpPerLevel - into) 升级").font(.caption).foregroundStyle(Theme.dim)
                }
                Text("专注 \(store.s.attack) · 韧性 \(store.s.magic) · 连续 \(store.s.streak) 天").font(.caption).foregroundStyle(Theme.dim)
            }
        }
    }

    private var roster: some View {
        let left = store.switchRemaining
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading("换一位同行", trailing: left > 0 ? "还差 \(left) 经验" : "现在可以换")
            ForEach(RoleID.allCases, id: \.self) { id in
                if let info = ROLES[id] {
                    let current = id == store.s.role
                    HStack(spacing: 12) {
                        Image(info.art)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 54, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(info.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(info.skill).font(.footnote).foregroundStyle(Theme.dim)
                        }
                        Spacer(minLength: 4)
                        if current {
                            Tag("同行中", color: Theme.ember, filled: true)
                        } else {
                            Button("换") { swap(to: id) }
                                .buttonStyle(.quietCompact)
                                .disabled(left > 0)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var strategy: some View {
        let tier = store.strategyTier
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading("夜谈第 \(tier + 1) 手", trailing: "做完 \(store.completed) 项")
            HStack(spacing: 6) {
                ForEach(Strategy.names.indices, id: \.self) { i in
                    VStack(spacing: 3) {
                        Text(Strategy.names[i]).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(i <= tier ? "已会" : "\(Strategy.thresholds[i]) 项").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(i <= tier ? Theme.ink : Theme.dim)
                    .background(i <= tier ? Theme.ember : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            Button("去火堆旁坐一局") { stage.openTalk(online: false) }.buttonStyle(.quiet)
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("抽到的牌", trailing: "\(store.s.cards.count) 张")
            Button(store.s.draws > 0 ? "抽一张 · 还有 \(store.s.draws) 次" : "还没有抽牌机会") {
                sfx(.drawShuffle)
                drawing = true
            }
            .buttonStyle(.ember)
            .disabled(store.s.draws < 1)
            if store.s.cards.isEmpty {
                Text("必做一件不漏，再多做一步额外，就有一次机会。连续三天不漏，再加一次。")
                    .font(.footnote).foregroundStyle(Theme.dim)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 14) {
                    ForEach(store.s.cards.reversed()) { card in
                        VStack(alignment: .leading, spacing: 5) {
                            Image(card.art)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 132)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(card.name).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(card.effect).font(.caption).foregroundStyle(Theme.ember)
                        }
                    }
                }
            }
        }
    }

    private func swap(to id: RoleID) {
        guard store.switchRole(id) else {
            sfx(.error)
            return
        }
        sfx(.levelup)
        stage.announce("\(ROLES[id]?.name ?? "")同行", "累计经验保留")
    }
}

/// 抽牌：先看到牌背，点一下才翻开、才消耗一次机会。
struct DrawView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var card: Keepsake?
    @State private var flip = 0.0
    @State private var sway = false

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                back.opacity(flip < 90 ? 1 : 0)
                front.opacity(flip < 90 ? 0 : 1).rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(width: 230, height: 318)
            .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotationEffect(.degrees(card == nil && sway ? 2 : card == nil ? -2 : 0))
            .onTapGesture { reveal() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(card == nil ? "翻开这张牌" : "\(card?.name ?? "")，\(card?.effect ?? "")")
            if let card {
                VStack(spacing: 6) {
                    Text(card.name).font(Theme.brush(28)).foregroundStyle(Theme.text)
                    Text(card.effect).font(.headline).foregroundStyle(Theme.ember)
                }
                .transition(.opacity)
            } else {
                Text("点一下翻开").font(.subheadline).foregroundStyle(Theme.dim)
            }
            Spacer()
            Button(card == nil ? "先收起来" : "收进木偶工坊") {
                sfx(.close)
                dismiss()
            }
            .buttonStyle(.quiet)
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nightBackground(.docks, quiet: true)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { sway = true }
        }
    }

    private var back: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.raised)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.ember.opacity(0.6), lineWidth: 1.5)
                    .padding(10)
            }
            .overlay { Text("？").font(Theme.brush(90)).foregroundStyle(Theme.ember) }
            .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
    }

    private var front: some View {
        Group {
            if let card {
                Image(card.art).resizable().scaledToFill()
            } else {
                Theme.raised
            }
        }
        .frame(width: 230, height: 318)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
    }

    private func reveal() {
        guard card == nil, let drawn = store.drawCard() else { return }
        sfx(.drawReveal)
        withAnimation(.easeInOut(duration: 0.7)) {
            flip = 180
            card = drawn
        }
    }
}
