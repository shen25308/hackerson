import SwiftUI

enum OnboardingExit {
    case write, demo, enter
}

/// 第一次进山庄时的开场：四页，讲清这里在玩什么。
struct OnboardingView: View {
    var startPage = 0
    let finish: (OnboardingExit) -> Void
    @State private var page = 0
    @State private var shown = false

    private struct Page {
        let backdrop: Backdrop
        let symbol: String
        let title: String
        let lines: [String]
    }

    private static let pages = [
        Page(backdrop: .street, symbol: "eye", title: "夜巡山庄",
             lines: ["这里的界面不太老实。", "它会抢着替你做决定。"]),
        Page(backdrop: .chapel, symbol: "checklist", title: "先答应自己一件事",
             lines: ["写在任务板上，现实里做完，再回来亲手登记。", "每做完一件，山庄的雾散一处。"]),
        Page(backdrop: .square, symbol: "scissors", title: "火堆旁有人说话",
             lines: ["三张字条里，有一张在牵着你走。", "五个守夜人里，有一个拿了钥匙。", "听完，决定还是你下。"]),
        Page(backdrop: .docks, symbol: "hand.raised", title: "守住你的人类含量",
             lines: ["界面会递诱饵、替你勾选、用倒计时替你决定。", "亲手拦下，含量才不掉。"]),
    ]

    private var last: Bool { page == Self.pages.count - 1 }

    var body: some View {
        let current = Self.pages[min(page, Self.pages.count - 1)]
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                if !last {
                    Button("跳过") { leave(.enter) }
                        .buttonStyle(.tap(.close))
                        .font(.subheadline)
                        .foregroundStyle(Theme.text.opacity(0.7))
                }
            }
            .frame(height: 44)
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: current.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.ember)
                Text(current.title)
                    .font(Theme.brush(38))
                    .foregroundStyle(Theme.text)
                    .shadow(color: .black, radius: 10)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(current.lines, id: \.self) { line in
                        Text(line)
                            .font(.title3)
                            .foregroundStyle(Theme.text.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .id(page)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .transition(.opacity)
            Spacer().frame(height: 34)
            HStack(spacing: 7) {
                ForEach(Self.pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.ember : Theme.text.opacity(0.25))
                        .frame(width: i == page ? 22 : 7, height: 7)
                }
            }
            .padding(.bottom, 22)
            actions
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            Atmosphere(backdrop: current.backdrop)
                .id(page)
                .transition(.opacity)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !last { advance() } }
        .onAppear {
            page = min(max(0, startPage), Self.pages.count - 1)
            sfx(.whoosh)
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) { shown = true }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actions: some View {
        if last {
            VStack(spacing: 10) {
                Button("写下第一件事") { leave(.write) }.buttonStyle(.ember)
                Button("先看看示例") { leave(.demo) }.buttonStyle(.quiet)
                Button("直接进山庄") { leave(.enter) }
                    .buttonStyle(.tap(.close))
                    .font(.subheadline)
                    .foregroundStyle(Theme.text.opacity(0.7))
                    .padding(.top, 4)
            }
        } else {
            Button("继续") { advance() }.buttonStyle(.ember)
        }
    }

    private func advance() {
        sfx(.paper)
        shown = false
        withAnimation(.easeInOut(duration: 0.45)) { page += 1 }
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) { shown = true }
    }

    private func leave(_ exit: OnboardingExit) {
        sfx(exit == .enter ? .close : .unlock)
        finish(exit)
    }
}
