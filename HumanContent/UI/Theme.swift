import SwiftUI
import UIKit

/// 配色取自山庄的画：夜色做底，纸条和墨字承载内容，火光是唯一的强调色。
enum Theme {
    static let night = Color(red: 0.086, green: 0.067, blue: 0.106)
    static let raised = Color(red: 0.133, green: 0.106, blue: 0.157)
    static let hairline = Color.white.opacity(0.09)
    static let text = Color(red: 0.93, green: 0.9, blue: 0.85)
    static let dim = Color(red: 0.66, green: 0.62, blue: 0.68)
    static let paper = Color(red: 0.937, green: 0.9, blue: 0.82)
    static let paperShade = Color(red: 0.86, green: 0.81, blue: 0.71)
    static let ink = Color(red: 0.13, green: 0.1, blue: 0.14)
    static let inkSoft = Color(red: 0.37, green: 0.33, blue: 0.38)
    static let ember = Color(red: 0.89, green: 0.56, blue: 0.25)
    static let rose = Color(red: 0.8, green: 0.3, blue: 0.45)
    static let moss = Color(red: 0.52, green: 0.66, blue: 0.44)

    /// 标题用宋体（设备上没有就退回系统字体）。
    static func title(_ size: CGFloat) -> Font {
        if UIFont(name: "STSongti-SC-Bold", size: size) != nil {
            return .custom("STSongti-SC-Bold", size: size)
        }
        return .system(size: size, weight: .bold)
    }

    static func brush(_ size: CGFloat) -> Font {
        if UIFont(name: "STSongti-SC-Black", size: size) != nil {
            return .custom("STSongti-SC-Black", size: size)
        }
        return .system(size: size, weight: .heavy)
    }
}

// MARK: 按钮

/// 主要动作：火光色实心。
struct EmberButtonStyle: ButtonStyle {
    var danger = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(danger ? Theme.rose : Theme.ember, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { sfx(.click) }
            }
    }
}

/// 次要动作：只有文字和一条细线。
struct QuietButtonStyle: ButtonStyle {
    var fill = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: 46)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.35)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { sfx(.click, strength: 0.7) }
            }
    }
}

/// 纸面上的按钮：墨色实心。
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(Theme.ink, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.3)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { sfx(.click) }
            }
    }
}

/// 行内的文字按钮，按下时出声。
struct TapStyle: ButtonStyle {
    var cue: Cue = .click

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { sfx(cue, strength: 0.8) }
            }
    }
}

extension ButtonStyle where Self == EmberButtonStyle {
    static var ember: EmberButtonStyle { EmberButtonStyle() }
    static var danger: EmberButtonStyle { EmberButtonStyle(danger: true) }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
    static var quietCompact: QuietButtonStyle { QuietButtonStyle(fill: false) }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var ink: InkButtonStyle { InkButtonStyle() }
}

extension ButtonStyle where Self == TapStyle {
    static var tap: TapStyle { TapStyle() }
    static func tap(_ cue: Cue) -> TapStyle { TapStyle(cue: cue) }
}

// MARK: 容器

extension View {
    /// 一张纸条：米色底、墨色字。
    func paper(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Theme.ink)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
    }

    /// 夜色里稍稍抬起的一块。
    func raised(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// 页面底色与统一的左右留白。
    func page() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
    }

    func nightBackground() -> some View {
        self.background(Theme.night.ignoresSafeArea())
    }
}

struct Tag: View {
    let text: String
    var color: Color = Theme.dim
    var filled = false

    init(_ text: String, color: Color = Theme.dim, filled: Bool = false) {
        self.text = text
        self.color = color
        self.filled = filled
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? Theme.ink : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(filled ? color : color.opacity(0.16), in: Capsule())
    }
}

struct Meter: View {
    var value: Double
    var color: Color = Theme.ember
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(color).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

struct SectionHeading: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.title(20)).foregroundStyle(Theme.text)
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(Theme.dim) }
        }
    }
}

/// 表单里的一栏：标签在上，输入在下。
struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Theme.dim)
            content
        }
    }
}

struct InputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(Theme.text)
            .tint(Theme.ember)
    }
}

extension View {
    func input() -> some View { modifier(InputStyle()) }

    /// 打字时出声。
    func typingSound<V: Equatable>(_ value: V) -> some View {
        onChange(of: value) { _, _ in sfx(.type) }
    }
}

/// 弹出的半屏面板统一用这个壳：标题、关闭按钮、可滚动的内容。
struct SheetScaffold<Content: View>: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .page()
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .nightBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        sfx(.close)
                        dismiss()
                    }
                    .tint(Theme.dim)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear { sfx(.paper) }
    }
}

/// 长按才算数的按钮：按住时进度推进、音调升高，松手就归零。
struct HoldButton: View {
    let title: String
    var seconds: Double = 1.1
    var color: Color = Theme.ember
    let action: () -> Void

    @State private var progress = 0.0
    @State private var timer: Timer?
    @State private var holding = false

    var body: some View {
        Text(holding ? "按住…" : title)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        color.opacity(0.62)
                        color.frame(width: geo.size.width * progress)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(holding ? 0.98 : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in begin() }
                    .onEnded { _ in cancel() }
            )
            .onDisappear { timer?.invalidate() }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("长按确认")
            .accessibilityAction { action() }
    }

    private func begin() {
        guard !holding else { return }
        holding = true
        progress = 0
        var step = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
            step += 1
            progress = min(1, Double(step) * 0.05 / seconds)
            if step % 3 == 0 { sfx(.hold, pitch: 1 + progress * 0.8) }
            if progress >= 1 {
                t.invalidate()
                timer = nil
                holding = false
                action()
            }
        }
    }

    private func cancel() {
        guard holding else { return }
        timer?.invalidate()
        timer = nil
        holding = false
        if progress < 1 {
            withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            sfx(.focusPause, strength: 0.5)
        }
    }
}

/// 一行键值，用在各种清单里。
struct LedgerRow: View {
    let label: String
    let value: String
    var color: Color = Theme.text

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).foregroundStyle(color).fontWeight(.medium).monospacedDigit()
        }
        .font(.subheadline)
        .padding(.vertical, 6)
    }
}

/// 空状态：一句话加一个动作。
struct EmptyNote: View {
    let title: String
    var action: String?
    var run: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.body).foregroundStyle(Theme.dim)
            if let action, let run {
                Button(action, action: run).buttonStyle(.quietCompact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }
}
