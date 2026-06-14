import Foundation
import VoicegroupCore

public typealias VoicegroupBridgeCompletionCallback = @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafeMutableRawPointer?
) -> Void

public typealias VoicegroupBridgeHoverCallback = @convention(c) (
    UnsafePointer<CChar>?,
    UnsafeMutableRawPointer?
) -> Void

private final class VoicegroupBridgeService {
    private var languageService: VoicegroupLanguageService
    private var documentText: String?

    init?(projectRoot: String?) {
        if let projectRoot, !projectRoot.isEmpty {
            guard let workspace = Self.loadWorkspace(projectRoot: projectRoot) else { return nil }
            languageService = VoicegroupLanguageService(workspace: workspace)
        } else {
            languageService = VoicegroupLanguageService(workspace: WorkspaceIndex())
        }
    }

    func setProjectRoot(_ projectRoot: String) -> Bool {
        guard let workspace = Self.loadWorkspace(projectRoot: projectRoot) else { return false }
        languageService = VoicegroupLanguageService(workspace: workspace)
        return true
    }

    func syncDocument(uri: String, text: String) -> Bool {
        guard !uri.isEmpty else { return false }
        documentText = text
        return true
    }

    func completions(line: Int, character: Int) -> [VoicegroupCompletionItem]? {
        guard let text = documentText else { return nil }
        return languageService.completions(text: text, line: line, character: character)
    }

    func hover(line: Int, character: Int) -> String? {
        guard let text = documentText else { return nil }
        return languageService.hover(text: text, line: line, character: character)
    }

    private static func loadWorkspace(projectRoot: String) -> WorkspaceIndex? {
        let root = URL(fileURLWithPath: projectRoot)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.appending(path: "sound").path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return WorkspaceIndex.load(projectRoot: root)
    }
}

@_cdecl("textedit_voicegroup_service_create")
public func textedit_voicegroup_service_create(_ projectRoot: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let service = VoicegroupBridgeService(projectRoot: projectRoot.map(String.init(cString:))) else {
        return nil
    }
    return Unmanaged.passRetained(service).toOpaque()
}

@_cdecl("textedit_voicegroup_service_destroy")
public func textedit_voicegroup_service_destroy(_ service: UnsafeMutableRawPointer?) {
    guard let service else { return }
    Unmanaged<VoicegroupBridgeService>.fromOpaque(service).release()
}

@_cdecl("textedit_voicegroup_service_set_project_root")
public func textedit_voicegroup_service_set_project_root(
    _ service: UnsafeMutableRawPointer?,
    _ projectRoot: UnsafePointer<CChar>?
) -> Int32 {
    guard let service = bridgeService(from: service), let projectRoot else { return 0 }
    return service.setProjectRoot(String(cString: projectRoot)) ? 1 : 0
}

@_cdecl("textedit_voicegroup_service_sync_document")
public func textedit_voicegroup_service_sync_document(
    _ service: UnsafeMutableRawPointer?,
    _ uri: UnsafePointer<CChar>?,
    _ text: UnsafePointer<CChar>?
) -> Int32 {
    guard let service = bridgeService(from: service), let uri, let text else { return 0 }
    return service.syncDocument(uri: String(cString: uri), text: String(cString: text)) ? 1 : 0
}

@_cdecl("textedit_voicegroup_service_complete")
public func textedit_voicegroup_service_complete(
    _ service: UnsafeMutableRawPointer?,
    _ line: Int32,
    _ character: Int32,
    _ callback: VoicegroupBridgeCompletionCallback?,
    _ userData: UnsafeMutableRawPointer?
) -> Int32 {
    guard let service = bridgeService(from: service), let callback else { return 0 }
    guard let completions = service.completions(line: Int(line), character: Int(character)) else { return 0 }

    for completion in completions {
        completion.label.withCString { label in
            completion.detail.withCString { detail in
                callback(label, detail, userData)
            }
        }
    }
    return 1
}

@_cdecl("textedit_voicegroup_service_hover")
public func textedit_voicegroup_service_hover(
    _ service: UnsafeMutableRawPointer?,
    _ line: Int32,
    _ character: Int32,
    _ callback: VoicegroupBridgeHoverCallback?,
    _ userData: UnsafeMutableRawPointer?
) -> Int32 {
    guard let service = bridgeService(from: service), let callback else { return 0 }
    guard let hover = service.hover(line: Int(line), character: Int(character)) else { return 1 }
    hover.withCString { text in
        callback(text, userData)
    }
    return 1
}

private func bridgeService(from handle: UnsafeMutableRawPointer?) -> VoicegroupBridgeService? {
    guard let handle else { return nil }
    return Unmanaged<VoicegroupBridgeService>.fromOpaque(handle).takeUnretainedValue()
}
