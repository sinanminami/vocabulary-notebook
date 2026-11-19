import SwiftUI
import VocabularyCore

struct MemoryInsightContent: View {
    let insight: MemoryInsight
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 11) {
            HStack(spacing: 8) {
                AppPill(text: insight.strategy.displayNameZH, tint: AppTheme.yellow)
                Text(insight.titleZH)
                    .font(compact ? .callout.weight(.semibold) : .headline)
                    .foregroundStyle(AppTheme.graphite)
            }

            if let breakdown = insight.breakdown {
                Text(breakdown)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(AppTheme.cyan)
                    .textSelection(.enabled)
            }

            Text(insight.cueZH)
                .foregroundStyle(AppTheme.graphite.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Text(insight.mnemonic)
                .font(.callout.italic())
                .foregroundStyle(AppTheme.warmSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let contrast = insight.contrastNoteZH {
                Label(contrast, systemImage: "arrow.left.arrow.right")
                    .font(.callout)
                    .foregroundStyle(AppTheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MemoryInsightEditor: View {
    @Binding var insight: MemoryInsight?

    var body: some View {
        if insight != nil {
            VStack(alignment: .leading, spacing: 10) {
                Picker("策略", selection: strategyBinding) {
                    ForEach(MemoryStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.displayNameZH).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                TextField("标题", text: stringBinding(\.titleZH))
                    .textFieldStyle(.plain)
                    .appFieldSurface()
                TextField("构词拆解（不适用时留空）", text: optionalStringBinding(\.breakdown))
                    .textFieldStyle(.plain)
                    .appFieldSurface()
                TextField("中文记忆逻辑", text: stringBinding(\.cueZH), axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
                    .fixedSize(horizontal: false, vertical: true)
                    .appFieldSurface(minHeight: 64)
                TextField("记忆句或联想", text: stringBinding(\.mnemonic), axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .fixedSize(horizontal: false, vertical: true)
                    .appFieldSurface(minHeight: 58)
                TextField("易混提醒（不适用时留空）", text: optionalStringBinding(\.contrastNoteZH), axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .fixedSize(horizontal: false, vertical: true)
                    .appFieldSurface(minHeight: 58)
            }
            .padding(14)
            .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var strategyBinding: Binding<MemoryStrategy> {
        Binding(
            get: { insight?.strategy ?? .directAssociation },
            set: { value in mutate { $0.strategy = value } }
        )
    }

    private func stringBinding(_ keyPath: WritableKeyPath<MemoryInsight, String>) -> Binding<String> {
        Binding(
            get: { insight?[keyPath: keyPath] ?? "" },
            set: { value in mutate { $0[keyPath: keyPath] = value } }
        )
    }

    private func optionalStringBinding(
        _ keyPath: WritableKeyPath<MemoryInsight, String?>
    ) -> Binding<String> {
        Binding(
            get: { insight?[keyPath: keyPath] ?? "" },
            set: { value in
                mutate {
                    $0[keyPath: keyPath] = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : value
                }
            }
        )
    }

    private func mutate(_ change: (inout MemoryInsight) -> Void) {
        guard var value = insight else { return }
        change(&value)
        insight = value
    }
}
