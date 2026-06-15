import Foundation

public enum ArgumentKind: Equatable, Sendable {
    case integer
    case directSoundSymbol
    case programmableWaveSymbol
    case voicegroupSymbol
    case keysplitSymbol
}

public struct NumericRange: Equatable, Sendable {
    public var min: Int
    public var max: Int

    public init(_ min: Int, _ max: Int) {
        self.min = min
        self.max = max
    }

    public func contains(_ value: Int) -> Bool {
        value >= min && value <= max
    }
}
public struct MacroArgument: Equatable, Sendable {
    public var name: String
    public var kind: ArgumentKind
    public var validRange: NumericRange?
    public var help: String

    public init(_ name: String, _ kind: ArgumentKind, range: NumericRange? = nil, help: String) {
        self.name = name
        self.kind = kind
        self.validRange = range
        self.help = help
    }
}
let BaseKeyArg: MacroArgument = .init(
    "base_midi_key", .integer, range: .init(0, 127),
    help: "Root MIDI note used when pitching the DirectSound sample.")
let PanArg: MacroArgument = .init(
    "pan", .integer, range: .init(0, 127),
    help:
        "m4a pan value. Zero means centered/disabled in the emitted macro. Squares accept 0, 64, 127 enumerated."
)
let SqDutyCycleArg: MacroArgument = .init(
    "duty_cycle", .integer, range: .init(0, 3),
    help: "Hardware duty cycle masked to two bits by the assembler macro.")
let SqAttackArg: MacroArgument = .init(
    "attack", .integer, range: .init(0, 7), help: "3-bit hardware envelope attack.")
let SqDecayArg: MacroArgument = .init(
    "decay", .integer, range: .init(0, 7), help: "3-bit hardware envelope decay.")
let SqSustainArg: MacroArgument = .init(
    "sustain", .integer, range: .init(0, 15),
    help: "4-bit hardware envelope sustain.")
let SqReleaseArg: MacroArgument = .init(
    "release", .integer, range: .init(0, 7),
    help: "3-bit hardware envelope release.")
let SqEnvelopeArgs = [SqAttackArg, SqDecayArg, SqSustainArg, SqReleaseArg]
public struct VoiceMacroDefinition: Equatable, Sendable {
    public var name: String
    public var arguments: [MacroArgument]
    public var summary: String

    public init(name: String, arguments: [MacroArgument], summary: String) {
        self.name = name
        self.arguments = arguments
        self.summary = summary
    }
}

/// The catalog is intentionally copied from poryaaaa/plugin/voicegroup/vg_parser.c.
/// Keeping this as data rather than switch-only code lets completions, hovers,
/// parsing, and diagnostics share the same domain truth.
public enum MacroCatalog {
    public static let definitions: [VoiceMacroDefinition] = [
        directSound("voice_directsound_no_resample", "DirectSound sample without m4a resampling."),
        directSound(
            "voice_directsound_alt", "DirectSound sample using the alternate fixed voice type."),
        directSound("voice_directsound", "DirectSound sample voice."),
        square1("voice_square_1_alt", "Square channel 1 alternate hardware voice."),
        square1("voice_square_1", "Square channel 1 hardware voice."),
        square2("voice_square_2_alt", "Square channel 2 alternate hardware voice."),
        square2("voice_square_2", "Square channel 2 hardware voice."),
        progWave("voice_programmable_wave_alt", "Programmable wave alternate hardware voice."),
        progWave("voice_programmable_wave", "Programmable wave hardware voice."),
        noise("voice_noise_alt", "Noise channel alternate hardware voice."),
        noise("voice_noise", "Noise channel hardware voice."),
        VoiceMacroDefinition(
            name: "voice_keysplit_all",
            arguments: [
                .init(
                    "voice_group_pointer", .voicegroupSymbol,
                    help: "Sub-voicegroup used for all notes.")
            ],
            summary: "Routes all notes into a sub-voicegroup, commonly a drumset."
        ),
        VoiceMacroDefinition(
            name: "voice_keysplit",
            arguments: [
                .init(
                    "voice_group_pointer", .voicegroupSymbol,
                    help: "Sub-voicegroup selected by the keysplit table."),
                .init(
                    "keysplit_table_pointer", .keysplitSymbol,
                    help: "Keysplit table that maps notes to sub-voice slots."),
            ],
            summary: "Routes notes to slots in another voicegroup through a keysplit table."
        ),
        VoiceMacroDefinition(
            name: "cry_reverse",
            arguments: [
                .init(
                    "sample", .directSoundSymbol, help: "Cry sample symbol from direct sound data.")
            ],
            summary: "Reverse cry sample voice."
        ),
        VoiceMacroDefinition(
            name: "cry",
            arguments: [
                .init(
                    "sample", .directSoundSymbol, help: "Cry sample symbol from direct sound data.")
            ],
            summary: "Cry sample voice."
        ),
    ]

    public static let byName = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })

    public static func argumentHover(for macro: VoiceMacroDefinition, argumentIndex: Int?) -> String
    {
        if let argumentIndex, macro.arguments.indices.contains(argumentIndex) {
            let argument = macro.arguments[argumentIndex]
            return
                "\(macro.name) argument \(argumentIndex + 1): \(argument.name)\n\n\(argument.help)"
        }
        let signature = macro.arguments.map(\.name).joined(separator: ", ")
        return "\(macro.name) \(signature)\n\n\(macro.summary)"
    }

    private static func directSound(_ name: String, _ summary: String) -> VoiceMacroDefinition {
        VoiceMacroDefinition(
            name: name,
            arguments: [
                BaseKeyArg,
                PanArg,
                .init(
                    "sample_data_pointer", .directSoundSymbol,
                    help: "DirectSoundWaveData_* symbol resolved through direct_sound_data.inc."),
                .init("attack", .integer, range: .init(0, 255), help: "Envelope attack byte."),
                .init("decay", .integer, range: .init(0, 255), help: "Envelope decay byte."),
                .init("sustain", .integer, range: .init(0, 255), help: "Envelope sustain byte."),
                .init("release", .integer, range: .init(0, 255), help: "Envelope release byte."),
            ], summary: summary)
    }

    private static func square1(_ name: String, _ summary: String) -> VoiceMacroDefinition {
        VoiceMacroDefinition(
            name: name,
            arguments: [
                BaseKeyArg,
                PanArg,
                .init("sweep", .integer, range: .init(0, 255), help: "Square 1 sweep byte."),
                SqDutyCycleArg,
            ] + SqEnvelopeArgs, summary: summary)
    }

    private static func square2(_ name: String, _ summary: String) -> VoiceMacroDefinition {
        VoiceMacroDefinition(
            name: name,
            arguments: [
                BaseKeyArg,
                PanArg,
                SqDutyCycleArg,
            ] + SqEnvelopeArgs, summary: summary)
    }

    private static func progWave(_ name: String, _ summary: String) -> VoiceMacroDefinition {
        VoiceMacroDefinition(
            name: name,
            arguments: [
                BaseKeyArg,
                PanArg,
                .init(
                    "wave_samples_pointer", .programmableWaveSymbol,
                    help:
                        "ProgrammableWaveData_* symbol resolved through programmable_wave_data.inc."
                ),
            ] + SqEnvelopeArgs, summary: summary)
    }

    private static func noise(_ name: String, _ summary: String) -> VoiceMacroDefinition {
        VoiceMacroDefinition(
            name: name,
            arguments: [
                .init(
                    "base_midi_key", .integer, range: .init(0, 127),
                    help: "Root MIDI note for the noise voice."),
                .init(
                    "pan", .integer, range: .init(0, 127),
                    help:
                        "Accepted for macro compatibility; poryaaaa runtime ignores it for noise voices."
                ),
                .init(
                    "period", .integer, range: .init(0, 1),
                    help: "Noise period bit. The assembler macro masks this to one bit."),
            ] + SqEnvelopeArgs, summary: summary)
    }
}
