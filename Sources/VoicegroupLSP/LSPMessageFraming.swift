import Foundation

/// LSP uses HTTP-like headers and a JSON body. VS Code sends CRLF-delimited
/// headers, so this parser works at the byte level instead of using readLine(),
/// which can leave carriage returns in surprising places.
public enum LSPMessageFraming {
    public static func decode(_ data: Data) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        var cursor = data.startIndex

        while cursor < data.endIndex {
            guard let headerEnd = findHeaderEnd(in: data, from: cursor) else { break }
            let headerData = data[cursor..<headerEnd.lowerBound]
            guard let headerText = String(data: headerData, encoding: .utf8),
                  let contentLength = contentLength(from: headerText) else {
                break
            }
            let bodyStart = headerEnd.upperBound
            let bodyEnd = bodyStart + contentLength
            guard bodyEnd <= data.endIndex else { break }
            let body = data[bodyStart..<bodyEnd]
            if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                messages.append(object)
            }
            cursor = bodyEnd
        }

        return messages
    }

    public static func readMessage(from input: FileHandle) -> [String: Any]? {
        var buffer = Data()
        while true {
            let chunk = input.readData(ofLength: 1)
            guard !chunk.isEmpty else { return nil }
            buffer.append(chunk)
            guard let headerEnd = findHeaderEnd(in: buffer, from: buffer.startIndex) else { continue }
            let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
            guard let headerText = String(data: headerData, encoding: .utf8),
                  let length = contentLength(from: headerText) else {
                return nil
            }
            let alreadyReadBodyCount = buffer.distance(from: headerEnd.upperBound, to: buffer.endIndex)
            var body = Data(buffer[headerEnd.upperBound..<buffer.endIndex])
            if alreadyReadBodyCount < length {
                body.append(input.readData(ofLength: length - alreadyReadBodyCount))
            }
            guard body.count >= length else { return nil }
            return try? JSONSerialization.jsonObject(with: body.prefix(length)) as? [String: Any]
        }
    }

    private static func contentLength(from headerText: String) -> Int? {
        for line in headerText.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2, parts[0].caseInsensitiveCompare("Content-Length") == .orderedSame {
                return Int(parts[1])
            }
        }
        return nil
    }

    private static func findHeaderEnd(in data: Data, from start: Data.Index) -> Range<Data.Index>? {
        let crlf = Data([13, 10, 13, 10])
        if let range = data[start...].range(of: crlf) {
            return range
        }
        let lf = Data([10, 10])
        return data[start...].range(of: lf)
    }
}
