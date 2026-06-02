import Foundation
import VoicegroupCore

public struct CompletionItem: Equatable, Sendable {
    public var label: String
    public var detail: String
}

/// This is the testable editor-intelligence facade. The JSON-RPC server is
/// deliberately thin so parser/completion/hover behavior can be tested without
/// having to spin up VS Code or speak LSP framing in unit tests.
public struct LanguageService: Sendable {
    public var workspace: WorkspaceIndex
    private let parser = VoicegroupParser()

    public init(workspace: WorkspaceIndex) {
        self.workspace = workspace
    }

    public func diagnostics(text: String, uri: String) -> [VoicegroupDiagnostic] {
        let document = parser.parse(text, uri: uri)
        return VoicegroupAnalyzer(symbols: workspace.symbols, keysplits: workspace.keysplits, voicegroups: workspace.voicegroups)
            .diagnostics(for: document)
    }

    public func completions(text: String, line: Int, character: Int) -> [CompletionItem] {
        let lineText = text.line(at: line)
        let prefix = String(lineText.prefix(min(character, lineText.count)))
        if prefix.trimmingCharacters(in: .whitespaces).hasPrefix("voice_") || prefix.trimmingCharacters(in: .whitespaces).isEmpty {
            return MacroCatalog.definitions.map { .init(label: $0.name, detail: $0.summary) }
        }

        guard let context = argumentContext(text: text, line: line, character: character),
              let macro = MacroCatalog.byName[context.macroName],
              macro.arguments.indices.contains(context.argumentIndex) else {
            return []
        }

        switch macro.arguments[context.argumentIndex].kind {
        case .directSoundSymbol:
            return workspace.symbols.directSound.keys.sorted().map { .init(label: $0, detail: "DirectSound sample") }
        case .programmableWaveSymbol:
            return workspace.symbols.programmableWave.keys.sorted().map { .init(label: $0, detail: "Programmable wave") }
        case .keysplitSymbol:
            return workspace.keysplits.definitions.keys.sorted().map { .init(label: $0, detail: "Keysplit table") }
        case .voicegroupSymbol:
            return workspace.voicegroups.keys.sorted().map { .init(label: "voicegroup_\($0)", detail: "Voicegroup") }
        case .integer:
            return []
        }
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
}

private extension String {
    func line(at index: Int) -> String {
        let lines = split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.indices.contains(index) else { return "" }
        return lines[index]
    }
}

