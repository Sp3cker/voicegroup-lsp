import Foundation
import Testing
@testable import VoicegroupBridge

private final class BridgeCallbackResult {
    var labels: [String] = []
    var insertTexts: [String] = []
    var ranges: [(Int32, Int32, Int32, Int32)] = []
    var hoverText = ""
}

@Test func bridgeCompletesSyncedDocument() throws {
    let service = try #require(textedit_voicegroup_service_create(nil))
    defer { textedit_voicegroup_service_destroy(service) }

    let synced = textedit_voicegroup_service_sync_document(
        service,
        "file:///textedit/voicegroup.inc",
        "\tvoice_dir"
    )
    #expect(synced == 1)

    let result = BridgeCallbackResult()
    let completed = textedit_voicegroup_service_complete(service, 0, 10, { label, _, insertText, startLine, startCharacter, endLine, endCharacter, userData in
        let result = Unmanaged<BridgeCallbackResult>.fromOpaque(userData!).takeUnretainedValue()
        result.labels.append(String(cString: label!))
        result.insertTexts.append(String(cString: insertText!))
        result.ranges.append((startLine, startCharacter, endLine, endCharacter))
    }, Unmanaged.passUnretained(result).toOpaque())

    #expect(completed == 1)
    #expect(result.labels.contains("voice_directsound"))
    let directSoundIndex = try #require(result.labels.firstIndex(of: "voice_directsound"))
    #expect(result.insertTexts[directSoundIndex] == "voice_directsound 60, 0, DirectSoundWaveData_, 255, 0, 255, 127")
    #expect(result.ranges[directSoundIndex].0 == 0)
    #expect(result.ranges[directSoundIndex].1 == 1)
    #expect(result.ranges[directSoundIndex].2 == 0)
    #expect(result.ranges[directSoundIndex].3 == 10)
}

@Test func bridgeReturnsHoverForSyncedDocument() throws {
    let service = try #require(textedit_voicegroup_service_create(nil))
    defer { textedit_voicegroup_service_destroy(service) }

    let synced = textedit_voicegroup_service_sync_document(
        service,
        "file:///textedit/voicegroup.inc",
        "\tvoice_directsound 60, 0, DirectSoundWaveData_piano, 255, 0, 255, 127"
    )
    #expect(synced == 1)

    let result = BridgeCallbackResult()
    let hovered = textedit_voicegroup_service_hover(service, 0, 20, { text, userData in
        let result = Unmanaged<BridgeCallbackResult>.fromOpaque(userData!).takeUnretainedValue()
        result.hoverText = String(cString: text!)
    }, Unmanaged.passUnretained(result).toOpaque())

    #expect(hovered == 1)
    #expect(result.hoverText.contains("base_midi_key"))
}

@Test func bridgeReturnsTabActionForNextArgument() throws {
    let service = try #require(textedit_voicegroup_service_create(nil))
    defer { textedit_voicegroup_service_destroy(service) }

    let synced = textedit_voicegroup_service_sync_document(
        service,
        "file:///textedit/voicegroup.inc",
        "\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0"
    )
    #expect(synced == 1)

    var kind: Int32 = 0
    var startLine: Int32 = 0
    var startCharacter: Int32 = 0
    var endLine: Int32 = 0
    var endCharacter: Int32 = 0
    let completed = textedit_voicegroup_service_tab_action(
        service,
        0,
        20,
        0,
        21,
        &kind,
        &startLine,
        &startCharacter,
        &endLine,
        &endCharacter
    )

    #expect(completed == 1)
    #expect(kind == 1)
    #expect(startLine == 0)
    #expect(startCharacter == 23)
    #expect(endLine == 0)
    #expect(endCharacter == 24)
}

@Test func bridgeReloadsProjectRootForSampleCompletions() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root.appending(path: "sound"), withIntermediateDirectories: true)
    try """
    DirectSoundWaveData_piano::
    \t.incbin "sound/direct_sound_samples/piano.bin"
    """.write(to: root.appending(path: "sound/direct_sound_data.inc"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let service = try #require(textedit_voicegroup_service_create(nil))
    defer { textedit_voicegroup_service_destroy(service) }

    let rootAccepted = root.path.withCString {
        textedit_voicegroup_service_set_project_root(service, $0)
    }
    #expect(rootAccepted == 1)

    let text = "\tvoice_directsound 60, 0, DirectSoundWaveData_p"
    let synced = textedit_voicegroup_service_sync_document(
        service,
        "file:///textedit/voicegroup.inc",
        text
    )
    #expect(synced == 1)

    let result = BridgeCallbackResult()
    let completed = textedit_voicegroup_service_complete(service, 0, Int32(text.count), { label, _, _, _, _, _, _, userData in
        let result = Unmanaged<BridgeCallbackResult>.fromOpaque(userData!).takeUnretainedValue()
        result.labels.append(String(cString: label!))
    }, Unmanaged.passUnretained(result).toOpaque())

    #expect(completed == 1)
    #expect(result.labels.contains("DirectSoundWaveData_piano"))
}

@Test func bridgeRejectsInvalidProjectRoot() throws {
    let service = try #require(textedit_voicegroup_service_create(nil))
    defer { textedit_voicegroup_service_destroy(service) }

    let rejected = "/tmp/not-a-voicegroup-project-\(UUID().uuidString)".withCString {
        textedit_voicegroup_service_set_project_root(service, $0)
    }

    #expect(rejected == 0)
}

@Test func bridgeRejectsInvalidCreateRoot() throws {
    let service = "/tmp/not-a-voicegroup-project-\(UUID().uuidString)".withCString {
        textedit_voicegroup_service_create($0)
    }

    #expect(service == nil)
}

@Test func bridgeRejectsEmptyDocumentURI() throws {
    let service = try #require(textedit_voicegroup_service_create(nil))
    defer { textedit_voicegroup_service_destroy(service) }

    let synced = textedit_voicegroup_service_sync_document(service, "", "\tvoice_dir")

    #expect(synced == 0)
}

@Test func bridgeTreatsEmptyCompletionResultAsSuccess() throws {
    let service = try #require(textedit_voicegroup_service_create(nil))
    defer { textedit_voicegroup_service_destroy(service) }

    let text = "\tvoice_directsound 60"
    let synced = textedit_voicegroup_service_sync_document(
        service,
        "file:///textedit/voicegroup.inc",
        text
    )
    #expect(synced == 1)

    let result = BridgeCallbackResult()
    let completed = textedit_voicegroup_service_complete(service, 0, Int32(text.count), { label, _, _, _, _, _, _, userData in
        let result = Unmanaged<BridgeCallbackResult>.fromOpaque(userData!).takeUnretainedValue()
        result.labels.append(String(cString: label!))
    }, Unmanaged.passUnretained(result).toOpaque())

    #expect(completed == 1)
    #expect(result.labels.isEmpty)
}
