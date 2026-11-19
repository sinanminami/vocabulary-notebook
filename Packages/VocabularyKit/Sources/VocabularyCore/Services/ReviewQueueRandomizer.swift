public struct ReviewQueueRandomizer: Sendable {
    public init() {}

    public func randomized<Item>(_ items: [Item]) -> [Item] {
        items.shuffled()
    }

    public func randomized<Item, R: RandomNumberGenerator>(
        _ items: [Item],
        using generator: inout R
    ) -> [Item] {
        items.shuffled(using: &generator)
    }
}
