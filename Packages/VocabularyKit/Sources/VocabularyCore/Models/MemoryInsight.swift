import Foundation

public enum MemoryStrategy: String, Codable, CaseIterable, Sendable {
    case morphology
    case wordFamily = "word_family"
    case contrast
    case semanticBridge = "semantic_bridge"
    case imagery
    case soundSpelling = "sound_spelling"
    case context
    case directAssociation = "direct_association"

    public var displayNameZH: String {
        switch self {
        case .morphology: "构词拆解"
        case .wordFamily: "词族联想"
        case .contrast: "易混辨析"
        case .semanticBridge: "语义桥梁"
        case .imagery: "画面联想"
        case .soundSpelling: "声音与拼写"
        case .context: "语境锚点"
        case .directAssociation: "直接联想"
        }
    }
}

public struct MemoryInsight: Codable, Equatable, Hashable, Sendable {
    public var strategy: MemoryStrategy
    public var titleZH: String
    public var breakdown: String?
    public var cueZH: String
    public var mnemonic: String
    public var contrastNoteZH: String?

    public init(
        strategy: MemoryStrategy,
        titleZH: String,
        breakdown: String? = nil,
        cueZH: String,
        mnemonic: String,
        contrastNoteZH: String? = nil
    ) {
        self.strategy = strategy
        self.titleZH = titleZH
        self.breakdown = breakdown
        self.cueZH = cueZH
        self.mnemonic = mnemonic
        self.contrastNoteZH = contrastNoteZH
    }

    enum CodingKeys: String, CodingKey {
        case strategy
        case titleZH = "title_zh"
        case breakdown
        case cueZH = "cue_zh"
        case mnemonic
        case contrastNoteZH = "contrast_note_zh"
    }

    public func validated() throws -> MemoryInsight {
        let title = titleZH.trimmed
        let cue = cueZH.trimmed
        let memorySentence = mnemonic.trimmed
        let cleanBreakdown = breakdown?.trimmed.nilIfEmpty
        let cleanContrast = contrastNoteZH?.trimmed.nilIfEmpty

        guard !title.isEmpty,
              !cue.isEmpty,
              !memorySentence.isEmpty,
              title.count <= 30,
              cue.count <= 220,
              memorySentence.count <= 180,
              (cleanBreakdown?.count ?? 0) <= 100,
              (cleanContrast?.count ?? 0) <= 180 else {
            throw AIProviderError.schemaValidationFailed
        }

        return MemoryInsight(
            strategy: strategy,
            titleZH: title,
            breakdown: cleanBreakdown,
            cueZH: cue,
            mnemonic: memorySentence,
            contrastNoteZH: cleanContrast
        )
    }
}

public enum MemoryInsightFeedback: String, Codable, Equatable, Sendable {
    case helpful
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
