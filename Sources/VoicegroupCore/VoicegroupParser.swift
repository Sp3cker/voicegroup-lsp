import Foundation

public struct VoicegroupDeclaration: Equatable, Sendable {
    public var name: String
    public var startingNote: Int
    public var range: SourceRange
}

public struct VoiceArgument: Equatable, Sendable {
    public var text: String
    public var range: SourceRange
}

public struct VoiceMacroCall: Equatable, Sendable {
    public var macroName: String
    public var macroRange: SourceRange
    public var arguments: [VoiceArgument]
    public var slot: Int
    public var lineComment: String?
}

public struct ParsedVoicegroupDocument: Equatable, Sendable {
    public var uri: String
    public var declarations: [VoicegroupDeclaration]
    public var calls: [VoiceMacroCall]
    public var syntaxDiagnostics: [VoicegroupDiagnostic]
}

/// Parses the small assembly-macro language used by sound/voicegroups.
/// Unlike the poryaaaa runtime parser, this keeps malformed lines and ranges
/// so the editor can explain mistakes while a user is still typing.
public struct VoicegroupParser: Sendable {
    public init() {}

    public func parse(_ text: String, uri: String) -> ParsedVoicegroupDocument {
        var declarations: [VoicegroupDeclaration] = []
        var calls: [VoiceMacroCall] = []
        var diagnostics: [VoicegroupDiagnostic] = []
        var voiceIndex = 0

        for (lineNumber, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            let comment = trailingAtComment(in: line)
            let code = stripAtComment(from: line)
            let trimmedStart = code.firstNonWhitespaceIndex ?? code.endIndex
            let trimmed = String(code[trimmedStart...]).trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let startColumn = code.distance(from: code.startIndex, to: trimmedStart)
            if trimmed.hasPrefix("voice_group") {
                let range = SourceRange(
                    start: .init(line: lineNumber, character: startColumn),
                    end: .init(line: lineNumber, character: code.count)
                )
                switch parseVoiceGroupDeclaration(trimmed, range: range) {
                case .success(let declaration):
                    declarations.append(declaration)
                    voiceIndex = declaration.startingNote
                case .failure(let diagnostic):
                    diagnostics.append(diagnostic)
                }
                continue
            }

            guard let macroEnd = trimmed.firstIndex(where: { $0.isWhitespace }) else {
                diagnostics.append(.init(
                    range: .init(start: .init(line: lineNumber, character: startColumn), end: .init(line: lineNumber, character: code.count)),
                    severity: .warning,
                    code: "unknown-line",
                    message: "Expected a voice macro call."
                ))
                continue
            }

            let macroName = String(trimmed[..<macroEnd])
            guard MacroCatalog.byName[macroName] != nil else {
                diagnostics.append(.init(
                    range: .init(start: .init(line: lineNumber, character: startColumn), end: .init(line: lineNumber, character: startColumn + macroName.count)),
                    severity: .warning,
                    code: "unknown-macro",
                    message: "Unknown voice macro '\(macroName)'."
                ))
                continue
            }

            let argsStartInTrimmed = trimmed.distance(from: trimmed.startIndex, to: macroEnd) + 1
            let argsStartColumn = startColumn + argsStartInTrimmed
            let argText = String(trimmed[macroEnd...]).trimmingCharacters(in: .whitespaces)
            let arguments = splitArguments(argText, line: lineNumber, startColumn: argsStartColumn)
            let call = VoiceMacroCall(
                macroName: macroName,
                macroRange: .init(
                    start: .init(line: lineNumber, character: startColumn),
                    end: .init(line: lineNumber, character: startColumn + macroName.count)
                ),
                arguments: arguments,
                slot: voiceIndex,
                lineComment: comment
            )
            calls.append(call)
            voiceIndex += 1
        }

        return .init(uri: uri, declarations: declarations, calls: calls, syntaxDiagnostics: diagnostics)
    }

    private enum DeclarationParseResult {
        case success(VoicegroupDeclaration)
        case failure(VoicegroupDiagnostic)
    }

    private func parseVoiceGroupDeclaration(_ trimmed: String, range: SourceRange) -> DeclarationParseResult {
        let rest = trimmed.dropFirst("voice_group".count).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else {
            return .failure(.init(range: range, severity: .error, code: "malformed-voice-group", message: "voice_group requires a label."))
        }
        let parts = rest.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        let name = parts[0]
        var startingNote = 0
        if parts.count == 2 {
            guard let parsed = Int(parts[1]), (0..<128).contains(parsed) else {
                return .failure(.init(range: range, severity: .error, code: "invalid-starting-note", message: "voice_group starting note must be in 0...127."))
            }
            startingNote = parsed
        }
        return .success(.init(name: name, startingNote: startingNote, range: range))
    }

    private func splitArguments(_ text: String, line: Int, startColumn: Int) -> [VoiceArgument] {
        var args: [VoiceArgument] = []
        var current = ""
        var argStart = 0

        for (offset, character) in text.enumerated() {
            if character == "," {
                appendArg(current, argStart: argStart, endOffset: offset, line: line, startColumn: startColumn, into: &args)
                current = ""
                argStart = offset + 1
            } else {
                current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty || text.hasSuffix(",") {
            appendArg(current, argStart: argStart, endOffset: text.count, line: line, startColumn: startColumn, into: &args)
        }
        return args
    }

    private func appendArg(_ raw: String, argStart: Int, endOffset: Int, line: Int, startColumn: Int, into args: inout [VoiceArgument]) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let leading = raw.prefix { $0.isWhitespace }.count
        let start = startColumn + argStart + leading
        args.append(.init(
            text: trimmed,
            range: .init(start: .init(line: line, character: start), end: .init(line: line, character: start + trimmed.count))
        ))
    }

    private func stripAtComment(from line: String) -> String {
        guard let at = line.firstIndex(of: "@") else { return line }
        return String(line[..<at])
    }

    private func trailingAtComment(in line: String) -> String? {
        guard let at = line.firstIndex(of: "@") else { return nil }
        let comment = line[line.index(after: at)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return comment.isEmpty ? nil : comment
    }
}

private extension String {
    var firstNonWhitespaceIndex: String.Index? {
        firstIndex { !$0.isWhitespace }
    }
}
