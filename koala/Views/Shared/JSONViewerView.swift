import SwiftUI

// MARK: - JSONNode

indirect enum JSONNode: Identifiable {
    case object(id: UUID, key: String?, pairs: [(key: String, value: JSONNode)])
    case array(id: UUID, key: String?, items: [JSONNode])
    case string(id: UUID, key: String?, value: String)
    case number(id: UUID, key: String?, value: String)
    case bool(id: UUID, key: String?, value: Bool)
    case null(id: UUID, key: String?)

    var id: UUID {
        switch self {
        case .object(let id, _, _): return id
        case .array(let id, _, _): return id
        case .string(let id, _, _): return id
        case .number(let id, _, _): return id
        case .bool(let id, _, _): return id
        case .null(let id, _): return id
        }
    }

    static func build(from any: Any, key: String? = nil) -> JSONNode {
        let id = UUID()
        if let dict = any as? [String: Any] {
            let pairs = dict.map { (k, v) in (key: k, value: JSONNode.build(from: v, key: k)) }
                .sorted { $0.key < $1.key }
            return .object(id: id, key: key, pairs: pairs)
        } else if let arr = any as? [Any] {
            let items = arr.enumerated().map { i, v in JSONNode.build(from: v, key: "[\(i)]") }
            return .array(id: id, key: key, items: items)
        } else if let str = any as? String {
            return .string(id: id, key: key, value: str)
        } else if let num = any as? NSNumber {
            if num === kCFBooleanTrue || num === kCFBooleanFalse {
                return .bool(id: id, key: key, value: num.boolValue)
            }
            return .number(id: id, key: key, value: num.stringValue)
        } else {
            return .null(id: id, key: key)
        }
    }
}

// MARK: - JSONViewerView

struct JSONViewerView: View {
    private let rawText: String
    private let node: JSONNode?
    private let rawObject: Any?

    @State private var showRaw: Bool = false
    @State private var pathQuery: String = ""

    enum ViewMode: String, CaseIterable {
        case tree = "Tree"
        case raw = "Raw"
    }

    init(data: Data) {
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let prettyText = String(data: prettyData, encoding: .utf8) {
            rawText = prettyText
            node = JSONNode.build(from: obj)
            rawObject = obj
        } else {
            rawText = String(data: data, encoding: .utf8) ?? "<binary data>"
            node = nil
            rawObject = nil
        }
    }

    init(text: String) {
        rawText = text
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            node = JSONNode.build(from: obj)
            rawObject = obj
        } else {
            node = nil
            rawObject = nil
        }
    }

    /// Filtered nodes for a non-empty JSONPath query.
    /// `nil` → no query active. Empty `[]` → query ran but matched nothing.
    private var filteredNodes: [JSONNode]? {
        let trimmed = pathQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let rawObject else { return nil }
        guard let matches = JSONPathEvaluator.evaluate(trimmed, in: rawObject) else { return [] }
        return matches.enumerated().map { idx, value in
            // Use a synthetic key showing the match index for clarity.
            JSONNode.build(from: value, key: matches.count > 1 ? "match[\(idx)]" : nil)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if node != nil {
                searchBar
                Divider()
            }
            ZStack(alignment: .topTrailing) {
                Group {
                    if showRaw || node == nil {
                        rawView
                    } else {
                        treeView
                    }
                }
                // Tiny toggle button if JSON parsed — switch between tree and raw text
                if node != nil {
                    Button {
                        showRaw.toggle()
                    } label: {
                        Image(systemName: showRaw ? "list.bullet.indent" : "doc.plaintext")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(.background.tertiary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(showRaw ? "Show tree" : "Show raw text")
                    .padding(8)
                }
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("$.users[0].email — JSONPath filter", text: $pathQuery)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .disableAutocorrection(true)

            if !pathQuery.isEmpty {
                if let matches = filteredNodes, !matches.isEmpty {
                    Text("\(matches.count) match\(matches.count == 1 ? "" : "es")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("no match")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                Button {
                    pathQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear filter")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var treeView: some View {
        if let filtered = filteredNodes {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        Text("No matches for path.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filtered) { match in
                            JSONNodeView(node: match, depth: 0)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if let node {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    JSONNodeView(node: node, depth: 0)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            rawView
        }
    }

    private var rawView: some View {
        TextEditor(text: .constant(rawText))
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
    }
}

// MARK: - JSONNodeView (custom collapsible, no DisclosureGroup)

private struct JSONNodeView: View {
    let node: JSONNode
    let depth: Int
    @State private var isExpanded = true

    private let indentWidth: CGFloat = 14

    var body: some View {
        switch node {
        case .object(_, let key, let pairs):
            collapsibleBlock(
                key: key,
                bracketOpen: "{",
                bracketClose: "}",
                summary: "\(pairs.count) " + (pairs.count == 1 ? "item" : "items")
            ) {
                ForEach(pairs, id: \.key) { pair in
                    JSONNodeView(node: pair.value, depth: depth + 1)
                }
            }

        case .array(_, let key, let items):
            collapsibleBlock(
                key: key,
                bracketOpen: "[",
                bracketClose: "]",
                summary: "\(items.count) " + (items.count == 1 ? "item" : "items")
            ) {
                ForEach(items) { item in
                    JSONNodeView(node: item, depth: depth + 1)
                }
            }

        case .string(_, let key, let value):
            leafRow(key: key, valueText: "\"\(value)\"", color: .green)
        case .number(_, let key, let value):
            leafRow(key: key, valueText: value, color: .blue)
        case .bool(_, let key, let value):
            leafRow(key: key, valueText: value ? "true" : "false", color: .purple)
        case .null(_, let key):
            leafRow(key: key, valueText: "null", color: .secondary)
        }
    }

    @ViewBuilder
    private func collapsibleBlock<Content: View>(
        key: String?,
        bracketOpen: String,
        bracketClose: String,
        summary: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)

                    if let key {
                        keyText(key)
                        Text(":").foregroundStyle(.secondary)
                    }

                    if isExpanded {
                        Text(bracketOpen).foregroundStyle(.secondary)
                    } else {
                        Text("\(bracketOpen) \(summary) \(bracketClose)")
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(.system(.body, design: .monospaced))

            if isExpanded {
                content()
                    .padding(.leading, indentWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 0) {
                    Text(bracketClose).foregroundStyle(.secondary)
                }
                .font(.system(.body, design: .monospaced))
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func leafRow(key: String?, valueText: String, color: Color) -> some View {
        HStack(spacing: 4) {
            // empty chevron-slot for visual alignment with collapsible rows
            Spacer().frame(width: 10)

            if let key {
                keyText(key)
                Text(":").foregroundStyle(.secondary)
            }
            Text(valueText).foregroundStyle(color)
        }
        .font(.system(.body, design: .monospaced))
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyText(_ key: String) -> some View {
        // Distinct color for keys (cyan/teal) so they pop vs values.
        Text("\"\(key)\"")
            .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 0.95))
            .fontWeight(.medium)
    }
}

// MARK: - Preview

#Preview("JSONViewerView") {
    let sampleJSON = """
    {
        "id": 42,
        "name": "Koala",
        "active": true,
        "score": 99.5,
        "tags": ["swift", "macOS", "api-client"],
        "address": {
            "city": "Jakarta",
            "country": "ID"
        },
        "nullable": null
    }
    """.data(using: .utf8)!

    return VStack {
        JSONViewerView(data: sampleJSON)
            .frame(width: 480, height: 400)
    }
    .padding()
}
