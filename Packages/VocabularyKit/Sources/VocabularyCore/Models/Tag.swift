import Foundation

public struct Tag: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var normalizedName: String
    public var isSystem: Bool
    public var sortOrder: Int
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        name: String,
        normalizedName: String,
        isSystem: Bool,
        sortOrder: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
