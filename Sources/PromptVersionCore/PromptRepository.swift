import Foundation
import SQLite3

public final class PromptRepository {
    public let databaseURL: URL

    private static let schema = """
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS prompts (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL CHECK(length(trim(title)) > 0),
        description TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS versions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        prompt_id TEXT NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
        version_number INTEGER NOT NULL CHECK(version_number > 0),
        content TEXT NOT NULL,
        model TEXT,
        rating INTEGER CHECK(rating IS NULL OR rating BETWEEN 1 AND 5),
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        UNIQUE(prompt_id, version_number)
    );
    CREATE TABLE IF NOT EXISTS tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name)) > 0)
    );
    CREATE TABLE IF NOT EXISTS prompt_tags (
        prompt_id TEXT NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
        tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
        PRIMARY KEY(prompt_id, tag_id)
    );
    CREATE INDEX IF NOT EXISTS idx_versions_prompt
        ON versions(prompt_id, version_number DESC);
    CREATE INDEX IF NOT EXISTS idx_prompt_tags_tag
        ON prompt_tags(tag_id, prompt_id);
    """

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL.standardizedFileURL
        try FileManager.default.createDirectory(
            at: self.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try withConnection { database in
            try executeScript(database, Self.schema)
            try executeScript(database, "PRAGMA journal_mode = WAL;")
        }
        try withConnection(write: true) { database in
            try mergeUnicodeDuplicateTags(database)
        }
    }

    public static func defaultDatabaseURL() -> URL {
        if let custom = ProcessInfo.processInfo.environment["PROMPTVM_DB"], !custom.isEmpty {
            return URL(fileURLWithPath: NSString(string: custom).expandingTildeInPath)
        }
        let environment = ProcessInfo.processInfo.environment
        let root: URL
        if let xdg = environment["XDG_DATA_HOME"], !xdg.isEmpty {
            root = URL(fileURLWithPath: NSString(string: xdg).expandingTildeInPath)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share")
        }
        return root.appendingPathComponent("promptvm/promptvm.db")
    }

    public func createPrompt(_ draft: PromptDraft) throws -> Prompt {
        let title = try validatedTitle(draft.title)
        try validateRating(draft.rating)
        let tags = try normalizedTags(draft.tags)
        let promptID = UUID().uuidString.lowercased()
        let timestamp = utcNow()
        try withConnection(write: true) { database in
            try execute(
                database,
                """
                INSERT INTO prompts(id, title, description, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                [.text(promptID), .text(title), .text(draft.description), .text(timestamp), .text(timestamp)]
            )
            try execute(
                database,
                """
                INSERT INTO versions(
                    prompt_id, version_number, content, model, rating, note, created_at
                ) VALUES (?, 1, ?, ?, ?, ?, ?)
                """,
                [
                    .text(promptID),
                    .text(draft.content),
                    draft.model.flatMap { $0.isEmpty ? nil : $0 }.map(SQLiteValue.text) ?? .null,
                    draft.rating.map { .integer(Int64($0)) } ?? .null,
                    .text(draft.note),
                    .text(timestamp),
                ]
            )
            try attachTags(database, promptID: promptID, tags: tags)
        }
        return try getPrompt(promptID)
    }

    @discardableResult
    public func addVersion(
        promptID: String,
        content: String,
        model: String? = nil,
        rating: Int? = nil,
        note: String = ""
    ) throws -> PromptVersion {
        try validateRating(rating)
        let timestamp = utcNow()
        return try withConnection(write: true) { database in
            try ensurePrompt(database, promptID: promptID)
            let next = try scalarInt(
                database,
                "SELECT COALESCE(MAX(version_number), 0) + 1 FROM versions WHERE prompt_id = ?",
                [.text(promptID)]
            )
            try execute(
                database,
                """
                INSERT INTO versions(
                    prompt_id, version_number, content, model, rating, note, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(promptID),
                    .integer(Int64(next)),
                    .text(content),
                    model.flatMap { $0.isEmpty ? nil : $0 }.map(SQLiteValue.text) ?? .null,
                    rating.map { .integer(Int64($0)) } ?? .null,
                    .text(note),
                    .text(timestamp),
                ]
            )
            try execute(
                database,
                "UPDATE prompts SET updated_at = ? WHERE id = ?",
                [.text(timestamp), .text(promptID)]
            )
            return try version(
                database,
                sql: """
                SELECT id, prompt_id, version_number, content, model, rating, note, created_at
                FROM versions WHERE prompt_id = ? AND version_number = ?
                """,
                values: [.text(promptID), .integer(Int64(next))]
            )
        }
    }

    public func editPrompt(promptID: String, title: String, description: String) throws -> Prompt {
        let cleanTitle = try validatedTitle(title)
        try withConnection(write: true) { database in
            try ensurePrompt(database, promptID: promptID)
            try execute(
                database,
                "UPDATE prompts SET title = ?, description = ?, updated_at = ? WHERE id = ?",
                [.text(cleanTitle), .text(description), .text(utcNow()), .text(promptID)]
            )
        }
        return try getPrompt(promptID)
    }

    public func setTags(promptID: String, tags: [String]) throws -> Prompt {
        let cleanTags = try normalizedTags(tags)
        try withConnection(write: true) { database in
            try ensurePrompt(database, promptID: promptID)
            try execute(database, "DELETE FROM prompt_tags WHERE prompt_id = ?", [.text(promptID)])
            try attachTags(database, promptID: promptID, tags: cleanTags)
            try execute(
                database,
                "DELETE FROM tags WHERE NOT EXISTS (SELECT 1 FROM prompt_tags WHERE tag_id = tags.id)"
            )
            try execute(
                database,
                "UPDATE prompts SET updated_at = ? WHERE id = ?",
                [.text(utcNow()), .text(promptID)]
            )
        }
        return try getPrompt(promptID)
    }

    public func getPrompt(_ promptID: String) throws -> Prompt {
        try withConnection { database in
            try prompt(
                database,
                sql: """
                SELECT id, title, description, created_at, updated_at
                FROM prompts WHERE id = ?
                """,
                values: [.text(promptID)]
            )
        }
    }

    public func listPrompts(tag: String? = nil) throws -> [Prompt] {
        let prompts = try withConnection { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT id, title, description, created_at, updated_at
                FROM prompts
                ORDER BY updated_at DESC, title COLLATE NOCASE
                """
            )
            var result: [Prompt] = []
            while try statement.step() == SQLITE_ROW {
                result.append(try promptFromStatement(database, statement: statement))
            }
            return result
        }
        guard let tag, !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return prompts
        }
        let key = normalizedTagKey(tag)
        return prompts.filter { prompt in
            prompt.tags.contains { normalizedTagKey($0) == key }
        }
    }

    public func search(_ query: String, tag: String? = nil) throws -> [Prompt] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw PromptVMError.validation("搜索内容不能为空。")
        }
        return try listPrompts(tag: tag).filter { prompt in
            if prompt.title.localizedCaseInsensitiveContains(clean)
                || prompt.description.localizedCaseInsensitiveContains(clean)
                || prompt.tags.contains(where: {
                    normalizedTagKey($0).contains(normalizedTagKey(clean))
                }) {
                return true
            }
            return try history(promptID: prompt.id).contains {
                $0.content.localizedCaseInsensitiveContains(clean)
            }
        }
    }

    public func history(promptID: String) throws -> [PromptVersion] {
        try withConnection { database in
            try ensurePrompt(database, promptID: promptID)
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT id, prompt_id, version_number, content, model, rating, note, created_at
                FROM versions WHERE prompt_id = ? ORDER BY version_number DESC
                """
            )
            try statement.bind([.text(promptID)])
            var versions: [PromptVersion] = []
            while try statement.step() == SQLITE_ROW {
                versions.append(versionFromStatement(statement))
            }
            return versions
        }
    }

    public func getVersion(promptID: String, number: Int? = nil) throws -> PromptVersion {
        try withConnection { database in
            try ensurePrompt(database, promptID: promptID)
            if let number {
                return try version(
                    database,
                    sql: """
                    SELECT id, prompt_id, version_number, content, model, rating, note, created_at
                    FROM versions WHERE prompt_id = ? AND version_number = ?
                    """,
                    values: [.text(promptID), .integer(Int64(number))]
                )
            }
            return try version(
                database,
                sql: """
                SELECT id, prompt_id, version_number, content, model, rating, note, created_at
                FROM versions WHERE prompt_id = ? ORDER BY version_number DESC LIMIT 1
                """,
                values: [.text(promptID)]
            )
        }
    }

    public func listTags() throws -> [TagUsage] {
        try withConnection { database in
            let statement = try SQLiteStatement(
                database: database,
                sql: """
                SELECT t.name, COUNT(pt.prompt_id)
                FROM tags t
                JOIN prompt_tags pt ON pt.tag_id = t.id
                GROUP BY t.id
                ORDER BY t.name COLLATE NOCASE
                """
            )
            var result: [TagUsage] = []
            while try statement.step() == SQLITE_ROW {
                result.append(TagUsage(name: statement.text(0), count: statement.int(1)))
            }
            return result
        }
    }

    public func importPayload(_ payload: ExportPayload) throws -> Prompt {
        try payload.validate()
        let promptID = UUID().uuidString.lowercased()
        try withConnection(write: true) { database in
            try execute(
                database,
                """
                INSERT INTO prompts(id, title, description, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                [
                    .text(promptID),
                    .text(payload.prompt.title.trimmingCharacters(in: .whitespacesAndNewlines)),
                    .text(payload.prompt.description),
                    .text(payload.prompt.createdAt),
                    .text(payload.prompt.updatedAt),
                ]
            )
            for version in payload.versions {
                try execute(
                    database,
                    """
                    INSERT INTO versions(
                        prompt_id, version_number, content, model, rating, note, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(promptID),
                        .integer(Int64(version.versionNumber)),
                        .text(version.content),
                        version.model.map(SQLiteValue.text) ?? .null,
                        version.rating.map { .integer(Int64($0)) } ?? .null,
                        .text(version.note),
                        .text(version.createdAt),
                    ]
                )
            }
            try attachTags(database, promptID: promptID, tags: payload.prompt.tags)
        }
        return try getPrompt(promptID)
    }

    private func withConnection<T>(
        write: Bool = false,
        _ operation: (OpaquePointer) throws -> T
    ) throws -> T {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "无法打开数据库。"
            if let database { sqlite3_close(database) }
            throw PromptVMError.database("数据库操作失败：\(message)")
        }
        defer { sqlite3_close(database) }
        do {
            try executeScript(database, "PRAGMA foreign_keys = ON;")
            sqlite3_busy_timeout(database, 10_000)
            if write {
                try execute(database, "BEGIN IMMEDIATE")
            }
            let result = try operation(database)
            if write {
                try execute(database, "COMMIT")
            }
            return result
        } catch {
            if write {
                try? execute(database, "ROLLBACK")
            }
            if let known = error as? PromptVMError {
                throw known
            }
            throw PromptVMError.database("数据库操作失败：\(error.localizedDescription)")
        }
    }

    private func executeScript(_ database: OpaquePointer, _ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorPointer)
            throw PromptVMError.database(message)
        }
    }

    private func prompt(
        _ database: OpaquePointer,
        sql: String,
        values: [SQLiteValue]
    ) throws -> Prompt {
        let statement = try SQLiteStatement(database: database, sql: sql)
        try statement.bind(values)
        guard try statement.step() == SQLITE_ROW else {
            throw PromptVMError.notFound("未找到 Prompt。")
        }
        return try promptFromStatement(database, statement: statement)
    }

    private func promptFromStatement(
        _ database: OpaquePointer,
        statement: SQLiteStatement
    ) throws -> Prompt {
        let promptID = statement.text(0)
        return Prompt(
            id: promptID,
            title: statement.text(1),
            description: statement.text(2),
            tags: try tagsForPrompt(database, promptID: promptID),
            createdAt: statement.text(3),
            updatedAt: statement.text(4),
            latestVersion: try version(
                database,
                sql: """
                SELECT id, prompt_id, version_number, content, model, rating, note, created_at
                FROM versions WHERE prompt_id = ? ORDER BY version_number DESC LIMIT 1
                """,
                values: [.text(promptID)]
            )
        )
    }

    private func version(
        _ database: OpaquePointer,
        sql: String,
        values: [SQLiteValue]
    ) throws -> PromptVersion {
        let statement = try SQLiteStatement(database: database, sql: sql)
        try statement.bind(values)
        guard try statement.step() == SQLITE_ROW else {
            throw PromptVMError.notFound("未找到版本。")
        }
        return versionFromStatement(statement)
    }

    private func versionFromStatement(_ statement: SQLiteStatement) -> PromptVersion {
        PromptVersion(
            id: statement.int64(0),
            promptID: statement.text(1),
            number: statement.int(2),
            content: statement.text(3),
            model: statement.optionalText(4),
            rating: statement.optionalInt(5),
            note: statement.text(6),
            createdAt: statement.text(7)
        )
    }

    private func ensurePrompt(_ database: OpaquePointer, promptID: String) throws {
        let count = try scalarInt(
            database,
            "SELECT COUNT(*) FROM prompts WHERE id = ?",
            [.text(promptID)]
        )
        guard count == 1 else {
            throw PromptVMError.notFound("未找到 Prompt：\(promptID)")
        }
    }

    private func scalarInt(
        _ database: OpaquePointer,
        _ sql: String,
        _ values: [SQLiteValue] = []
    ) throws -> Int {
        let statement = try SQLiteStatement(database: database, sql: sql)
        try statement.bind(values)
        guard try statement.step() == SQLITE_ROW else {
            throw PromptVMError.database("查询没有返回结果。")
        }
        return statement.int(0)
    }

    private func tagsForPrompt(_ database: OpaquePointer, promptID: String) throws -> [String] {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            SELECT t.name
            FROM tags t
            JOIN prompt_tags pt ON pt.tag_id = t.id
            WHERE pt.prompt_id = ?
            ORDER BY t.name COLLATE NOCASE
            """
        )
        try statement.bind([.text(promptID)])
        var tags: [String] = []
        var seen = Set<String>()
        while try statement.step() == SQLITE_ROW {
            let name = statement.text(0)
            if seen.insert(normalizedTagKey(name)).inserted {
                tags.append(name)
            }
        }
        return tags
    }

    private func attachTags(
        _ database: OpaquePointer,
        promptID: String,
        tags: [String]
    ) throws {
        for name in try normalizedTags(tags) {
            let existing = try allTags(database).first {
                normalizedTagKey($0.name) == normalizedTagKey(name)
            }
            let tagID: Int
            if let existing {
                tagID = existing.id
            } else {
                try execute(database, "INSERT OR IGNORE INTO tags(name) VALUES (?)", [.text(name)])
                guard let inserted = try allTags(database).first(where: {
                    normalizedTagKey($0.name) == normalizedTagKey(name)
                }) else {
                    throw PromptVMError.database("无法创建标签：\(name)")
                }
                tagID = inserted.id
            }
            try execute(
                database,
                "INSERT OR IGNORE INTO prompt_tags(prompt_id, tag_id) VALUES (?, ?)",
                [.text(promptID), .integer(Int64(tagID))]
            )
        }
    }

    private func allTags(_ database: OpaquePointer) throws -> [(id: Int, name: String)] {
        let statement = try SQLiteStatement(
            database: database,
            sql: "SELECT id, name FROM tags ORDER BY id"
        )
        var tags: [(Int, String)] = []
        while try statement.step() == SQLITE_ROW {
            tags.append((statement.int(0), statement.text(1)))
        }
        return tags
    }

    private func mergeUnicodeDuplicateTags(_ database: OpaquePointer) throws {
        var canonical: [String: Int] = [:]
        for tag in try allTags(database) {
            let key = normalizedTagKey(tag.name)
            if let kept = canonical[key] {
                try execute(
                    database,
                    """
                    INSERT OR IGNORE INTO prompt_tags(prompt_id, tag_id)
                    SELECT prompt_id, ? FROM prompt_tags WHERE tag_id = ?
                    """,
                    [.integer(Int64(kept)), .integer(Int64(tag.id))]
                )
                try execute(database, "DELETE FROM prompt_tags WHERE tag_id = ?", [.integer(Int64(tag.id))])
                try execute(database, "DELETE FROM tags WHERE id = ?", [.integer(Int64(tag.id))])
            } else {
                canonical[key] = tag.id
            }
        }
    }

    private func validatedTitle(_ title: String) throws -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw PromptVMError.validation("标题不能为空。")
        }
        return clean
    }

    private func validateRating(_ rating: Int?) throws {
        if let rating, !(1...5).contains(rating) {
            throw PromptVMError.validation("评分必须是 1–5，或留空。")
        }
    }

    private func normalizedTags(_ tags: [String]) throws -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for tag in tags {
            let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else {
                throw PromptVMError.validation("标签不能为空。")
            }
            if seen.insert(normalizedTagKey(clean)).inserted {
                result.append(clean)
            }
        }
        return result
    }

    private func normalizedTagKey(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func utcNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
