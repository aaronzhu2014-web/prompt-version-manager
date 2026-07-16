import AppKit
import Foundation
import PromptVersionCore

enum PresentedSheet: Identifiable {
    case create
    case newVersion
    case metadata
    case tags

    var id: Int {
        switch self {
        case .create: 0
        case .newVersion: 1
        case .metadata: 2
        case .tags: 3
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var prompts: [Prompt] = []
    @Published var selectedPromptID: String? {
        didSet {
            if selectedPromptID != oldValue {
                loadSelection()
            }
        }
    }
    @Published var selectedPrompt: Prompt?
    @Published var history: [PromptVersion] = []
    @Published var displayedVersion: PromptVersion?
    @Published var searchText = ""
    @Published var tagFilter: String?
    @Published var tags: [TagUsage] = []
    @Published var diffFrom: Int?
    @Published var diffTo: Int?
    @Published var errorMessage: String?
    @Published var status = "就绪"
    @Published var presentedSheet: PresentedSheet?

    let repository: PromptRepository?
    let databaseURL: URL

    init() {
        databaseURL = Self.databaseURLFromArguments()
        do {
            repository = try PromptRepository(databaseURL: databaseURL)
            refresh()
        } catch {
            repository = nil
            errorMessage = error.localizedDescription
            status = "数据库打开失败"
        }
    }

    var diffText: String {
        guard let from = diffFrom,
              let to = diffTo,
              let old = history.first(where: { $0.number == from }),
              let new = history.first(where: { $0.number == to }) else {
            return history.count < 2 ? "创建第二个版本后即可比较差异。" : ""
        }
        if old.content == new.content {
            return "v\(from) 与 v\(to) 内容相同。"
        }
        return Diffing.unified(old: old, new: new)
    }

    func refresh(selecting promptID: String? = nil) {
        guard let repository else { return }
        do {
            tags = try repository.listTags()
            let requestedID = promptID ?? selectedPromptID
            prompts = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? try repository.listPrompts(tag: tagFilter)
                : try repository.search(searchText, tag: tagFilter)

            if let requestedID, prompts.contains(where: { $0.id == requestedID }) {
                selectedPromptID = requestedID
                loadSelection()
            } else {
                selectedPromptID = prompts.first?.id
                if prompts.isEmpty {
                    clearSelection()
                }
            }
            status = "显示 \(prompts.count) 个 Prompt"
        } catch {
            report(error)
        }
    }

    func loadSelection() {
        guard let repository, let selectedPromptID else {
            clearSelection()
            return
        }
        do {
            selectedPrompt = try repository.getPrompt(selectedPromptID)
            history = try repository.history(promptID: selectedPromptID)
            displayedVersion = history.first
            if history.count >= 2 {
                diffFrom = history[1].number
                diffTo = history[0].number
            } else {
                diffFrom = history.first?.number
                diffTo = history.first?.number
            }
        } catch {
            report(error)
            clearSelection()
        }
    }

    func showVersion(_ version: PromptVersion) {
        displayedVersion = version
    }

    func create(_ draft: PromptDraft) {
        guard let repository else { return }
        do {
            let prompt = try repository.createPrompt(draft)
            searchText = ""
            tagFilter = nil
            refresh(selecting: prompt.id)
            status = "已创建“\(prompt.title)” v1"
            presentedSheet = nil
        } catch {
            report(error)
        }
    }

    func addVersion(_ draft: PromptDraft) {
        guard let repository, let selectedPrompt else { return }
        do {
            let version = try repository.addVersion(
                promptID: selectedPrompt.id,
                content: draft.content,
                model: draft.model,
                rating: draft.rating,
                note: draft.note
            )
            refresh(selecting: selectedPrompt.id)
            status = "已保存 v\(version.number)"
            presentedSheet = nil
        } catch {
            report(error)
        }
    }

    func editMetadata(title: String, description: String) {
        guard let repository, let selectedPrompt else { return }
        do {
            let updated = try repository.editPrompt(
                promptID: selectedPrompt.id,
                title: title,
                description: description
            )
            refresh(selecting: updated.id)
            status = "Prompt 信息已更新"
            presentedSheet = nil
        } catch {
            report(error)
        }
    }

    func updateTags(_ tags: [String]) {
        guard let repository, let selectedPrompt else { return }
        do {
            let updated = try repository.setTags(promptID: selectedPrompt.id, tags: tags)
            refresh(selecting: updated.id)
            status = "标签已更新"
            presentedSheet = nil
        } catch {
            report(error)
        }
    }

    func importFile() {
        guard let repository else { return }
        let panel = NSOpenPanel()
        panel.title = "导入 Prompt"
        panel.allowedContentTypes = [.json, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let prompt = try repository.importPayload(Interchange.read(from: url))
            searchText = ""
            tagFilter = nil
            refresh(selecting: prompt.id)
            status = "已导入“\(prompt.title)”"
        } catch {
            report(error)
        }
    }

    func exportFile(markdown: Bool) {
        guard let repository, let selectedPrompt else { return }
        let panel = NSSavePanel()
        panel.title = "导出 Prompt"
        panel.nameFieldStringValue = "\(selectedPrompt.title).\(markdown ? "md" : "json")"
        panel.allowedContentTypes = markdown ? [.plainText] : [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let payload = try Interchange.payload(repository: repository, promptID: selectedPrompt.id)
            try Interchange.write(payload, to: url, markdown: markdown)
            status = "已导出到 \(url.path)"
        } catch {
            report(error)
        }
    }

    private func clearSelection() {
        selectedPrompt = nil
        history = []
        displayedVersion = nil
        diffFrom = nil
        diffTo = nil
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        status = error.localizedDescription
    }

    private static func databaseURLFromArguments() -> URL {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--db"), arguments.indices.contains(index + 1) {
            let path = NSString(string: arguments[index + 1]).expandingTildeInPath
            return URL(fileURLWithPath: path)
        }
        return PromptRepository.defaultDatabaseURL()
    }
}
