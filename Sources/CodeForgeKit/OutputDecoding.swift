import Foundation

public enum OutputLineKind: Sendable, Equatable {
    case normal, error, warning
}

/// Colors program output by what a line says, since a terminal doesn't separate stdout from stderr.
public enum OutputClassifier {
    private static let errorPattern = try! NSRegularExpression(pattern: #"""
        (?x) ^\s*(?:error|fatal\ error|fatal)(?:\[[^\]]*\])?\s*:      # error: …  error[E0308]: …
        | :\s*(?:fatal\ )?error(?:\s+[A-Z]+\d+)?\s*:                  # file.c:3:1: error: …  a.cs(1,2): error CS1002: …
        | ^Traceback\ \(most\ recent\ call\ last\)
        | ^(?:[A-Za-z_][\w.]*)?(?:Error|Exception)(?::\ .*)?$         # ValueError: … (Python, Node, Java)
        | ^Exception\ in\ thread\b
        | ^Unhandled\ exception\b
        | ^panic:\ 
        | ^thread\ '.*'(?:\ \(\d+\))?\ panicked\b
        | \bFatal\ error:\                                            # Swift crashes
        | ^Build\ FAILED\b | ^FAILED\b | ^Failed!\s
        | ^zsh:\ .*(?:command\ not\ found|no\ such\ file|permission\ denied)
        | ^\S*\.go:\d+:\d+:\                                            # Go compile errors have no "error:"
        | \[FAIL\]\s*$ | ^\s*Failed\ \S+\ \[\d                # a failing .NET test
        | ^Segmentation\ fault | ^Bus\ error | ^Illegal\ instruction | ^Abort\ trap
        """#)
    private static let warningPattern = try! NSRegularExpression(pattern: #"""
        (?x) ^\s*warning(?:\[[^\]]*\])?\s*:                           # warning: …
        | :\s*warning(?:\s+[A-Z]+\d+)?\s*:                            # file.c:3:1: warning: …
        | ^npm\ (?:WARN|warn)\b
        """#)

    public static func kind(of line: String) -> OutputLineKind {
        let range = NSRange(location: 0, length: (line as NSString).length)
        if errorPattern.firstMatch(in: line, range: range) != nil { return .error }
        if warningPattern.firstMatch(in: line, range: range) != nil { return .warning }
        return .normal
    }
}

/// Turns bytes from a terminal into text pieces: never splits a UTF-8 character across reads, and colors whole lines.
public struct OutputDecoder: Sendable {
    public struct Piece: Sendable, Equatable {
        public let text: String
        public let kind: OutputLineKind
    }

    private var bytes: [UInt8] = []
    /// The unfinished line already shown (a prompt); its end is shown uncolored.
    private var showedPartial = false

    public init() {}

    public mutating func append(_ data: [UInt8]) -> [Piece] {
        bytes += data
        var pieces: [Piece] = []
        while let newline = bytes.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let isPair = bytes[newline] == 13 && newline + 1 < bytes.count && bytes[newline + 1] == 10
            // A lone \r at the very end may be half of \r\n: wait for the next read.
            if bytes[newline] == 13 && newline + 1 == bytes.count { break }
            let newlineByte = bytes[newline]
            let line = String(decoding: bytes[..<newline], as: UTF8.self)
            bytes.removeSubrange(...(isPair ? newline + 1 : newline))
            defer { showedPartial = false }
            // A lone \r rewrites the line, as with git's percentages: only the last version stays.
            // (A part already shown can't be taken back, so that one just ends.)
            if newlineByte == 13, !isPair, !showedPartial { continue }
            if !showedPartial, Self.isBuildProgress(line) { continue }
            let kind = showedPartial ? OutputLineKind.normal : OutputClassifier.kind(of: line)
            pieces.append(Piece(text: line + "\n", kind: kind))
        }
        return pieces
    }

    /// True while the end of a line is waiting: it may be a prompt, or the rest of the line may be about to come.
    public var hasPartialLine: Bool { !bytes.isEmpty }

    /// Shows what's waiting of the line, for when nothing more comes shortly: the program may be asking for input.
    /// Keeps back a character split between reads, and a \r that may be half of \r\n.
    public mutating func flushPartialLine() -> [Piece] {
        let complete = bytes.count - Self.incompleteTail(of: bytes)
        guard complete > 0, bytes[..<complete].last != 13 else { return [] }
        let text = String(decoding: bytes[..<complete], as: UTF8.self)
        bytes.removeSubrange(..<complete)
        defer { showedPartial = true }
        return [Piece(text: text, kind: showedPartial ? .normal : OutputClassifier.kind(of: text))]
    }

    public mutating func finish() -> [Piece] {
        defer { bytes = [] }
        let text = String(decoding: bytes.filter { $0 != 13 }, as: UTF8.self)
        return text.isEmpty ? [] : [Piece(text: text, kind: showedPartial ? .normal : OutputClassifier.kind(of: text))]
    }

    /// SwiftPM's step counter ("[3 / 41]", with thin spaces, so a program's own "[3/41]" stays): noise once the build is done.
    private static func isBuildProgress(_ line: String) -> Bool {
        line.range(of: "^\\[\\d+\u{2009}/\u{2009}\\d+\\]( \\S+)?$", options: .regularExpression) != nil
    }

    /// How many bytes at the end begin a UTF-8 character that isn't complete yet.
    private static func incompleteTail(of bytes: [UInt8]) -> Int {
        for back in 1...min(3, max(bytes.count, 1)) where back <= bytes.count {
            let byte = bytes[bytes.count - back]
            if byte & 0b1100_0000 == 0b1000_0000 { continue }
            let needed = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
            return needed > back ? back : 0
        }
        return 0
    }
}
