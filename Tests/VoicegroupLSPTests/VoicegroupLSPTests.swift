import Testing
import Foundation
@testable import VoicegroupCore
@testable import VoicegroupLSP

@Test func languageServiceCompletesMacroNamesAtLineStart() throws {
    let service = LanguageService(workspace: WorkspaceIndex())
    let completions = service.completions(text: "\tvoice_dir", line: 0, character: 10)

    #expect(completions.contains { $0.label == "voice_directsound" })
    #expect(completions.contains { $0.label == "voice_directsound_no_resample" })
}

@Test func languageServiceReturnsHoverForMacroArguments() throws {
    let service = LanguageService(workspace: WorkspaceIndex())
    let hover = service.hover(
        text: "\tvoice_directsound 60, 0, DirectSoundWaveData_piano, 255, 0, 255, 127",
        line: 0,
        character: 20
    )

    #expect(hover?.contains("base_midi_key") == true)
    #expect(hover?.contains("DirectSound") == true)
}

@Test func messageFramingDecodesStandardCRLFLSPMessages() throws {
    let body = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootUri":null}}"#
    let framed = "Content-Length: \(body.utf8.count)\r\n\r\n\(body)"

    let decoded = try #require(LSPMessageFraming.decode(Data(framed.utf8)).first)

    #expect(decoded["method"] as? String == "initialize")
    #expect(decoded["id"] as? Int == 1)
}
