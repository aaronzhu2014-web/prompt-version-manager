import Foundation
import SQLite3

let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteValue {
    case integer(Int64)
    case text(String)
    case null
}

final class SQLiteStatement {
    private let database: OpaquePointer
    private var statement: OpaquePointer?

    init(database: OpaquePointer, sql: String) throws {
        self.database = database
        if sqlite3_prepare_v2(database, sql, -1, &statement, nil) != SQLITE_OK {
            throw PromptVMError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ values: [SQLiteValue]) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .integer(let number):
                result = sqlite3_bind_int64(statement, index, number)
            case .text(let text):
                result = sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            if result != SQLITE_OK {
                throw PromptVMError.database(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    func step() throws -> Int32 {
        let result = sqlite3_step(statement)
        if result != SQLITE_ROW && result != SQLITE_DONE {
            throw PromptVMError.database(String(cString: sqlite3_errmsg(database)))
        }
        return result
    }

    func text(_ column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }

    func optionalText(_ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return text(column)
    }

    func int(_ column: Int32) -> Int {
        Int(sqlite3_column_int64(statement, column))
    }

    func int64(_ column: Int32) -> Int64 {
        sqlite3_column_int64(statement, column)
    }

    func optionalInt(_ column: Int32) -> Int? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return int(column)
    }
}

func execute(_ database: OpaquePointer, _ sql: String, _ values: [SQLiteValue] = []) throws {
    let statement = try SQLiteStatement(database: database, sql: sql)
    try statement.bind(values)
    guard try statement.step() == SQLITE_DONE else {
        throw PromptVMError.database("SQLite write did not finish.")
    }
}
