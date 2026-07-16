import Foundation
import PromptVersionCore

@main
struct PromptVersionCoreChecks {
    static func main() throws {
        let checks: [(String, () throws -> Void)] = [
            ("create/update/history/search", createUpdateHistoryAndSearch),
            ("Unicode tag identity", unicodeTagsUseOneIdentity),
            ("concurrent version writes", concurrentVersionWritesAreSerialized),
            ("JSON/Markdown round-trip", jsonAndMarkdownRoundTrip),
            ("Python export compatibility", readsPythonExportFixture),
            ("diff output", diffContainsAdditionsAndRemovals),
        ]

        for (name, check) in checks {
            do {
                try check()
                print("PASS  \(name)")
            } catch {
                fputs("FAIL  \(name): \(error.localizedDescription)\n", stderr)
                Foundation.exit(1)
            }
        }
        print("All \(checks.count) Swift core checks passed.")
    }

    private static func createUpdateHistoryAndSearch() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let repository = context.repository
        let prompt = try repository.createPrompt(
            PromptDraft(
                title: "技术解释器",
                description: "测试描述",
                tags: ["Writing", "中文", "writing"],
                content: "解释 joins",
                model: "example-model",
                rating: 3,
                note: "初始版本"
            )
        )
        try require(prompt.tags == ["Writing", "中文"], "标签未去重")
        try require(prompt.latestVersion.number == 1, "初始版本不是 v1")

        let second = try repository.addVersion(
            promptID: prompt.id,
            content: "解释事务并提供示例",
            rating: 5,
            note: "改进"
        )
        try require(second.number == 2, "新版本不是 v2")
        try require(
            try repository.history(promptID: prompt.id).map(\.number) == [2, 1],
            "历史顺序错误"
        )
        try require(try repository.search("joins").first?.id == prompt.id, "未搜索到旧正文")
        try require(
            try repository.search("事务", tag: "WRITING").first?.id == prompt.id,
            "标签过滤搜索失败"
        )
    }

    private static func unicodeTagsUseOneIdentity() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let repository = context.repository
        let prompt = try repository.createPrompt(
            PromptDraft(title: "Unicode", tags: ["Straße"], content: "content")
        )
        _ = try repository.setTags(promptID: prompt.id, tags: ["Straße", "STRASSE"])

        try require(try repository.getPrompt(prompt.id).tags == ["Straße"], "Unicode 标签重复")
        try require(
            try repository.listPrompts(tag: "strasse").map(\.id) == [prompt.id],
            "Unicode 标签过滤失败"
        )
    }

    private static func concurrentVersionWritesAreSerialized() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let repository = context.repository
        let prompt = try repository.createPrompt(PromptDraft(title: "并发", content: "v1"))
        let queue = DispatchQueue(label: "pvm.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        let results = LockedResults()

        for index in 0..<8 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    let worker = try PromptRepository(databaseURL: repository.databaseURL)
                    let version = try worker.addVersion(
                        promptID: prompt.id,
                        content: "worker \(index)"
                    )
                    results.append(number: version.number)
                } catch {
                    results.append(error: error)
                }
            }
        }
        group.wait()

        try require(results.errors.isEmpty, "并发写入失败：\(results.errors)")
        try require(results.numbers.sorted() == Array(2...9), "并发版本号不连续")
    }

    private static func jsonAndMarkdownRoundTrip() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let repository = context.repository
        let prompt = try repository.createPrompt(
            PromptDraft(
                title: "往返 中文",
                description: "描述",
                tags: ["i18n"],
                content: "正文\n```edge```",
                rating: 4
            )
        )
        _ = try repository.addVersion(promptID: prompt.id, content: "第二版", rating: 5)
        let payload = try Interchange.payload(repository: repository, promptID: prompt.id)
        let jsonPayload = try Interchange.parse(Interchange.json(payload))
        let markdown = try Interchange.markdown(payload)
        let markdownPayload = try Interchange.parse(markdown)

        try require(jsonPayload == payload, "JSON 往返不一致")
        try require(markdownPayload == payload, "Markdown 往返不一致")
        try require(markdown.contains("PVM-DATA-V1"), "Markdown 缺少元数据")
        try require(markdown.contains("## v2"), "Markdown 缺少版本")
    }

    private static func readsPythonExportFixture() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let fixture = """
        {
          "format": "prompt-version-manager",
          "format_version": 1,
          "prompt": {
            "id": "python-source",
            "title": "Python 兼容",
            "description": "旧格式",
            "tags": ["legacy"],
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-02T00:00:00Z"
          },
          "versions": [
            {
              "version_number": 1,
              "content": "第一版",
              "model": null,
              "rating": 3,
              "note": "",
              "created_at": "2026-01-01T00:00:00Z"
            },
            {
              "version_number": 2,
              "content": "第二版",
              "model": "example",
              "rating": 5,
              "note": "更新",
              "created_at": "2026-01-02T00:00:00Z"
            }
          ]
        }
        """
        let imported = try context.repository.importPayload(Interchange.parse(fixture))
        try require(imported.id != "python-source", "导入复用了源 ID")
        try require(imported.title == "Python 兼容", "导入标题错误")
        try require(imported.latestVersion.content == "第二版", "导入最新版错误")
        try require(
            try context.repository.history(promptID: imported.id).count == 2,
            "导入版本数量错误"
        )
    }

    private static func diffContainsAdditionsAndRemovals() throws {
        let old = PromptVersion(
            id: 1,
            promptID: "id",
            number: 1,
            content: "tone: formal\nshort",
            model: nil,
            rating: nil,
            note: "",
            createdAt: "date"
        )
        let new = PromptVersion(
            id: 2,
            promptID: "id",
            number: 2,
            content: "tone: warm\nshort\nexamples",
            model: nil,
            rating: nil,
            note: "",
            createdAt: "date"
        )
        let output = Diffing.unified(old: old, new: new)
        try require(output.contains("--- v1"), "Diff 缺少旧版本头")
        try require(output.contains("+++ v2"), "Diff 缺少新版本头")
        try require(output.contains("-tone: formal"), "Diff 缺少删除行")
        try require(output.contains("+tone: warm"), "Diff 缺少添加行")
        try require(output.contains("+examples"), "Diff 缺少新增行")
    }

    private static func require(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String
    ) throws {
        if try !condition() {
            throw CheckError(message: message)
        }
    }
}

private struct CheckError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class TestContext {
    let directory: URL
    let repository: PromptRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvm-swift-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = try PromptRepository(databaseURL: directory.appendingPathComponent("test.db"))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class LockedResults {
    private let lock = NSLock()
    private var storedNumbers: [Int] = []
    private var storedErrors: [Error] = []

    var numbers: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return storedNumbers
    }

    var errors: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return storedErrors
    }

    func append(number: Int) {
        lock.lock()
        storedNumbers.append(number)
        lock.unlock()
    }

    func append(error: Error) {
        lock.lock()
        storedErrors.append(error)
        lock.unlock()
    }
}
