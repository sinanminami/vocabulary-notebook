import Foundation
import Observation
import VocabularyCore

@MainActor
@Observable
final class TagSettingsViewModel {
    private(set) var tags: [Tag] = []
    var newTagName = ""
    var editingTagID: UUID?
    var editingName = ""
    private(set) var isWorking = false
    var statusMessage: String?
    var errorMessage: String?

    private let repository: any TagRepository

    init(repository: any TagRepository) {
        self.repository = repository
    }

    var systemTags: [Tag] { tags.filter(\.isSystem) }
    var customTags: [Tag] { tags.filter { !$0.isSystem } }

    func load() async {
        do {
            tags = try await repository.fetchAll()
        } catch {
            errorMessage = "无法读取标签：\(error.localizedDescription)"
        }
    }

    func create() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        clearMessages()
        do {
            _ = try await repository.create(name: newTagName, at: Date())
            newTagName = ""
            statusMessage = "自定义标签已添加。"
            tags = try await repository.fetchAll()
            isWorking = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isWorking = false
            return false
        }
    }

    func beginRename(_ tag: Tag) {
        editingTagID = tag.id
        editingName = tag.name
        clearMessages()
    }

    func cancelRename() {
        editingTagID = nil
        editingName = ""
    }

    func saveRename() async -> Bool {
        guard let editingTagID, !isWorking else { return false }
        isWorking = true
        clearMessages()
        do {
            _ = try await repository.rename(
                id: editingTagID,
                name: editingName,
                at: Date()
            )
            cancelRename()
            statusMessage = "标签名称已更新。"
            tags = try await repository.fetchAll()
            isWorking = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isWorking = false
            return false
        }
    }

    func delete(_ tag: Tag) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        clearMessages()
        do {
            try await repository.delete(id: tag.id)
            statusMessage = "自定义标签已删除，词卡本身不受影响。"
            tags = try await repository.fetchAll()
            isWorking = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isWorking = false
            return false
        }
    }

    private func clearMessages() {
        statusMessage = nil
        errorMessage = nil
    }
}
