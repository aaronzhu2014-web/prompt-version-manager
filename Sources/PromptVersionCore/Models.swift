import Foundation

public struct PromptVersion: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let promptID: String
    public let number: Int
    public let content: String
    public let model: String?
    public let rating: Int?
    public let note: String
    public let createdAt: String

    public init(
        id: Int64,
        promptID: String,
        number: Int,
        content: String,
        model: String?,
        rating: Int?,
        note: String,
        createdAt: String
    ) {
        self.id = id
        self.promptID = promptID
        self.number = number
        self.content = content
        self.model = model
        self.rating = rating
        self.note = note
        self.createdAt = createdAt
    }
}

public struct Prompt: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let tags: [String]
    public let createdAt: String
    public let updatedAt: String
    public let latestVersion: PromptVersion

    public init(
        id: String,
        title: String,
        description: String,
        tags: [String],
        createdAt: String,
        updatedAt: String,
        latestVersion: PromptVersion
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.latestVersion = latestVersion
    }
}

public struct TagUsage: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct PromptDraft: Equatable, Sendable {
    public var title = ""
    public var description = ""
    public var tags: [String] = []
    public var content = ""
    public var model: String?
    public var rating: Int?
    public var note = ""

    public init(
        title: String = "",
        description: String = "",
        tags: [String] = [],
        content: String = "",
        model: String? = nil,
        rating: Int? = nil,
        note: String = ""
    ) {
        self.title = title
        self.description = description
        self.tags = tags
        self.content = content
        self.model = model
        self.rating = rating
        self.note = note
    }
}

public enum PromptVMError: LocalizedError, Equatable {
    case validation(String)
    case notFound(String)
    case database(String)
    case importFormat(String)
    case file(String)

    public var errorDescription: String? {
        switch self {
        case .validation(let message),
             .notFound(let message),
             .database(let message),
             .importFormat(let message),
             .file(let message):
            return message
        }
    }
}
