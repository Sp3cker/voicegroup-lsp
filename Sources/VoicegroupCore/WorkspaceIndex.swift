import Foundation

public struct WorkspaceIndex: Sendable {
    public var symbols: SymbolIndex
    public var keysplits: KeysplitIndex
    public var voicegroups: [String: IndexedSymbol]

    public init(symbols: SymbolIndex = .init(), keysplits: KeysplitIndex = .init(), voicegroups: [String: IndexedSymbol] = [:]) {
        self.symbols = symbols
        self.keysplits = keysplits
        self.voicegroups = voicegroups
    }

    /// Builds the pieces needed for editor intelligence from a decomp project
    /// root. The path choices mirror poryaaaa's standard discovery path; later
    /// iterations can add config overrides and deeper fork discovery.
    public static func load(projectRoot: URL) -> WorkspaceIndex {
        let directSound = parseSymbolsIfPresent(projectRoot.appending(path: "sound/direct_sound_data.inc"))
        let progWave = parseSymbolsIfPresent(projectRoot.appending(path: "sound/programmable_wave_data.inc"))
        let keysplits = parseKeysplitsIfPresent(projectRoot.appending(path: "sound/keysplit_tables.inc"))
        let voicegroups = discoverVoicegroups(projectRoot: projectRoot)
        return .init(symbols: .init(directSound: directSound, programmableWave: progWave), keysplits: keysplits, voicegroups: voicegroups)
    }

    private static func parseSymbolsIfPresent(_ url: URL) -> [String: IndexedSymbol] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return SymbolIndex.parseIncbinSymbols(text, uri: url.absoluteString)
    }

    private static func parseKeysplitsIfPresent(_ url: URL) -> KeysplitIndex {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .init() }
        return KeysplitIndex.parse(text, uri: url.absoluteString)
    }

    private static func discoverVoicegroups(projectRoot: URL) -> [String: IndexedSymbol] {
        let root = projectRoot.appending(path: "sound/voicegroups")
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        var result: [String: IndexedSymbol] = [:]
        for case let url as URL in enumerator where url.pathExtension == "inc" || url.pathExtension == "s" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let parsed = VoicegroupParser().parse(text, uri: url.absoluteString)
            for declaration in parsed.declarations {
                result[declaration.name] = .init(name: declaration.name, uri: url.absoluteString, range: declaration.range, targetPath: nil)
            }
        }
        return result
    }
}
