import Foundation

public struct KeysplitDefinition: Equatable, Sendable {
    public var name: String
    public var uri: String
    public var range: SourceRange
    public var startingNote: Int
    public var table: [UInt8]
}

/// Parses both keysplit table formats supported by poryaaaa: pokeemerald's
/// `keysplit`/`split` macros and pokefirered's raw `.set`/`.byte` table form.
public struct KeysplitIndex: Sendable {
    public var definitions: [String: KeysplitDefinition]

    public init(definitions: [String: KeysplitDefinition] = [:]) {
        self.definitions = definitions
    }

    public static func parse(_ text: String, uri: String) -> KeysplitIndex {
        var result: [String: KeysplitDefinition] = [:]
        var current: KeysplitDefinition?
        var lastNote = 0

        func storeCurrent() {
            if let current {
                result[current.name] = current
            }
        }

        for (lineNumber, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("keysplit ") {
                storeCurrent()
                let rest = trimmed.dropFirst("keysplit ".count)
                let parts = rest.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard let baseName = parts.first else { continue }
                let start = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                lastNote = start
                current = .init(
                    name: "keysplit_\(baseName)",
                    uri: uri,
                    range: .init(start: .init(line: lineNumber, character: 0), end: .init(line: lineNumber, character: trimmed.count)),
                    startingNote: start,
                    table: Array(repeating: 0, count: 128)
                )
            } else if trimmed.hasPrefix("split "), var active = current {
                let rest = trimmed.dropFirst("split ".count)
                let parts = rest.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, let index = UInt8(parts[0]), let endNote = Int(parts[1]) else { continue }
                for note in max(0, lastNote)..<min(128, endNote) {
                    active.table[note] = index
                }
                lastNote = endNote
                current = active
            } else if trimmed.hasPrefix(".set ") {
                storeCurrent()
                let rest = trimmed.dropFirst(".set ".count)
                let parts = rest.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard let name = parts.first else { continue }
                let start = parts.count > 1 ? Int(parts[1].replacingOccurrences(of: ". -", with: "").trimmingCharacters(in: .whitespaces)) ?? 0 : 0
                lastNote = start
                current = .init(
                    name: name,
                    uri: uri,
                    range: .init(start: .init(line: lineNumber, character: 0), end: .init(line: lineNumber, character: trimmed.count)),
                    startingNote: start,
                    table: Array(repeating: 0, count: 128)
                )
            } else if trimmed.hasPrefix(".byte "), var active = current {
                let values = trimmed.dropFirst(".byte ".count).split(separator: ",").compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
                for value in values where lastNote < 128 {
                    active.table[lastNote] = value
                    lastNote += 1
                }
                current = active
            }
        }

        storeCurrent()
        return .init(definitions: result)
    }
}

