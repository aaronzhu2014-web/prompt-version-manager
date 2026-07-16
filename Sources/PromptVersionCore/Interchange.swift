import Foundation

public struct ExportPayload: Codable, Equatable, Sendable {
    public let format: String
    public let formatVersion: Int
    public let prompt: ExportPrompt
    public let versions: [ExportVersion]

    enum CodingKeys: String, CodingKey {
        case format
        case formatVersion = "format_version"
        case prompt
        case versions
    }

    public init(prompt: Prompt, versions: [PromptVersion]) {
        format = "prompt-version-manager"
        formatVersion = 1
        self.prompt = ExportPrompt(prompt)
        self.versions = versions.sorted { $0.number < $1.number }.map(ExportVersion.init)
    }

    public func validate() throws {
        guard format == "prompt-version-manager", formatVersion == 1 else {
            throw PromptVMError.importFormat("不支持的导入格式或版本。")
        }
        guard !prompt.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PromptVMError.importFormat("导入内容缺少标题。")
        }
        guard !versions.isEmpty else {
            throw PromptVMError.importFormat("导入内容至少需要一个版本。")
        }
        for (index, version) in versions.enumerated() {
            guard version.versionNumber == index + 1 else {
                throw PromptVMError.importFormat("导入版本必须从 1 开始连续编号。")
            }
            if let rating = version.rating, !(1...5).contains(rating) {
                throw PromptVMError.importFormat("导入版本评分必须是 1–5。")
            }
        }
    }
}

public struct ExportPrompt: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let tags: [String]
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, description, tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(_ prompt: Prompt) {
        id = prompt.id
        title = prompt.title
        description = prompt.description
        tags = prompt.tags
        createdAt = prompt.createdAt
        updatedAt = prompt.updatedAt
    }
}

public struct ExportVersion: Codable, Equatable, Sendable {
    public let versionNumber: Int
    public let content: String
    public let model: String?
    public let rating: Int?
    public let note: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case versionNumber = "version_number"
        case content, model, rating, note
        case createdAt = "created_at"
    }

    init(_ version: PromptVersion) {
        versionNumber = version.number
        content = version.content
        model = version.model
        rating = version.rating
        note = version.note
        createdAt = version.createdAt
    }
}

public enum Interchange {
    public static func payload(repository: PromptRepository, promptID: String) throws -> ExportPayload {
        ExportPayload(
            prompt: try repository.getPrompt(promptID),
            versions: try repository.history(promptID: promptID)
        )
    }

    public static func json(_ payload: ExportPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(payload), as: UTF8.self) + "\n"
    }

    public static func markdown(_ payload: ExportPayload) throws -> String {
        let data = try JSONEncoder().encode(payload)
        let marker = urlSafeBase64(data)
        let tags = payload.prompt.tags.isEmpty
            ? "—"
            : payload.prompt.tags.map { "`\($0)`" }.joined(separator: ", ")
        var lines = [
            "<!-- PVM-DATA-V1:\(marker) -->",
            "",
            "# \(payload.prompt.title)",
            "",
            payload.prompt.description.isEmpty ? "_No description._" : payload.prompt.description,
            "",
            "- Tags: \(tags)",
            "- Created: \(payload.prompt.createdAt)",
            "- Updated: \(payload.prompt.updatedAt)",
            "",
        ]
        for version in payload.versions.reversed() {
            var metadata: [String] = []
            if let model = version.model { metadata.append("Model: \(model)") }
            if let rating = version.rating { metadata.append("Rating: \(rating)/5") }
            metadata.append("Created: \(version.createdAt)")
            lines += ["## v\(version.versionNumber)", "", metadata.joined(separator: " · "), ""]
            if !version.note.isEmpty {
                lines += ["> Note: \(version.note)", ""]
            }
            let fence = markdownFence(for: version.content)
            lines += ["\(fence)text", version.content, fence, ""]
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    public static func parse(_ text: String) throws -> ExportPayload {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let data: Data
        if trimmed.hasPrefix("{") {
            guard let jsonData = trimmed.data(using: .utf8) else {
                throw PromptVMError.importFormat("导入文件不是有效的 UTF-8。")
            }
            data = jsonData
        } else {
            let pattern = #"<!-- PVM-DATA-V1:([A-Za-z0-9_=-]+) -->"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..., in: text)
                  ),
                  let range = Range(match.range(at: 1), in: text),
                  let decoded = decodeURLSafeBase64(String(text[range])) else {
                throw PromptVMError.importFormat("Markdown 缺少有效的 PVM-DATA-V1 元数据。")
            }
            data = decoded
        }
        do {
            let payload = try JSONDecoder().decode(ExportPayload.self, from: data)
            try payload.validate()
            return payload
        } catch let error as PromptVMError {
            throw error
        } catch {
            throw PromptVMError.importFormat("导入文件包含无效字段：\(error.localizedDescription)")
        }
    }

    public static func read(from url: URL) throws -> ExportPayload {
        do {
            return try parse(String(contentsOf: url, encoding: .utf8))
        } catch let error as PromptVMError {
            throw error
        } catch {
            throw PromptVMError.file("无法读取文件：\(error.localizedDescription)")
        }
    }

    public static func write(
        _ payload: ExportPayload,
        to url: URL,
        markdown: Bool
    ) throws {
        let rendered = try markdown ? self.markdown(payload) : json(payload)
        do {
            try rendered.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw PromptVMError.file("无法保存文件：\(error.localizedDescription)")
        }
    }

    private static func markdownFence(for content: String) -> String {
        var longest = 0
        var current = 0
        for character in content {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return String(repeating: "`", count: max(3, longest + 1))
    }

    private static func urlSafeBase64(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    private static func decodeURLSafeBase64(_ value: String) -> Data? {
        var standard = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder != 0 {
            standard += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: standard)
    }
}
