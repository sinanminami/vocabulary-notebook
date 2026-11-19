import Foundation
import Observation
import VocabularyCore

@MainActor
@Observable
final class DataManagementViewModel {
    private(set) var healthReport: VocabularyDataHealthReport?
    private(set) var isWorking = false
    var statusMessage: String?
    var errorMessage: String?

    private let vocabularyRepository: any VocabularyRepository
    private let reviewStateRepository: any ReviewStateRepository
    private let tagRepository: any TagRepository
    private let exportService = VocabularyExportService()

    init(
        vocabularyRepository: any VocabularyRepository,
        reviewStateRepository: any ReviewStateRepository,
        tagRepository: any TagRepository
    ) {
        self.vocabularyRepository = vocabularyRepository
        self.reviewStateRepository = reviewStateRepository
        self.tagRepository = tagRepository
    }

    func loadHealthReport() async {
        do {
            async let cards = vocabularyRepository.fetchAll()
            async let assignments = tagRepository.fetchTagIDsByCardID()
            healthReport = try await exportService.healthReport(
                cards: cards,
                tagIDsByCardID: assignments
            )
        } catch {
            errorMessage = "无法检查本地数据：\(error.localizedDescription)"
        }
    }

    func prepareCSV() async -> Data? {
        guard !isWorking else { return nil }
        isWorking = true
        statusMessage = nil
        errorMessage = nil
        do {
            async let cards = vocabularyRepository.fetchAll()
            async let states = reviewStateRepository.fetchAll()
            async let tags = tagRepository.fetchAll()
            async let assignments = tagRepository.fetchTagIDsByCardID()
            let data = try await exportService.csvData(
                cards: cards,
                tags: tags,
                tagIDsByCardID: assignments,
                reviewStates: states
            )
            isWorking = false
            return data
        } catch {
            errorMessage = "无法准备导出文件：\(error.localizedDescription)"
            isWorking = false
            return nil
        }
    }

    func markExported(fileName: String) {
        statusMessage = "已导出到 \(fileName)。"
        errorMessage = nil
    }

    func reportExportFailure(_ error: Error) {
        errorMessage = "无法写入导出文件：\(error.localizedDescription)"
        statusMessage = nil
    }
}
