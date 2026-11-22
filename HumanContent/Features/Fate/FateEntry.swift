import SwiftUI

/// 议事页里的四夜之约入口：进度、下一夜的门槛、开局或接着打，以及上一局测出的结果。
struct FateEntry: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var stage: Stage
    @ObservedObject private var fate = FateStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("十个人，三个提线人，四夜。")
                .font(Theme.title(22))
                .foregroundStyle(Theme.text)
            Text("每一夜的选择决定谁出事、谁被请出山庄，也一点点照出你是怎样做决定的人。")
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            FateEntryStatus(game: fate.game, completed: store.gateCount)
            Button(fate.inProgress ? "接着打" : "开局") {
                fate.wantsVerdict = false
                stage.openFate()
            }
            .buttonStyle(.ember)
            if let result = fate.last {
                FateEntryResult(result: result) {
                    fate.wantsVerdict = true
                    stage.openFate()
                } retest: {
                    fate.reset()
                    sfx(.undo)
                }
            }
        }
        .raised()
    }
}

/// 这一局走到哪了，下一夜还差几件事。
struct FateEntryStatus: View {
    let game: FateGame?
    let completed: Int

    var body: some View {
        let data = FateData.shared
        VStack(alignment: .leading, spacing: 6) {
            if let g = game, !g.finished {
                Text("已记下 \(g.answered) / 12 个抉择 · \(data.nightName(g.night))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.text)
                if let need = g.nextNightNeed(completed: completed), let n = g.upcomingNight {
                    Label("\(data.nightName(n))要再做完 \(need) 件事才会降临", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.rose)
                } else if let n = g.upcomingNight {
                    Label("\(data.nightName(n))已经可以开始", systemImage: "moon.stars")
                        .font(.footnote)
                        .foregroundStyle(Theme.moss)
                }
            } else {
                Text("第一夜随时可以开始；之后每一夜，都要你在现实里先做完一件事。")
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 上一局测出的结果：一行字加一张小立绘。
struct FateEntryResult: View {
    let result: FateResult
    let open: () -> Void
    let retest: () -> Void

    var body: some View {
        let data = FateData.shared
        let main = result.fit?.main ?? "villager"
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.hairline)
            HStack(spacing: 12) {
                Image("puppet_" + main)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(result.type) · \(result.typeInfo?.nick ?? "")")
                        .font(Theme.title(17))
                        .foregroundStyle(Theme.text)
                    Text("最像\(data.puppetName(main))")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 4)
                Button("看结果", action: open)
                    .buttonStyle(.quietCompact)
            }
            Button("重测（清空这一局）", action: retest)
                .buttonStyle(.tap(.undo))
                .font(.footnote)
                .foregroundStyle(Theme.dim)
        }
    }
}

/// 木偶工坊里的一行：上一局测出的牌风。没测过就什么都不显示。
struct FatePersonaRow: View {
    @ObservedObject private var fate = FateStore.shared

    var body: some View {
        if let r = fate.last {
            let data = FateData.shared
            let main = r.fit?.main ?? "villager"
            HStack(spacing: 12) {
                Image("puppet_" + main)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("牌风 \(r.type) · \(r.typeInfo?.nick ?? "") · 最像\(data.puppetName(main))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(r.typeInfo?.drive ?? "")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
