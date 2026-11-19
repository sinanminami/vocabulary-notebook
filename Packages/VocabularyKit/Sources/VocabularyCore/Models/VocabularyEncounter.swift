import Foundation

public struct VocabularyEncounter: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let cardID: UUID
    public let senseID: UUID
    public var context: String?
    public var sourceApplication: String?
    public let encounteredAt: Date

    public init(
        id: UUID,
        cardID: UUID,
        senseID: UUID,
        context: String? = nil,
        sourceApplication: String? = nil,
        encounteredAt: Date
    ) {
        self.id = id
        self.cardID = cardID
        self.senseID = senseID
        self.context = context?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.sourceApplication = sourceApplication?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.encounteredAt = encounteredAt
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
