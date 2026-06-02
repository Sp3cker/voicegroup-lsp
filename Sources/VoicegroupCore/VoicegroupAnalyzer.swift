import Foundation

/// Semantic diagnostics live outside the parser so half-typed documents can
/// still produce completions and hovers from the AST that did parse.
public struct VoicegroupAnalyzer: Sendable {
    public var symbols: SymbolIndex
    public var keysplits: KeysplitIndex
    public var voicegroups: [String: IndexedSymbol]

    public init(symbols: SymbolIndex, keysplits: KeysplitIndex, voicegroups: [String: IndexedSymbol]) {
        self.symbols = symbols
        self.keysplits = keysplits
        self.voicegroups = voicegroups
    }

    public func diagnostics(for document: ParsedVoicegroupDocument) -> [VoicegroupDiagnostic] {
        var diagnostics = document.syntaxDiagnostics

        for call in document.calls {
            guard let definition = MacroCatalog.byName[call.macroName] else { continue }
            if call.arguments.count != definition.arguments.count {
                diagnostics.append(.init(
                    range: call.macroRange,
                    severity: .error,
                    code: "wrong-argument-count",
                    message: "\(call.macroName) expects \(definition.arguments.count) arguments, got \(call.arguments.count)."
                ))
                continue
            }

            if !(0..<128).contains(call.slot) {
                diagnostics.append(.init(
                    range: call.macroRange,
                    severity: .error,
                    code: "slot-out-of-range",
                    message: "Voice slot \(call.slot) is outside the 0...127 voicegroup range."
                ))
            }

            for (index, argument) in call.arguments.enumerated() {
                let expected = definition.arguments[index]
                switch expected.kind {
                case .integer:
                    validateInteger(argument, expected: expected, into: &diagnostics)
                case .directSoundSymbol:
                    if symbols.directSound[argument.text] == nil {
                        diagnostics.append(.init(range: argument.range, severity: .warning, code: "unknown-directsound-symbol", message: "Unknown DirectSound symbol '\(argument.text)'."))
                    }
                case .programmableWaveSymbol:
                    if symbols.programmableWave[argument.text] == nil {
                        diagnostics.append(.init(range: argument.range, severity: .warning, code: "unknown-programmable-wave-symbol", message: "Unknown programmable wave symbol '\(argument.text)'."))
                    }
                case .keysplitSymbol:
                    if keysplits.definitions[argument.text] == nil {
                        diagnostics.append(.init(range: argument.range, severity: .warning, code: "unknown-keysplit-symbol", message: "Unknown keysplit table '\(argument.text)'."))
                    }
                case .voicegroupSymbol:
                    let normalized = argument.text.hasPrefix("voicegroup_") ? String(argument.text.dropFirst("voicegroup_".count)) : argument.text
                    if !voicegroups.isEmpty && voicegroups[normalized] == nil && voicegroups[argument.text] == nil {
                        diagnostics.append(.init(range: argument.range, severity: .warning, code: "unknown-voicegroup-symbol", message: "Unknown voicegroup '\(argument.text)'."))
                    }
                }
            }
        }

        return diagnostics
    }

    private func validateInteger(_ argument: VoiceArgument, expected: MacroArgument, into diagnostics: inout [VoicegroupDiagnostic]) {
        guard let value = Int(argument.text) else {
            diagnostics.append(.init(range: argument.range, severity: .error, code: "invalid-integer", message: "\(expected.name) must be an integer."))
            return
        }
        if let range = expected.validRange, !range.contains(value) {
            diagnostics.append(.init(range: argument.range, severity: .warning, code: "invalid-range", message: "\(expected.name) should be in \(range.min)...\(range.max)."))
        }
    }
}

