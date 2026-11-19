public struct ReviewRequeuePolicy: Sendable {
    public init() {}

    /// `Again` creates a short FSRS learning step. Keep that step inside the
    /// current session so the UI never declares completion while the item is
    /// about to become due again.
    public func shouldRequeue(after log: ReviewLogEntry) -> Bool {
        log.rating == .again
    }
}
