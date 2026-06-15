import Foundation

public struct VoicegroupCompletionItem: Equatable, Sendable {
    public var label: String
    public var detail: String
    public var insertText: String
    public var replacementStartLine: Int
    public var replacementStartCharacter: Int
    public var replacementEndLine: Int
    public var replacementEndCharacter: Int

    public init(
        label: String,
        detail: String,
        insertText: String? = nil,
        replacementStartLine: Int = 0,
        replacementStartCharacter: Int = 0,
        replacementEndLine: Int = 0,
        replacementEndCharacter: Int = 0
    ) {
        self.label = label
        self.detail = detail
        self.insertText = insertText ?? label
        self.replacementStartLine = replacementStartLine
        self.replacementStartCharacter = replacementStartCharacter
        self.replacementEndLine = replacementEndLine
        self.replacementEndCharacter = replacementEndCharacter
    }
}

public enum VoicegroupTabActionKind: Int32, Sendable {
    case insertIndent = 0
    case selectRange = 1
    case moveCaret = 2
}

public struct VoicegroupTabAction: Equatable, Sendable {
    public var kind: VoicegroupTabActionKind
    public var startLine: Int
    public var startCharacter: Int
    public var endLine: Int
    public var endCharacter: Int

    public init(
        kind: VoicegroupTabActionKind = .insertIndent,
        startLine: Int = 0,
        startCharacter: Int = 0,
        endLine: Int = 0,
        endCharacter: Int = 0
    ) {
        self.kind = kind
        self.startLine = startLine
        self.startCharacter = startCharacter
        self.endLine = endLine
        self.endCharacter = endCharacter
    }
}

/// Transport-neutral editor intelligence over voicegroup source.
public struct VoicegroupLanguageService: Sendable {
    public let workspace: WorkspaceIndex
    private let parser = VoicegroupParser()

    public init(workspace: WorkspaceIndex) {
        self.workspace = workspace
    }

    public func diagnostics(text: String, uri: String) -> [VoicegroupDiagnostic] {
        let document = parser.parse(text, uri: uri)
        return VoicegroupAnalyzer(symbols: workspace.symbols, keysplits: workspace.keysplits, voicegroups: workspace.voicegroups)
            .diagnostics(for: document)
    }

    public func completions(text: String, line: Int, character: Int) -> [VoicegroupCompletionItem] {
        let lineText = text.line(at: line)
        let prefix = String(lineText.prefix(min(character, lineText.count)))
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
        let replacementRange = completionReplacementRange(lineText: lineText, line: line, character: character)
        let typedPrefix = completionPrefix(lineText: lineText, replacementRange: replacementRange)

        if let context = argumentContext(text: text, line: line, character: character),
           let macro = MacroCatalog.byName[context.macroName],
           macro.arguments.indices.contains(context.argumentIndex) {
            switch macro.arguments[context.argumentIndex].kind {
            case .directSoundSymbol:
                return filteredCompletionLabels(workspace.symbols.directSound.keys, typedPrefix: typedPrefix)
                    .filter { !isCrySampleName($0) }
                    .map {
                        completionItem(label: $0, detail: "DirectSound sample", replacementRange: replacementRange)
                    }
            case .programmableWaveSymbol:
                return filteredCompletionLabels(workspace.symbols.programmableWave.keys, typedPrefix: typedPrefix).map {
                    completionItem(label: $0, detail: "Programmable wave", replacementRange: replacementRange)
                }
            case .keysplitSymbol:
                return filteredCompletionLabels(workspace.keysplits.definitions.keys, typedPrefix: typedPrefix).map {
                    completionItem(label: $0, detail: "Keysplit table", replacementRange: replacementRange)
                }
            case .voicegroupSymbol:
                return filteredCompletionLabels(
                    workspace.voicegroups.keys.map { "voicegroup_\($0)" },
                    typedPrefix: typedPrefix
                ).map {
                    completionItem(label: $0, detail: "Voicegroup", replacementRange: replacementRange)
                }
            case .integer:
                return []
            }
        }

        if trimmedPrefix.hasPrefix("voice_") || trimmedPrefix.isEmpty {
            return MacroCatalog.definitions.map {
                completionItem(
                    label: $0.name,
                    detail: $0.summary,
                    insertText: macroInsertText($0),
                    replacementRange: replacementRange
                )
            }
        }

        return []
    }

    public func hover(text: String, line: Int, character: Int) -> String? {
        let document = parser.parse(text, uri: "inmemory://hover")
        guard let call = document.calls.first(where: { call in
            call.macroRange.contains(line: line, character: character) ||
            call.arguments.contains(where: { $0.range.contains(line: line, character: character) })
        }), let macro = MacroCatalog.byName[call.macroName] else {
            return nil
        }
        let argumentIndex = call.arguments.firstIndex { $0.range.contains(line: line, character: character) }
        return MacroCatalog.argumentHover(for: macro, argumentIndex: argumentIndex)
    }

    public func tabAction(
        text: String,
        startLine: Int,
        startCharacter: Int,
        endLine: Int,
        endCharacter: Int
    ) -> VoicegroupTabAction {
        let document = parser.parse(text, uri: "inmemory://tab")

        for call in document.calls {
            guard let argumentIndex = selectedArgumentIndex(
                in: call,
                startLine: startLine,
                startCharacter: startCharacter,
                endLine: endLine,
                endCharacter: endCharacter
            ) else {
                continue
            }

            let nextIndex = argumentIndex + 1
            guard call.arguments.indices.contains(nextIndex) else {
                return .init()
            }

            let range = call.arguments[nextIndex].range
            return .init(
                kind: .selectRange,
                startLine: range.start.line,
                startCharacter: range.start.character,
                endLine: range.end.line,
                endCharacter: range.end.character
            )
        }

        return .init()
    }

    private func argumentContext(text: String, line: Int, character: Int) -> (macroName: String, argumentIndex: Int)? {
        let lineText = text.line(at: line)
        guard character <= lineText.count else { return nil }
        let prefix = String(lineText.prefix(character))
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(where: { $0.isWhitespace }) else { return nil }
        let macroName = String(trimmed[..<space])
        let args = trimmed[space...]
        let commaCount = args.filter { $0 == "," }.count
        return (macroName, commaCount)
    }

    private func selectedArgumentIndex(
        in call: VoiceMacroCall,
        startLine: Int,
        startCharacter: Int,
        endLine: Int,
        endCharacter: Int
    ) -> Int? {
        call.arguments.firstIndex { argument in
            argument.range.start.line == startLine &&
                argument.range.end.line == endLine &&
                argument.range.start.character <= startCharacter &&
                argument.range.end.character >= endCharacter
        }
    }

    private func completionItem(
        label: String,
        detail: String,
        insertText: String? = nil,
        replacementRange: (line: Int, start: Int, end: Int)
    ) -> VoicegroupCompletionItem {
        .init(
            label: label,
            detail: detail,
            insertText: insertText,
            replacementStartLine: replacementRange.line,
            replacementStartCharacter: replacementRange.start,
            replacementEndLine: replacementRange.line,
            replacementEndCharacter: replacementRange.end
        )
    }

    private func completionReplacementRange(lineText: String, line: Int, character: Int) -> (line: Int, start: Int, end: Int) {
        let end = min(character, lineText.count)
        let prefix = Array(lineText.prefix(end))
        var start = end

        while start > 0 {
            let previous = prefix[start - 1]
            if previous.isWhitespace || previous == "," {
                break
            }
            start -= 1
        }

        return (line, start, end)
    }

    private func completionPrefix(lineText: String, replacementRange: (line: Int, start: Int, end: Int)) -> String {
        let characters = Array(lineText)
        guard replacementRange.start >= 0,
              replacementRange.end <= characters.count,
              replacementRange.start <= replacementRange.end else {
            return ""
        }
        return String(characters[replacementRange.start..<replacementRange.end])
    }

    private func filteredCompletionLabels(_ labels: some Collection<String>, typedPrefix: String) -> [String] {
        labels.sorted().filter { label in
            typedPrefix.isEmpty || label.localizedCaseInsensitiveComparePrefix(typedPrefix)
        }
    }

    private func isCrySampleName(_ name: String) -> Bool {
        name.lowercased().hasPrefix("cry_")
    }

    private func macroInsertText(_ macro: VoiceMacroDefinition) -> String {
        let defaults = macro.arguments.map { defaultInsertText(for: $0, macroName: macro.name) }
        if defaults.isEmpty {
            return macro.name
        }
        return "\(macro.name) \(defaults.joined(separator: ", "))"
    }

    private func defaultInsertText(for argument: MacroArgument, macroName: String) -> String {
        switch argument.kind {
        case .directSoundSymbol:
            return "DirectSoundWaveData_"
        case .programmableWaveSymbol:
            return "ProgrammableWaveData_"
        case .voicegroupSymbol:
            return "voicegroup_"
        case .keysplitSymbol:
            return "KeysplitTable_"
        case .integer:
            return defaultIntegerText(for: argument.name, macroName: macroName)
        }
    }

    private func defaultIntegerText(for argumentName: String, macroName: String) -> String {
        let isDirectSound = macroName.hasPrefix("voice_directsound")

        switch argumentName {
        case "base_midi_key":
            return "60"
        case "pan", "sweep", "period", "attack", "decay":
            return isDirectSound && argumentName == "attack" ? "255" : "0"
        case "duty_cycle":
            return "2"
        case "sustain":
            return isDirectSound ? "255" : "15"
        case "release":
            return isDirectSound ? "127" : "0"
        default:
            return "0"
        }
    }
}

private extension String {
    func localizedCaseInsensitiveComparePrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    }
}

private extension String {
    func line(at index: Int) -> String {
        let lines = split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.indices.contains(index) else { return "" }
        return lines[index]
    }
}
