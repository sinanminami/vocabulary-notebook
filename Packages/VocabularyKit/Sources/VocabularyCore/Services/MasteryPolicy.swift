public struct MasteryPolicy: Sendable {
    public let learningStabilityThreshold: Double
    public let masteredStabilityThreshold: Double
    public let masteredMinimumRepetitions: Int

    public init(
        learningStabilityThreshold: Double = 7,
        masteredStabilityThreshold: Double = 30,
        masteredMinimumRepetitions: Int = 5
    ) {
        self.learningStabilityThreshold = learningStabilityThreshold
        self.masteredStabilityThreshold = masteredStabilityThreshold
        self.masteredMinimumRepetitions = masteredMinimumRepetitions
    }

    public func level(for state: ReviewState) -> MasteryLevel {
        if state.reps == 0 || state.fsrsState == .new {
            return .new
        }
        if state.fsrsState == .learning
            || state.fsrsState == .relearning
            || state.stability < learningStabilityThreshold {
            return .learning
        }
        if state.fsrsState == .review
            && state.stability >= masteredStabilityThreshold
            && state.reps >= masteredMinimumRepetitions {
            return .mastered
        }
        return .familiar
    }
}
