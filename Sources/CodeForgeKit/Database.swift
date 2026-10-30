import Foundation
import SQLite3

/// A Server Explorer data connection. SQLite files are opened directly; PostgreSQL, MySQL and SQL Server are reached
/// through their command-line clients (psql, mysql, sqlcmd), which the user installs.
public struct DataConnection: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case sqlite, postgres, mysql, sqlserver

        public var title: String {
            switch self {
            case .sqlite: "SQLite database file"
            case .postgres: "PostgreSQL"
            case .mysql: "MySQL / MariaDB"
            case .sqlserver: "Microsoft SQL Server"
            }
        }

        /// The command-line client a server connection needs.
        public var client: String? {
            switch self {
            case .sqlite: nil
            case .postgres: "psql"
            case .mysql: "mysql"
            case .sqlserver: "sqlcmd"
            }
        }

        public var installHint: String {
            switch self {
            case .sqlite: ""
            case .postgres: "Install the PostgreSQL client with `brew install libpq` (or `brew install postgresql`)."
            case .mysql: "Install the MySQL client with `brew install mysql-client`."
            case .sqlserver: "Install sqlcmd with `brew install sqlcmd`."
            }
        }
    }

    public var id: String
    public var name: String
    public var kind: Kind
    /// SQLite: the file path. Servers: host (and optional port).
    public var location: String
    public var port: String = ""
    public var database: String = ""
    public var user: String = ""

    public init(id: String = UUID().uuidString, name: String, kind: Kind, location: String, port: String = "", database: String = "", user: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.location = location
        self.port = port
        self.database = database
        self.user = user
    }
}

public struct QueryResult: Sendable, Equatable {
    public var columns: [String] = []
    public var rows: [[String?]] = []
    /// Rows changed by INSERT, UPDATE or DELETE, when there's no result set.
    public var changes: Int = 0
    public var message: String = ""

    public init(columns: [String] = [], rows: [[String?]] = [], changes: Int = 0, message: String = "") {
        self.columns = columns
        self.rows = rows
        self.changes = changes
        self.message = message
    }
}

public struct DatabaseError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Tables, views and their columns, for the Server Explorer tree.
public struct DatabaseTable: Sendable, Equatable {
    public let name: String
    public let isView: Bool
    public var columns: [(name: String, type: String, isKey: Bool)] = []

    public init(name: String, isView: Bool, columns: [(name: String, type: String, isKey: Bool)] = []) {
        self.name = name
        self.isView = isView
        self.columns = columns
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.name == b.name && a.isView == b.isView && a.columns.map { "\($0.name):\($0.type):\($0.isKey)" } == b.columns.map { "\($0.name):\($0.type):\($0.isKey)" }
    }
}

public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    /// Opens a database file; `create` makes a new empty file when it doesn't exist.
    public init(path: String, create: Bool = false) throws {
        let flags = SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0)
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Couldn't open the database."
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError(message)
        }
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit { sqlite3_close(handle) }

    public func tables() throws -> [DatabaseTable] {
        let list = try execute("SELECT name, type FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY type, name")
        return try list.rows.map { row in
            let name = row[0] ?? ""
            var table = DatabaseTable(name: name, isView: row[1] == "view")
            let info = try execute("PRAGMA table_info(\(Self.quote(name)))")
            table.columns = info.rows.map { ($0[1] ?? "", $0[2] ?? "", ($0[5] ?? "0") != "0") }
            return table
        }
    }

    /// Runs one or more statements. The result is the last statement that returned rows, or the change count.
    public func execute(_ sql: String) throws -> QueryResult {
        var result = QueryResult()
        var changes = 0
        var hadRows = false
        try sql.withCString { start in
            var tail: UnsafePointer<CChar>? = start
            while let current = tail, current.pointee != 0 {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(handle, current, -1, &statement, &tail) == SQLITE_OK else {
                    throw DatabaseError(String(cString: sqlite3_errmsg(handle)))
                }
                guard let statement else { continue }   // only whitespace or a comment was left
                defer { sqlite3_finalize(statement) }
                let count = Int(sqlite3_column_count(statement))
                var rows: [[String?]] = []
                while true {
                    let step = sqlite3_step(statement)
                    if step == SQLITE_DONE { break }
                    guard step == SQLITE_ROW else { throw DatabaseError(String(cString: sqlite3_errmsg(handle))) }
                    rows.append((0..<count).map { index in
                        sqlite3_column_type(statement, Int32(index)) == SQLITE_NULL ? nil
                            : sqlite3_column_text(statement, Int32(index)).map { String(cString: $0) }
                    })
                    if rows.count >= 10_000 { break }
                }
                if count > 0 {
                    hadRows = true
                    result.columns = (0..<count).map { String(cString: sqlite3_column_name(statement, Int32($0))) }
                    result.rows = rows
                } else {
                    changes += Int(sqlite3_changes(handle))
                }
            }
        }
        result.changes = changes
        result.message = hadRows ? "\(result.rows.count) row\(result.rows.count == 1 ? "" : "s")" + (result.rows.count >= 10_000 ? " (first 10,000)" : "")
            : "Command completed. \(changes) row\(changes == 1 ? "" : "s") affected."
        return result
    }

    static func quote(_ name: String) -> String { "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}

/// Builds client commands for server databases and reads their output.
public enum DatabaseClient {
    /// The SQL that lists tables and views (name, type) for a server kind.
    public static func tablesQuery(_ kind: DataConnection.Kind) -> String {
        switch kind {
        case .sqlite: "SELECT name, type FROM sqlite_master WHERE type IN ('table','view') ORDER BY name"
        case .postgres: "SELECT table_schema || '.' || table_name, table_type FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema') ORDER BY 1"
        case .mysql: "SELECT table_name, table_type FROM information_schema.tables WHERE table_schema = DATABASE() ORDER BY 1"
        case .sqlserver: "SET NOCOUNT ON; SELECT TABLE_SCHEMA + '.' + TABLE_NAME, TABLE_TYPE FROM INFORMATION_SCHEMA.TABLES ORDER BY 1"
        }
    }

    /// The SQL that lists a table's columns (name, type, is primary key).
    public static func columnsQuery(_ kind: DataConnection.Kind, table: String) -> String {
        let parts = table.split(separator: ".", maxSplits: 1).map(String.init)
        let name = (parts.last ?? table).replacingOccurrences(of: "'", with: "''")
        let schema = parts.count > 1 ? parts[0].replacingOccurrences(of: "'", with: "''") : nil
        switch kind {
        case .sqlite:
            return "PRAGMA table_info('\(name)')"
        case .postgres, .sqlserver:
            let nocount = kind == .sqlserver ? "SET NOCOUNT ON; " : ""
            return nocount + """
                SELECT c.column_name, c.data_type, CASE WHEN k.column_name IS NULL THEN 'NO' ELSE 'YES' END \
                FROM information_schema.columns c LEFT JOIN (SELECT ku.table_schema, ku.table_name, ku.column_name \
                FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage ku \
                ON tc.constraint_name = ku.constraint_name AND tc.table_schema = ku.table_schema \
                WHERE tc.constraint_type = 'PRIMARY KEY') k ON k.table_schema = c.table_schema AND k.table_name = c.table_name \
                AND k.column_name = c.column_name WHERE c.table_name = '\(name)'\(schema.map { " AND c.table_schema = '\($0)'" } ?? "") \
                ORDER BY c.ordinal_position
                """
        case .mysql:
            return "SELECT column_name, column_type, IF(column_key = 'PRI', 'YES', 'NO') FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = '\(name)' ORDER BY ordinal_position"
        }
    }

    /// A SELECT of the first rows of a table, in the server's dialect.
    public static func topRowsQuery(_ kind: DataConnection.Kind, table: String, count: Int = 200) -> String {
        let quoted = table.split(separator: ".").map { part -> String in
            switch kind {
            case .mysql: "`" + part.replacingOccurrences(of: "`", with: "``") + "`"
            case .sqlserver: "[" + part.replacingOccurrences(of: "]", with: "]]") + "]"
            default: "\"" + part.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
        }.joined(separator: ".")
        return kind == .sqlserver ? "SELECT TOP \(count) * FROM \(quoted)" : "SELECT * FROM \(quoted) LIMIT \(count)"
    }

    /// The client and its arguments for running `sql`. The password, if any, goes in the environment, never the command line.
    public static func command(for connection: DataConnection, sql: String) -> (executable: String, arguments: [String])? {
        switch connection.kind {
        case .sqlite:
            return nil
        case .postgres:
            var arguments = ["-X", "--csv", "-v", "ON_ERROR_STOP=1", "-h", connection.location]
            if !connection.port.isEmpty { arguments += ["-p", connection.port] }
            if !connection.user.isEmpty { arguments += ["-U", connection.user] }
            if !connection.database.isEmpty { arguments += ["-d", connection.database] }
            return ("psql", arguments + ["-c", sql])
        case .mysql:
            var arguments = ["--batch", "--raw", "-h", connection.location]
            if !connection.port.isEmpty { arguments += ["-P", connection.port] }
            if !connection.user.isEmpty { arguments += ["-u", connection.user] }
            if !connection.database.isEmpty { arguments += ["-D", connection.database] }
            return ("mysql", arguments + ["-e", sql])
        case .sqlserver:
            var arguments = ["-S", connection.location + (connection.port.isEmpty ? "" : ",\(connection.port)"), "-s", "\u{1F}", "-W", "-b"]
            if !connection.user.isEmpty { arguments += ["-U", connection.user] }
            if !connection.database.isEmpty { arguments += ["-d", connection.database] }
            return ("sqlcmd", arguments + ["-Q", sql])
        }
    }

    /// The environment variable a client reads the password from.
    public static func passwordVariable(_ kind: DataConnection.Kind) -> String? {
        switch kind {
        case .sqlite: nil
        case .postgres: "PGPASSWORD"
        case .mysql: "MYSQL_PWD"
        case .sqlserver: "SQLCMDPASSWORD"
        }
    }

    /// Reads the client's output: CSV (psql --csv), tab-separated (mysql --batch) or unit-separated (sqlcmd).
    public static func parse(_ output: String, kind: DataConnection.Kind) -> QueryResult {
        let text = output.replacingOccurrences(of: "\r\n", with: "\n")
        var lines: [[String?]]
        switch kind {
        case .postgres, .sqlite: lines = parseCSV(text)
        case .mysql: lines = text.split(separator: "\n", omittingEmptySubsequences: true).map { $0.components(separatedBy: "\t").map { $0 == "NULL" ? nil : unescapeMySQL($0) } }
        case .sqlserver:
            lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                .filter { !$0.hasPrefix("(") || !$0.hasSuffix("affected)") }
                .filter { !$0.allSatisfy { $0 == "-" || $0 == "\u{1F}" } }
                .map { $0.components(separatedBy: "\u{1F}").map { $0 == "NULL" ? nil : $0 } }
        }
        guard let header = lines.first, lines.count >= 1, header.count > 1 || lines.count > 1 else {
            return QueryResult(message: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Command completed." : text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        lines.removeFirst()
        let columns = header.map { $0 ?? "" }
        let rows = lines.map { row in row.count >= columns.count ? Array(row.prefix(columns.count)) : row + Array(repeating: nil, count: columns.count - row.count) }
        return QueryResult(columns: columns, rows: rows, message: "\(rows.count) row\(rows.count == 1 ? "" : "s")")
    }

    static func parseCSV(_ text: String) -> [[String?]] {
        var rows: [[String?]] = []
        var row: [String?] = []
        var field = ""
        var quoted = false
        var wasQuoted = false
        var characters = Array(text)
        if characters.last != "\n" { characters.append("\n") }
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" { field.append("\""); index += 1 } else { quoted = false }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
                wasQuoted = true
            } else if character == "," || character == "\n" {
                // psql writes NULL as an empty, unquoted field.
                row.append(field.isEmpty && !wasQuoted ? nil : field)
                field = ""
                wasQuoted = false
                if character == "\n" {
                    if !(row.count == 1 && row[0] == nil) { rows.append(row) }
                    row = []
                }
            } else {
                field.append(character)
            }
            index += 1
        }
        return rows
    }

    private static func unescapeMySQL(_ value: String) -> String {
        value.replacingOccurrences(of: "\\t", with: "\t").replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\\", with: "\\")
    }
}
