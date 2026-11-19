import AppKit
import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.12, green: 0.84, blue: 0.38)
    static let accentStrong = Color(red: 0.11, green: 0.72, blue: 0.33)
    static let accentSoft = Color(red: 0.09, green: 0.20, blue: 0.13)
    static let violet = Color(red: 0.64, green: 0.36, blue: 1.00)
    static let pink = Color(red: 1.00, green: 0.25, blue: 0.55)
    static let orange = Color(red: 1.00, green: 0.42, blue: 0.18)
    static let cyan = Color(red: 0.15, green: 0.76, blue: 1.00)
    static let yellow = Color(red: 1.00, green: 0.87, blue: 0.18)
    static let canvas = Color(red: 0.047, green: 0.047, blue: 0.047)
    static let sidebar = Color.black
    static let surface = Color(red: 0.095, green: 0.095, blue: 0.095)
    static let surfaceRaised = Color(red: 0.145, green: 0.145, blue: 0.145)
    static let field = Color(red: 0.16, green: 0.16, blue: 0.16)
    static let border = Color.white.opacity(0.075)
    static let divider = Color.white.opacity(0.085)
    static let graphite = Color.white
    static let warmSecondary = Color(red: 0.70, green: 0.70, blue: 0.70)
    static let glow = Color(red: 0.08, green: 0.47, blue: 0.22).opacity(0.52)

    static let cardRadius: CGFloat = 18
    static let compactRadius: CGFloat = 12

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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(tint)
                    .frame(width: 18, height: 3)
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.65)
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
        HStack(alignment: .top, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.graphite)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.warmSecondary)
                }
            }
            Spacer(minLength: 0)
        }
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
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
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
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.30))
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
                            colors: [Color.white.opacity(0.075), .clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.7
                    )
            }
            .shadow(
                color: shadow ? Color.black.opacity(0.30) : .clear,
                radius: shadow ? 18 : 0,
                y: shadow ? 8 : 0
            )
    }
}

private struct AppHeroCardModifier: ViewModifier {
    let padding: CGFloat
    let tint: Color
    let secondaryTint: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.40),
                                    secondaryTint.opacity(0.22),
                                    AppTheme.surface
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Circle()
                        .fill(secondaryTint.opacity(0.26))
                        .frame(width: 250, height: 250)
                        .blur(radius: 58)
                        .offset(x: 82, y: -96)
                    Circle()
                        .stroke(tint.opacity(0.24), lineWidth: 20)
                        .frame(width: 168, height: 168)
                        .offset(x: 72, y: -72)
                    Circle()
                        .stroke(secondaryTint.opacity(0.18), lineWidth: 10)
                        .frame(width: 112, height: 112)
                        .offset(x: 64, y: -66)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.11), AppTheme.border],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: Color.black.opacity(0.34), radius: 24, y: 12)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 19)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: configuration.isPressed
                        ? [AppTheme.accentStrong, AppTheme.accentStrong]
                        : [AppTheme.accent, AppTheme.accentStrong],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
            }
            .shadow(color: AppTheme.accent.opacity(0.18), radius: 12, y: 6)
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

    func appHeroCard(
        padding: CGFloat = 24,
        tint: Color = AppTheme.accent,
        secondaryTint: Color = AppTheme.cyan
    ) -> some View {
        modifier(AppHeroCardModifier(
            padding: padding,
            tint: tint,
            secondaryTint: secondaryTint
        ))
    }

    func appPageBackground() -> some View {
        background {
            ZStack {
                AppTheme.canvas
                RadialGradient(
                    colors: [AppTheme.violet.opacity(0.16), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 520
                )
                RadialGradient(
                    colors: [AppTheme.cyan.opacity(0.10), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 460
                )
                LinearGradient(
                    colors: [AppTheme.pink.opacity(0.045), .clear, Color.black.opacity(0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
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
