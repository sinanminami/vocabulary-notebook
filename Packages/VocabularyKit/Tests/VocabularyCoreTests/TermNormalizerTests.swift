import Foundation
import Testing
@testable import VocabularyCore

@Suite("Term normalization")
struct TermNormalizerTests {
    private let normalizer = TermNormalizer()

    @Test("Trims and collapses whitespace")
    func whitespace() throws {
        #expect(try normalizer.displayTerm("  ablation\n\t study  ") == "ablation study")
        #expect(try normalizer.normalize("  Ablation\n study  ") == "ablation study")
    }

    @Test("Folds case, width, dashes, and apostrophes")
    func compatibilityCharacters() throws {
        #expect(try normalizer.normalize("State‑of‑the‑Art") == "state-of-the-art")
        #expect(try normalizer.normalize("Ｒｅｇｒｅｓｓｉｏｎ") == "regression")
        #expect(try normalizer.normalize("User’s") == "user's")
    }

    @Test("Keeps meaningful diacritics while applying NFC")
    func diacritics() throws {
        let decomposed = "re\u{301}sume\u{301}"
        #expect(try normalizer.normalize(decomposed) == "résumé")
        let plain = try normalizer.normalize("resume")
        let accented = try normalizer.normalize(decomposed)
        #expect(plain != accented)
    }

    @Test("Does not impose Latin-only behavior")
    func japanese() throws {
        #expect(try normalizer.normalize("  データ   分析 ") == "データ 分析")
    }

    @Test("Rejects empty and overlong terms")
    func validation() throws {
        do {
            _ = try normalizer.normalize(" \n ")
            Issue.record("Expected an empty-term error")
        } catch {
            #expect(error as? TermValidationError == .empty)
        }

        do {
            _ = try normalizer.normalize(String(repeating: "a", count: 121))
            Issue.record("Expected an overlong-term error")
        } catch {
            #expect(error as? TermValidationError == .tooLong(maximum: 120))
        }
    }
}
