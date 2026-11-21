import SwiftUI

// 占位：反向体验与五席夜谈两个模块写好后，这个文件会被删掉。
struct TalkView: View {
    var body: some View { Text("五席夜谈").foregroundStyle(Theme.text) }
}

struct LabView: View {
    let entry: LabEntry
    var body: some View { Text("木偶剧场").foregroundStyle(Theme.text) }
}

struct LabMenuSheet: View {
    var body: some View { Text("木偶剧场").foregroundStyle(Theme.text) }
}
