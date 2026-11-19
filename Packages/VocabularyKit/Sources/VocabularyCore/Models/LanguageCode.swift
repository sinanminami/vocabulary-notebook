import Foundation

/// A stable, extensible language identifier. MVP values are `en` and `ja`,
/// while the storage format intentionally accepts future BCP-47 identifiers.
public struct LanguageCode: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public static let english = LanguageCode(rawValue: "en")
    public static let japanese = LanguageCode(rawValue: "ja")
    public static let undetermined = LanguageCode(rawValue: "und")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    public var description: String { rawValue }
}
