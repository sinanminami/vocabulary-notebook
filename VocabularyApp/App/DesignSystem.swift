import AppKit
import SwiftUI

/// 「浪漫 Romantic」配色：葡萄紫 #A78AD4、樱花粉 #F5B5CF、淡丁香 #D8C8ED、珍珠白 #FFF1E9。
/// 原色用于填充、背景与主按钮；会被用作文字/图标的语义色取同色相加深版本，保证浅色背景上可读。
enum AppTheme {
    // Palette swatches
    static let grape = Color(hex: 0xA78AD4)       // 葡萄紫
    static let sakura = Color(hex: 0xF5B5CF)      // 樱花粉
    static let lilac = Color(hex: 0xD8C8ED)       // 淡丁香
    static let pearl = Color(hex: 0xFFF1E9)       // 珍珠白

    // Semantic tints (deepened for legibility on light surfaces)
    static let accent = Color(hex: 0x8A6CC4)      // 主操作 · 葡萄紫加深
    static let accentStrong = Color(hex: 0x7D5DB4)
    static let accentSoft = Color(hex: 0xEFE7F8)  // 淡丁香浅底
    static let violet = Color(hex: 0x9A62B0)      // 词库 · 兰紫
    static let pink = Color(hex: 0xC25A88)        // 最近活动 · 深樱粉
    static let orange = Color(hex: 0xC4655F)      // 统计/学习压力 · 玫瑰珊瑚
    static let cyan = Color(hex: 0x5F78BE)        // 信息 · 远山蓝
    static let yellow = Color(hex: 0x9A7428)      // 新内容/提示 · 蜂蜜金

    // Surfaces
    static let canvas = Color(hex: 0xFDFBFA)
    static let sidebar = Color(hex: 0xF3ECFA)
    static let surface = Color.white
    static let surfaceRaised = pearl
    static let field = Color(hex: 0xFBF4EF)
    static let border = Color(hex: 0x6B4E8C).opacity(0.12)
    static let divider = Color(hex: 0x6B4E8C).opacity(0.10)
    static let shadow = Color(hex: 0x5B3F78)

    // Text
    static let graphite = Color(hex: 0x2F2635)
    static let warmSecondary = Color(hex: 0x76697E)
    static let glow = grape.opacity(0.35)

    static let cardRadius: CGFloat = 18
    static let compactRadius: CGFloat = 12

    /// Editorial display face (New York / Songti) for page titles and hero numbers.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum RelativeDateRole {
    case past
    case due
}

struct RelativeDateText: View {
    let date: Date
    var role: RelativeDateRole = .past
    var now: Date = Date()

    var body: some View {
        Text(relativeDate)
            .help(date.formatted(.dateTime.year().month().day().hour().minute()))
    }

    private var relativeDate: String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let targetDay = calendar.startOfDay(for: date)
        let dayDifference = calendar.dateComponents([.day], from: startOfToday, to: targetDay).day ?? 0

        switch role {
        case .due:
            if date <= now { return "现在该复习" }
            if calendar.isDateInToday(date) { return "今天" }
            if calendar.isDateInTomorrow(date) { return "明天" }
            if dayDifference <= 6 { return "\(dayDifference) 天后" }
        case .past:
            let secondsAgo = now.timeIntervalSince(date)
            if secondsAgo < 60 { return "刚刚" }
            if secondsAgo < 3_600 { return "\(max(1, Int(secondsAgo / 60))) 分钟前" }
            if calendar.isDateInToday(date) { return "今天" }
            if calendar.isDateInYesterday(date) { return "昨天" }
            if dayDifference >= -6 { return "\(-dayDifference) 天前" }
        }

        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let currentYear = calendar.component(.year, from: now)
        return year == currentYear ? "\(month) 月 \(day) 日" : "\(year) 年 \(month) 月 \(day) 日"
    }
}

struct AppPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var tint: Color = AppTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(tint)
            Text(title)
                .font(AppTheme.display(30))
                .foregroundStyle(AppTheme.graphite)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(AppTheme.warmSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppSectionHeading: View {
    let title: String
    let subtitle: String?
    let symbol: String?
    let tint: Color

    init(
        _ title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        tint: Color = AppTheme.accent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.graphite)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    var suffix: String? = nil
    var tint: Color = AppTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Circle()
                    .fill(tint.opacity(0.10))
                    .frame(width: 7, height: 7)
            }
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.warmSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 29, weight: .semibold, design: .serif))
                    .foregroundStyle(AppTheme.graphite)
                    .monospacedDigit()
                if let suffix {
                    Text(suffix)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.warmSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: 17, shadow: false)
    }
}

struct AppInlineMetric: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = AppTheme.accent
    var footnote: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AppIconBadge(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.warmSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(AppTheme.graphite)
                        .monospacedDigit()
                    if let footnote {
                        Text(footnote)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.warmSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppPill: View {
    let text: String
    var tint: Color = AppTheme.accent

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10), in: Capsule())
            .overlay { Capsule().stroke(tint.opacity(0.12), lineWidth: 0.5) }
    }
}

struct AppIconBadge: View {
    let symbol: String
    var tint: Color = AppTheme.accent
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.16), tint.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                    .stroke(tint.opacity(0.12), lineWidth: 0.5)
            }
    }
}

private struct AppCardModifier: ViewModifier {
    let padding: CGFloat
    let shadow: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.lilac.opacity(0.35), .clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.7
                    )
            }
            .shadow(color: AppTheme.shadow.opacity(shadow ? 0.05 : 0.025), radius: shadow ? 2 : 1, y: 1)
            .shadow(
                color: shadow ? AppTheme.shadow.opacity(0.07) : .clear,
                radius: shadow ? 22 : 0,
                y: shadow ? 10 : 0
            )
    }
}

private struct AppHeroCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.8)
            }
            .shadow(color: AppTheme.shadow.opacity(0.05), radius: 2, y: 1)
            .shadow(color: AppTheme.shadow.opacity(0.08), radius: 24, y: 12)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 19)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: configuration.isPressed
                        ? [AppTheme.accentStrong, AppTheme.accentStrong]
                        : [AppTheme.grape, AppTheme.accentStrong],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.7)
            }
            .shadow(color: AppTheme.accent.opacity(0.25), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct AppQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(AppTheme.graphite)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(
                configuration.isPressed ? AppTheme.accentSoft : AppTheme.surfaceRaised,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(AppTheme.border, lineWidth: 0.8)
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension View {
    func appCard(padding: CGFloat = 18, shadow: Bool = true) -> some View {
        modifier(AppCardModifier(padding: padding, shadow: shadow))
    }

    func appHeroCard(padding: CGFloat = 24) -> some View {
        modifier(AppHeroCardModifier(padding: padding))
    }

    func appPageBackground() -> some View {
        background(AppTheme.canvas.ignoresSafeArea())
    }

    func appFieldSurface(minHeight: CGFloat? = nil) -> some View {
        frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .padding(11)
            .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.8)
            }
    }
}

// MARK: - Word card fan
// The day's real words as tactile, sticker-like cards (after CapWords, ADA 2025 Delight & Fun):
// content itself is the hero decoration, not ornament.

struct WordCardFanItem: Identifiable {
    let id: UUID
    let term: String
    let meaning: String
    let language: String
}

struct WordCardFan: View {
    let items: [WordCardFanItem]
    var caption: String? = nil
    /// Plays the fan-out entrance on first appearance (skipped under Reduce Motion).
    var animatesIn: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSpread = false
    @State private var isFanned = false

    // One hue: the front card is paper, the cards behind it deepen into lilac.
    private static let fills: [[Color]] = [
        [Color.white, AppTheme.pearl.opacity(0.6)],
        [AppTheme.lilac.opacity(0.45), Color.white],
        [AppTheme.lilac.opacity(0.8), AppTheme.lilac.opacity(0.35)]
    ]
    private static let angles: [Double] = [-5, 4, 11]
    private static let offsets: [CGSize] = [CGSize(width: -18, height: 10), CGSize(width: 16, height: -6), CGSize(width: 46, height: -20)]

    private var showsFinalState: Bool { !animatesIn || reduceMotion }
    private var fanned: Bool { showsFinalState || isFanned }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach(Array(items.prefix(3).enumerated()).reversed(), id: \.element.id) { index, item in
                    let spread = fanned ? (isSpread ? 1.45 : 1) : 0.12
                    card(item, index: index)
                        .rotationEffect(.degrees(Self.angles[index] * (fanned ? (isSpread ? 1.5 : 1) : 0.2)))
                        .offset(
                            x: Self.offsets[index].width * spread,
                            y: Self.offsets[index].height * (fanned ? (isSpread ? 1.3 : 1) : 0.12)
                        )
                        .opacity(fanned || index == 0 ? 1 : 0)
                }
            }
            .frame(width: 250, height: 160)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
                    .padding(.top, 8)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { isSpread = hovering }
        }
        .onAppear {
            guard !showsFinalState, !isFanned else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.15)) { isFanned = true }
        }
        .accessibilityElement(children: .combine)
    }

    private func card(_ item: WordCardFanItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.language)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.accentSoft, in: Capsule())
                    .opacity(index == 0 ? 1 : 0)
                Spacer()
                Text(String(format: "%02d", index + 1))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.warmSecondary.opacity(0.8))
            }
            Spacer(minLength: 0)
            // Only the front card shows its word; back cards would peek out as cut-off fragments.
            Group {
                Text(item.term)
                    .font(AppTheme.display(23))
                    .foregroundStyle(AppTheme.graphite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(item.meaning)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
                    .lineLimit(1)
            }
            .opacity(index == 0 ? 1 : 0)
        }
        .padding(14)
        .frame(width: 186, height: 116, alignment: .topLeading)
        .background(
            LinearGradient(colors: Self.fills[index], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        // Sticker die-cut edge: thick white rim, then a hairline.
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 3.5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.6)
        }
        .shadow(color: AppTheme.shadow.opacity(0.08), radius: 1.5, y: 1)
        .shadow(color: AppTheme.shadow.opacity(0.14), radius: 14, y: 8)
        // Washi tape "holding" the front card onto the page.
        .overlay(alignment: .topLeading) {
            if index == 0 {
                WashiTape(color: AppTheme.sakura, width: 68, height: 19)
                    .rotationEffect(.degrees(-28))
                    .offset(x: -24, y: -4)
            }
        }
    }
}

// MARK: - Washi tape
// The page's single decorative device: it "holds" the front word card onto the paper.

/// Translucent washi tape with torn zig-zag ends and fine stripes.
struct WashiTape: View {
    var color: Color = AppTheme.sakura
    var width: CGFloat = 64
    var height: CGFloat = 18

    var body: some View {
        let shape = TornStrip()
        ZStack {
            shape.fill(color.opacity(0.62))
            Canvas { context, size in
                var x: CGFloat = -size.height
                while x < size.width {
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: x, y: size.height))
                    stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(stripe, with: .color(.white.opacity(0.35)), lineWidth: 1.2)
                    x += 6
                }
            }
            .clipShape(shape)
        }
        .frame(width: width, height: height)
        .shadow(color: AppTheme.shadow.opacity(0.10), radius: 1, y: 0.5)
        .accessibilityHidden(true)
    }

    private struct TornStrip: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let teeth = 4
            let depth: CGFloat = 3
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            for index in 1...teeth {
                let y = rect.minY + rect.height * CGFloat(index) / CGFloat(teeth)
                path.addLine(to: CGPoint(x: rect.maxX - (index.isMultiple(of: 2) ? 0 : depth), y: y))
            }
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            for index in (0..<teeth).reversed() {
                let y = rect.minY + rect.height * CGFloat(index) / CGFloat(teeth)
                path.addLine(to: CGPoint(x: rect.minX + (index.isMultiple(of: 2) ? 0 : depth), y: y))
            }
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Painted handwritten note
// A short handwritten aside next to the word cards, lettered as if with a loaded brush.

/// Deterministic pseudo-random value in 0..<1 for paint dab placement.
private func paintHash(_ n: Double) -> Double {
    let x = sin(n * 12.9898) * 43758.5453
    return x - x.rounded(.down)
}

/// Oil-paint texture: a base colour covered in short curved dabs of lighter and deeper tints.
struct PaintTexture: View {
    var base: Color = AppTheme.accent
    var light: Color = AppTheme.sakura
    var dark: Color = AppTheme.accentStrong
    var seed: Double = 9
    var dabs: Int = 260
    var dabLength: CGFloat = 5

    var body: some View {
        ZStack {
            base
            Canvas { context, size in
                for index in 0..<dabs {
                    let s = seed * 100 + Double(index)
                    let x = paintHash(s) * size.width
                    let y = paintHash(s + 1) * size.height
                    let angle = (paintHash(s + 2) - 0.5) * 0.9 + (y / max(size.height, 1) - 0.5) * 0.6
                    let length = Double(dabLength) * (0.6 + paintHash(s + 3))
                    var dab = Path()
                    dab.move(to: CGPoint(x: x, y: y))
                    dab.addQuadCurve(
                        to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                        control: CGPoint(x: x + cos(angle) * length / 2, y: y + sin(angle) * length / 2 - 1.5)
                    )
                    let isLight = paintHash(s + 4) > 0.45
                    let opacity = isLight ? 0.25 + paintHash(s + 5) * 0.35 : 0.12 + paintHash(s + 5) * 0.18
                    context.stroke(
                        dab,
                        with: .color((isLight ? light : dark).opacity(opacity)),
                        style: StrokeStyle(lineWidth: 1 + paintHash(s + 6) * 1.8, lineCap: .round)
                    )
                }
            }
        }
    }
}

/// Filled, tapered brush arrow: heavy where the brush lands, thin at the tip.
struct BrushArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        for index in 0...30 {
            let t = Double(index) / 30
            let x = Double(rect.minX) + Double(rect.width) * t
            let y = Double(rect.midY) + 6 - sin(t * .pi) * 9 - t * 4
            let halfWidth = 3.2 * (1 - t) + 0.6
            top.append(CGPoint(x: x, y: y - halfWidth))
            bottom.append(CGPoint(x: x, y: y + halfWidth))
        }
        var path = Path()
        path.move(to: top[0])
        top.forEach { path.addLine(to: $0) }
        bottom.reversed().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        let tip = top[top.count - 1]
        path.move(to: CGPoint(x: tip.x - 9, y: tip.y - 6))
        path.addLine(to: CGPoint(x: tip.x + 1, y: tip.y + 0.5))
        path.addLine(to: CGPoint(x: tip.x - 7, y: tip.y + 7))
        path.addLine(to: CGPoint(x: tip.x - 6, y: tip.y + 5))
        path.addLine(to: CGPoint(x: tip.x - 1, y: tip.y + 0.5))
        path.addLine(to: CGPoint(x: tip.x - 8, y: tip.y - 4))
        path.closeSubpath()
        return path
    }
}

/// Two-line handwritten aside in paint, with a brush arrow pointing right.
/// Writes itself in (fade + arrow sweep) after the card fan has opened; static under Reduce Motion.
struct PaintedHandNote: View {
    let lines: [String]
    /// Draws the brush arrow pointing right, at whatever sits beside the note.
    var showsArrow: Bool = true
    var animatesIn: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private static let fontName = "HannotateSC-W5"
    private var isShown: Bool { !animatesIn || reduceMotion || shown }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            lettering
                .foregroundStyle(.clear)
                .overlay { PaintTexture().mask { lettering } }
                .rotationEffect(.degrees(-4))
                .opacity(isShown ? 1 : 0)
                .offset(y: isShown ? 0 : 6)

            if showsArrow {
                PaintTexture(dabs: 24)
                    .frame(width: 40, height: 22)
                    .mask(BrushArrow())
                    // Sweep the arrow in from its tail, like a stroke being painted.
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: isShown ? 40 : 0)
                    }
            }
        }
        .onAppear {
            guard animatesIn, !reduceMotion, !shown else { return }
            withAnimation(.easeOut(duration: 0.6).delay(0.55)) { shown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.joined())
    }

    private var lettering: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(lines, id: \.self) { line in
                Text(line).font(.custom(Self.fontName, size: 19))
            }
        }
        .fixedSize()
    }
}
