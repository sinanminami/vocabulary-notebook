// Offscreen preview of the Today layout built from DesignSystem components
// (no app launch, no database, no screen-recording permission needed). Sample data only.
// Usage:
//   swiftc -parse-as-library VocabularyApp/App/DesignSystem.swift Scripts/render_design_preview.swift -o /tmp/render
//   /tmp/render out.png 772      # second argument = content width in points (window width − sidebar)
import SwiftUI
import AppKit

private struct Row: View {
    let term: String, zh: String, when: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(term).font(AppTheme.display(15)).foregroundStyle(AppTheme.graphite).lineLimit(1)
            Text(zh).font(.callout).foregroundStyle(AppTheme.warmSecondary).lineLimit(1)
            Spacer(minLength: 8)
            Text(when).font(.caption).foregroundStyle(AppTheme.warmSecondary)
        }
        .padding(.vertical, 8)
    }
}

private struct Column<F: View>: View {
    let title: String, value: String, unit: String
    @ViewBuilder let footer: F
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(AppTheme.warmSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(AppTheme.display(28)).foregroundStyle(AppTheme.graphite)
                Text(unit).font(.caption).foregroundStyle(AppTheme.warmSecondary)
            }
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Mock: View {
    let stages: [(String, Int, Color)] = [
        ("待学习", 11, AppTheme.lilac.opacity(0.7)), ("学习中", 9, AppTheme.grape.opacity(0.6)),
        ("熟悉", 5, AppTheme.grape), ("已掌握", 0, AppTheme.accentStrong)
    ]
    var mastery: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeading("学习阶段", subtitle: "全部 25 个词义")
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(stages.filter { $0.1 > 0 }, id: \.0) { s in
                        Rectangle().fill(s.2).frame(width: (proxy.size.width - 4) * CGFloat(s.1) / 25)
                    }
                }.clipShape(Capsule())
            }.frame(height: 8)
            VStack(spacing: 8) {
                ForEach(stages, id: \.0) { s in
                    HStack(spacing: 8) {
                        Circle().fill(s.2).frame(width: 7, height: 7)
                        Text(s.0).font(.callout).foregroundStyle(AppTheme.graphite)
                        Spacer()
                        Text("\(s.1)").font(.callout).foregroundStyle(AppTheme.warmSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appCard(padding: 20, shadow: false)
    }
    var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeading("最近收录", subtitle: "按加入时间排列")
            VStack(spacing: 0) {
                Row(term: "sociological", zh: "社会学的", when: "昨天"); Divider().overlay(AppTheme.divider)
                Row(term: "domains", zh: "领域，域", when: "昨天"); Divider().overlay(AppTheme.divider)
                Row(term: "dynamically", zh: "动态地", when: "昨天"); Divider().overlay(AppTheme.divider)
                Row(term: "orchestrated", zh: "精心策划的", when: "昨天"); Divider().overlay(AppTheme.divider)
                Row(term: "architectural", zh: "架构的，建筑学的", when: "昨天")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appCard(padding: 20, shadow: false)
    }
    var fan: some View {
        WordCardFan(items: [
                    WordCardFanItem(id: UUID(), term: "reveal", meaning: "显示，揭示", language: "EN"),
                    WordCardFanItem(id: UUID(), term: "considerable", meaning: "相当大的，可观的", language: "EN"),
                    WordCardFanItem(id: UUID(), term: "initial results", meaning: "初步结果", language: "EN"),
                ], caption: "还有 21 个词义在等你", animatesIn: false)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            AppPageHeader(eyebrow: "11月20日 星期五", title: "今天有 13 个词义等你复习", subtitle: "先完成今天该复习的词，再回到阅读。")
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("24").font(AppTheme.display(52)).foregroundStyle(AppTheme.graphite)
                        Text("个词义待学习").font(.title3.weight(.medium)).foregroundStyle(AppTheme.warmSecondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("13 个到期复习 · 本次加入 11 个新词义 · 词库共 25 个词。").font(.callout).foregroundStyle(AppTheme.warmSecondary)
                        Text("今日新词额度：已学 0 · 上限 20").font(.caption).foregroundStyle(AppTheme.warmSecondary)
                    }
                    Button { } label: { Label("开始约 12 分钟复习", systemImage: "play.fill") }
                        .buttonStyle(AppPrimaryButtonStyle()).padding(.top, 4)
                }
                Spacer(minLength: 12)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
                        PaintedHandNote(lines: ["先从这三个", "开始吧"], animatesIn: false)
                        fan
                    }
                    VStack(spacing: 6) {
                        WordCardFan(items: [
                            WordCardFanItem(id: UUID(), term: "reveal", meaning: "显示，揭示", language: "EN"),
                            WordCardFanItem(id: UUID(), term: "considerable", meaning: "相当大的，可观的", language: "EN"),
                            WordCardFanItem(id: UUID(), term: "initial results", meaning: "初步结果", language: "EN"),
                        ], animatesIn: false)
                        PaintedHandNote(lines: ["先从这三个开始吧"], showsArrow: false, animatesIn: false)
                        Text("还有 21 个词义在等你").font(.caption).foregroundStyle(AppTheme.warmSecondary)
                    }
                }.padding(.trailing, 18)
            }
            .appHeroCard(padding: 28)
            HStack(alignment: .top, spacing: 0) {
                Column(title: "近 7 天复习", value: "0", unit: "次") {
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(0..<7, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(i == 6 ? AppTheme.accent : AppTheme.lilac).frame(width: 8, height: 4)
                        }
                    }.frame(height: 22, alignment: .bottom)
                }
                Divider().overlay(AppTheme.divider).padding(.horizontal, 20)
                Column(title: "连续学习", value: "0", unit: "天") { Text("今天复习一次就开始计数").font(.caption).foregroundStyle(AppTheme.warmSecondary) }
                Divider().overlay(AppTheme.divider).padding(.horizontal, 20)
                Column(title: "已熟悉", value: "5", unit: "/ 25") { Text("熟悉或已掌握的词义").font(.caption).foregroundStyle(AppTheme.warmSecondary) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .appCard(padding: 20, shadow: false)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { mastery.frame(minWidth: 300); recent.frame(minWidth: 300) }.fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 16) { mastery; recent }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 30)
        .frame(width: CGFloat(Double(CommandLine.arguments[2])!), alignment: .top)
        .appPageBackground()
        .environment(\.colorScheme, .light)
    }
}

@main
struct RenderMain {
    @MainActor static func main() {
        let renderer = ImageRenderer(content: Mock())
        renderer.scale = 1.5
        guard let image = renderer.cgImage else { fputs("render failed\n", stderr); exit(1) }
        let rep = NSBitmapImageRep(cgImage: image)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("ok")
    }
}
