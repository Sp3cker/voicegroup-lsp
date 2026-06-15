import Testing
import Foundation
@testable import VoicegroupCore

@Test func languageServiceCompletesMacroNamesAtLineStart() throws {
    let service = VoicegroupLanguageService(workspace: WorkspaceIndex())
    let completions = service.completions(text: "\tvoice_dir", line: 0, character: 10)

    #expect(completions.contains { $0.label == "voice_directsound" })
    #expect(completions.contains { $0.label == "voice_directsound_no_resample" })
}

@Test func languageServiceCompletesDirectSoundSymbolsInArgumentContext() throws {
    let symbol = IndexedSymbol(
        name: "DirectSoundWaveData_piano",
        uri: "file:///sound/direct_sound_data.inc",
        range: .init(start: .init(line: 0, character: 0), end: .init(line: 0, character: 25)),
        targetPath: "sound/direct_sound_samples/piano.bin"
    )
    let service = VoicegroupLanguageService(
        workspace: WorkspaceIndex(symbols: .init(directSound: [symbol.name: symbol]))
    )
    let text = "\tvoice_directsound 60, 0, DirectSoundWaveData_p"
    let completions = service.completions(text: text, line: 0, character: text.count)

    #expect(completions.contains { $0.label == "DirectSoundWaveData_piano" })
    #expect(!completions.contains { $0.label == "voice_directsound" })
}

@Test func languageServiceNarrowsDirectSoundSymbolsByTypedPrefix() throws {
    let piano = IndexedSymbol(
        name: "DirectSoundWaveData_piano",
        uri: "file:///sound/direct_sound_data.inc",
        range: .init(start: .init(line: 0, character: 0), end: .init(line: 0, character: 25)),
        targetPath: "sound/direct_sound_samples/piano.bin"
    )
    let bass = IndexedSymbol(
        name: "DirectSoundWaveData_bass",
        uri: "file:///sound/direct_sound_data.inc",
        range: .init(start: .init(line: 2, character: 0), end: .init(line: 2, character: 24)),
        targetPath: "sound/direct_sound_samples/bass.bin"
    )
    let service = VoicegroupLanguageService(
        workspace: WorkspaceIndex(symbols: .init(directSound: [piano.name: piano, bass.name: bass]))
    )
    let text = "\tvoice_directsound 60, 0, DirectSoundWaveData_p"
    let completions = service.completions(text: text, line: 0, character: text.count)

    #expect(completions.map(\.label) == ["DirectSoundWaveData_piano"])
}

@Test func languageServiceDoesNotRecommendCrySamplesForDirectSoundVoices() throws {
    let directSound = IndexedSymbol(
        name: "DirectSoundWaveData_piano",
        uri: "file:///sound/direct_sound_data.inc",
        range: .init(start: .init(line: 0, character: 0), end: .init(line: 0, character: 25)),
        targetPath: "sound/direct_sound_samples/piano.bin"
    )
    let cry = IndexedSymbol(
        name: "Cry_MissingNo",
        uri: "file:///sound/direct_sound_data.inc",
        range: .init(start: .init(line: 2, character: 0), end: .init(line: 2, character: 13)),
        targetPath: "sound/direct_sound_samples/cries/missingno.bin"
    )
    let service = VoicegroupLanguageService(
        workspace: WorkspaceIndex(symbols: .init(directSound: [directSound.name: directSound, cry.name: cry]))
    )
    let text = "\tvoice_directsound 60, 0, "
    let completions = service.completions(text: text, line: 0, character: text.count)

    #expect(completions.contains { $0.label == "DirectSoundWaveData_piano" })
    #expect(!completions.contains { $0.label == "Cry_MissingNo" })
}

@Test func languageServiceReturnsHoverForMacroArguments() throws {
    let service = VoicegroupLanguageService(workspace: WorkspaceIndex())
    let hover = service.hover(
        text: "\tvoice_directsound 60, 0, DirectSoundWaveData_piano, 255, 0, 255, 127",
        line: 0,
        character: 20
    )

    #expect(hover?.contains("base_midi_key") == true)
    #expect(hover?.contains("DirectSound") == true)
}

@Test func macroCatalogUsesPoryaaaaVoiceMacroRules() throws {
    #expect(MacroCatalog.byName["voice_directsound_no_resample"]?.arguments.count == 7)
    #expect(MacroCatalog.byName["voice_square_1"]?.arguments.map(\.name) == [
        "base_midi_key", "pan", "sweep", "duty_cycle", "attack", "decay", "sustain", "release"
    ])
    #expect(MacroCatalog.byName["voice_keysplit"]?.arguments.map(\.kind) == [.voicegroupSymbol, .keysplitSymbol])
    #expect(MacroCatalog.byName["cry"]?.arguments.map(\.kind) == [.directSoundSymbol])
}

@Test func parserBuildsVoiceMacroSlots() throws {
    let text = """
    voice_group route101
    \tvoice_keysplit_all voicegroup_rs_drumset
    \tvoice_directsound 60, 0, DirectSoundWaveData_sc88pro_piano1, 255, 0, 255, 127
    \tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0
    """

    let document = VoicegroupParser().parse(text, uri: "file:///sound/voicegroups/route101.inc")

    #expect(document.declarations.first?.name == "route101")
    #expect(document.calls.count == 3)
    #expect(document.calls[0].slot == 0)
    #expect(document.calls[1].slot == 1)
    #expect(document.calls[1].arguments[2].text == "DirectSoundWaveData_sc88pro_piano1")
    #expect(document.calls[2].macroName == "voice_square_1")
}

@Test func parserKeepsArgumentRangesForMacroCalls() throws {
    let text = "\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0"
    let document = VoicegroupParser().parse(text, uri: "file:///sound/voicegroups/route101.inc")
    let call = try #require(document.calls.first)

    let expectedPanRange = SourceRange(
        start: SourcePosition(line: 0, character: 20),
        end: SourcePosition(line: 0, character: 21)
    )
    let expectedSweepRange = SourceRange(
        start: SourcePosition(line: 0, character: 23),
        end: SourcePosition(line: 0, character: 24)
    )

    #expect(call.arguments[1].range == expectedPanRange)
    #expect(call.arguments[2].range == expectedSweepRange)
}

@Test func parserHonorsVoiceGroupStartingNote() throws {
    let text = """
    voice_group custom, 12
    \tvoice_noise 60, 0, 0, 0, 0, 15, 0
    """

    let document = VoicegroupParser().parse(text, uri: "file:///sound/voicegroups/custom.inc")

    #expect(document.declarations.first?.startingNote == 12)
    #expect(document.calls.first?.slot == 12)
}

@Test func symbolIndexParsesIncbinLabels() throws {
    let text = """
    DirectSoundWaveData_sc88pro_piano1::
    \t.incbin "sound/direct_sound_samples/sc88pro_piano1.bin"

    ProgrammableWaveData_1::
    \t.incbin "sound/programmable_wave_samples/01.pcm"
    """

    let symbols = SymbolIndex.parseIncbinSymbols(text, uri: "file:///sound/direct_sound_data.inc")

    #expect(symbols["DirectSoundWaveData_sc88pro_piano1"]?.targetPath == "sound/direct_sound_samples/sc88pro_piano1.bin")
    #expect(symbols["ProgrammableWaveData_1"]?.targetPath == "sound/programmable_wave_samples/01.pcm")
}

@Test func analyzerReportsUnknownSymbolWrongCountAndRange() throws {
    let text = """
    voice_group broken
    \tvoice_directsound 60, 0, MissingSample, 255, 0, 255, 127
    \tvoice_square_1 60, 0, 0, 4, 0, 0, 15
    \tvoice_noise 60, 0, 3, 0, 0, 15, 0
    """

    let document = VoicegroupParser().parse(text, uri: "file:///sound/voicegroups/broken.inc")
    let analyzer = VoicegroupAnalyzer(symbols: SymbolIndex(), keysplits: KeysplitIndex(), voicegroups: [:])
    let diagnostics = analyzer.diagnostics(for: document)

    #expect(diagnostics.contains { $0.code == "unknown-directsound-symbol" })
    #expect(diagnostics.contains { $0.code == "wrong-argument-count" })
    #expect(diagnostics.contains { $0.code == "invalid-range" && $0.message.contains("period") })
}
