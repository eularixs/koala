import Foundation

final class MarkdownExporter {

    static func export(_ collection: KoalaCollection) throws -> String {
        var lines: [String] = []
        lines.append("# \(collection.name)")
        lines.append("")
        for item in collection.items {
            appendItem(item, level: 2, lines: &lines)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private helpers

    private static func appendItem(_ item: CollectionItem, level: Int, lines: inout [String]) {
        switch item {
        case .folder(let folder):
            lines.append("\(heading(level)) \(folder.name)")
            lines.append("")
            for child in folder.items {
                appendItem(child, level: level + 1, lines: &lines)
            }
        case .request(let req):
            appendRequest(req, level: level, lines: &lines)
        }
    }

    private static func appendRequest(_ req: KoalaRequest, level: Int, lines: inout [String]) {
        let path = urlPath(req.url)
        lines.append("\(heading(level)) \(req.method.rawValue) \(path)")
        lines.append("")

        if !req.headers.isEmpty {
            lines.append("**Headers**")
            for h in req.headers where h.isEnabled {
                let desc = h.description.isEmpty ? "" : " (\(h.description))"
                lines.append("- `\(h.key)`: `\(h.value)`\(desc)")
            }
            lines.append("")
        }

        if !req.queryParams.isEmpty {
            lines.append("**Query Parameters**")
            for q in req.queryParams where q.isEnabled {
                let desc = q.description.isEmpty ? "" : " (\(q.description))"
                lines.append("- `\(q.key)`: `\(q.value)`\(desc)")
            }
            lines.append("")
        }

        appendBody(req.body, lines: &lines)
        lines.append("---")
        lines.append("")
    }

    private static func appendBody(_ body: RequestBody, lines: inout [String]) {
        switch body {
        case .none: return
        case .json(let content):
            lines.append("**Body**")
            lines.append("```json")
            lines.append(content)
            lines.append("```")
            lines.append("")
        case .raw(let content, let ct):
            lines.append("**Body** (`\(ct)`)")
            lines.append("```")
            lines.append(content)
            lines.append("```")
            lines.append("")
        case .formURLEncoded(let pairs):
            lines.append("**Body** (form-urlencoded)")
            for p in pairs where p.isEnabled {
                lines.append("- `\(p.key)`: `\(p.value)`")
            }
            lines.append("")
        case .multipart(let items):
            lines.append("**Body** (multipart/form-data)")
            for item in items where item.isEnabled {
                lines.append("- `\(item.key)`: `\(item.value)` [\(item.type.rawValue)]")
            }
            lines.append("")
        case .graphql(let query, let variables):
            lines.append("**Body** (GraphQL)")
            lines.append("```graphql")
            lines.append(query)
            lines.append("```")
            if !variables.isEmpty && variables != "{}" {
                lines.append("*Variables:*")
                lines.append("```json")
                lines.append(variables)
                lines.append("```")
            }
            lines.append("")
        case .binary:
            lines.append("**Body**: Binary file")
            lines.append("")
        }
    }

    private static func heading(_ level: Int) -> String {
        String(repeating: "#", count: min(max(level, 1), 6))
    }

    private static func urlPath(_ rawURL: String) -> String {
        guard let url = URL(string: rawURL) else { return rawURL }
        let path = url.path
        return path.isEmpty ? rawURL : path
    }
}
