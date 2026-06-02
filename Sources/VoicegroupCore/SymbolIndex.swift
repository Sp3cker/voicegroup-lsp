import Foundation

public struct IndexedSymbol: Equatable, Sendable {
    public var name: String
    public var uri: String
    public var range: SourceRange
    public var targetPath: String?

    public init(name: String, uri: String, range: SourceRange, targetPath: String?) {
        self.name = name
        self.uri = uri
        self.range = range
        self.targetPath = targetPath
    }
}

/// Mirrors poryaaaa's symbol parser for `<label>::` followed by `.incbin`.
/// The LSP keeps source locations so go-to-definition can jump to the symbol
/// declaration instead of only knowing the sample file path.
public struct SymbolIndex: Sendable {
    public var directSound: [String: IndexedSymbol]
    public var programmableWave: [String: IndexedSymbol]

    public init(directSound: [String: IndexedSymbol] = [:], programmableWave: [String: IndexedSymbol] = [:]) {
        self.directSound = directSound
        self.programmableWave = programmableWave
    }

    public static func parseIncbinSymbols(_ text: String, uri: String) -> [String: IndexedSymbol] {
        var symbols: [String: IndexedSymbol] = [:]
        var pending: (name: String, range: SourceRange)?

        for (lineNumber, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let labelEnd = trimmed.range(of: "::"), labelEnd.lowerBound > trimmed.startIndex {
                let name = String(trimmed[..<labelEnd.lowerBound])
                let column = line.distance(from: line.startIndex, to: line.firstNonWhitespaceIndex ?? line.startIndex)
                pending = (name, .init(start: .init(line: lineNumber, character: column), end: .init(line: lineNumber, character: column + name.count)))
                continue
            }
            guard let pendingSymbol = pending, trimmed.contains(".incbin") else { continue }
            let target = quotedString(in: trimmed)
            symbols[pendingSymbol.name] = .init(name: pendingSymbol.name, uri: uri, range: pendingSymbol.range, targetPath: target)
            pending = nil
        }

        return symbols
    }

    private static func quotedString(in text: String) -> String? {
        guard let first = text.firstIndex(of: "\"") else { return nil }
        let afterFirst = text.index(after: first)
        guard let second = text[afterFirst...].firstIndex(of: "\"") else { return nil }
        return String(text[afterFirst..<second])
    }
}

private extension String {
    var firstNonWhitespaceIndex: String.Index? {
        firstIndex { !$0.isWhitespace }
    }
}

