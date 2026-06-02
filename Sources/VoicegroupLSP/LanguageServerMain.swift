import Foundation
import VoicegroupCore

public enum LanguageServerMain {
    public static func run() {
        StdioLanguageServer().run()
    }
}

/// Minimal stdio JSON-RPC server for VS Code's LanguageClient. It implements
/// the LSP methods needed for first use and keeps state in memory because VS
/// Code sends full document text for open files.
final class StdioLanguageServer {
    private var workspace = WorkspaceIndex()
    private var documents: [String: String] = [:]

    func run() {
        while let message = readMessage() {
            handle(message)
        }
    }

    private func handle(_ message: [String: Any]) {
        guard let method = message["method"] as? String else { return }
        let id = message["id"]
        switch method {
        case "initialize":
            if let params = message["params"] as? [String: Any],
               let rootURI = params["rootUri"] as? String,
               let url = URL(string: rootURI) {
                workspace = WorkspaceIndex.load(projectRoot: url)
            }
            respond(id: id, result: [
                "capabilities": [
                    "textDocumentSync": 1,
                    "completionProvider": ["triggerCharacters": ["_", ",", " "]],
                    "hoverProvider": true,
                    "definitionProvider": true
                ]
            ])
        case "textDocument/didOpen", "textDocument/didChange":
            updateDocument(from: message)
        case "textDocument/completion":
            respond(id: id, result: completionResult(from: message))
        case "textDocument/hover":
            respond(id: id, result: hoverResult(from: message) as Any)
        case "shutdown":
            respond(id: id, result: NSNull())
        case "exit":
            Foundation.exit(0)
        default:
            if id != nil {
                respond(id: id, result: NSNull())
            }
        }
    }

    private func updateDocument(from message: [String: Any]) {
        guard let params = message["params"] as? [String: Any] else { return }
        if let textDocument = params["textDocument"] as? [String: Any],
           let uri = textDocument["uri"] as? String,
           let text = textDocument["text"] as? String {
            documents[uri] = text
            publishDiagnostics(uri: uri, text: text)
            return
        }
        if let textDocument = params["textDocument"] as? [String: Any],
           let uri = textDocument["uri"] as? String,
           let changes = params["contentChanges"] as? [[String: Any]],
           let text = changes.last?["text"] as? String {
            documents[uri] = text
            publishDiagnostics(uri: uri, text: text)
        }
    }

    private func completionResult(from message: [String: Any]) -> [[String: Any]] {
        guard let (uri, line, character) = documentPosition(from: message),
              let text = documents[uri] else { return [] }
        return LanguageService(workspace: workspace)
            .completions(text: text, line: line, character: character)
            .map { ["label": $0.label, "detail": $0.detail, "kind": 3] }
    }

    private func hoverResult(from message: [String: Any]) -> [String: Any]? {
        guard let (uri, line, character) = documentPosition(from: message),
              let text = documents[uri],
              let hover = LanguageService(workspace: workspace).hover(text: text, line: line, character: character) else {
            return nil
        }
        return ["contents": ["kind": "markdown", "value": hover]]
    }

    private func publishDiagnostics(uri: String, text: String) {
        let diagnostics = LanguageService(workspace: workspace).diagnostics(text: text, uri: uri)
        notify(method: "textDocument/publishDiagnostics", params: [
            "uri": uri,
            "diagnostics": diagnostics.map { diagnostic in
                [
                    "range": lspRange(diagnostic.range),
                    "severity": diagnostic.severity.rawValue,
                    "code": diagnostic.code,
                    "message": diagnostic.message
                ]
            }
        ])
    }

    private func documentPosition(from message: [String: Any]) -> (String, Int, Int)? {
        guard let params = message["params"] as? [String: Any],
              let textDocument = params["textDocument"] as? [String: Any],
              let uri = textDocument["uri"] as? String,
              let position = params["position"] as? [String: Any],
              let line = position["line"] as? Int,
              let character = position["character"] as? Int else {
            return nil
        }
        return (uri, line, character)
    }

    private func lspRange(_ range: SourceRange) -> [String: Any] {
        [
            "start": ["line": range.start.line, "character": range.start.character],
            "end": ["line": range.end.line, "character": range.end.character]
        ]
    }

    private func respond(id: Any?, result: Any) {
        guard let id else { return }
        write(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func notify(method: String, params: [String: Any]) {
        write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func readMessage() -> [String: Any]? {
        LSPMessageFraming.readMessage(from: .standardInput)
    }

    private func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let header = "Content-Length: \(data.count)\r\n\r\n"
        FileHandle.standardOutput.write(Data(header.utf8))
        FileHandle.standardOutput.write(data)
    }
}
