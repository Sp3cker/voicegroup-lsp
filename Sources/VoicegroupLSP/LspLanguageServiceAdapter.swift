import Foundation
import VoicegroupCore

public struct LspLanguageServiceAdapter {
    public var service: VoicegroupLanguageService

    public init(workspace: WorkspaceIndex) {
        self.service = VoicegroupLanguageService(workspace: workspace)
    }

    public func completionResult(text: String, line: Int, character: Int) -> [[String: Any]] {
        service.completions(text: text, line: line, character: character)
            .map { ["label": $0.label, "detail": $0.detail, "kind": 3] }
    }

    public func hoverResult(text: String, line: Int, character: Int) -> [String: Any]? {
        guard let hover = service.hover(text: text, line: line, character: character) else {
            return nil
        }
        return ["contents": ["kind": "markdown", "value": hover]]
    }

    public func diagnosticsParams(uri: String, text: String) -> [String: Any] {
        let diagnostics = service.diagnostics(text: text, uri: uri)
        return [
            "uri": uri,
            "diagnostics": diagnostics.map { diagnostic in
                [
                    "range": lspRange(diagnostic.range),
                    "severity": diagnostic.severity.rawValue,
                    "code": diagnostic.code,
                    "message": diagnostic.message
                ]
            }
        ]
    }

    private func lspRange(_ range: SourceRange) -> [String: Any] {
        [
            "start": ["line": range.start.line, "character": range.start.character],
            "end": ["line": range.end.line, "character": range.end.character]
        ]
    }
}
