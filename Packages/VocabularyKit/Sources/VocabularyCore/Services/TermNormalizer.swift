import Foundation

public enum TermValidationError: Error, Equatable, Sendable {
    case empty
    case tooLong(maximum: Int)
}

public struct TermNormalizer: Sendable {
    public static let maximumLength = 120

    private static let dashCharacters: Set<Character> = ["‐", "‑", "‒", "–", "—", "−"]
    private static let apostropheCharacters: Set<Character> = ["‘", "’", "ʼ", "＇"]
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public init() {}

    public func displayTerm(_ term: String) throws -> String {
        let collapsed = term
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        guard !collapsed.isEmpty else {
            throw TermValidationError.empty
        }
        guard collapsed.count <= Self.maximumLength else {
            throw TermValidationError.tooLong(maximum: Self.maximumLength)
        }
        return collapsed.precomposedStringWithCanonicalMapping
    }

    public func normalize(_ term: String) throws -> String {
        let display = try displayTerm(term)
        let punctuationNormalized = String(display.map { character in
            if Self.dashCharacters.contains(character) { return "-" }
            if Self.apostropheCharacters.contains(character) { return "'" }
            return character
        })

        return punctuationNormalized
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Self.posixLocale)
            .lowercased(with: Self.posixLocale)
            .precomposedStringWithCanonicalMapping
    }
}
