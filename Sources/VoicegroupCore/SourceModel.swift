import Foundation

/// LSP works in zero-based lines and UTF-16-ish columns. The files this server
/// targets are ASCII assembly includes, so a simple character offset is enough
/// for accurate editor ranges without paying for a full text rope.
public struct SourcePosition: Equatable, Sendable, Codable {
    public var line: Int
    public var character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

/// Every parsed token keeps a range because diagnostics, hovers, completions,
/// and go-to-definition all need to point at the exact argument, not just the
/// containing line.
public struct SourceRange: Equatable, Sendable, Codable {
    public var start: SourcePosition
    public var end: SourcePosition

    public init(start: SourcePosition, end: SourcePosition) {
        self.start = start
        self.end = end
    }

    public func contains(line: Int, character: Int) -> Bool {
        guard line >= start.line && line <= end.line else { return false }
        if line == start.line && character < start.character { return false }
        if line == end.line && character > end.character { return false }
        return true
    }
}

public enum DiagnosticSeverity: Int, Sendable, Codable {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4
}

public struct VoicegroupDiagnostic: Equatable, Sendable {
    public var range: SourceRange
    public var severity: DiagnosticSeverity
    public var code: String
    public var message: String

    public init(range: SourceRange, severity: DiagnosticSeverity, code: String, message: String) {
        self.range = range
        self.severity = severity
        self.code = code
        self.message = message
    }
}

