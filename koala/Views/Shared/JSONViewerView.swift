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

    @State private var mode: ViewMode = .tree

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
        } else {
            rawText = String(data: data, encoding: .utf8) ?? "<binary data>"
            node = nil
        }
    }

    init(text: String) {
        rawText = text
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            node = JSONNode.build(from: obj)
        } else {
            node = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            contentView
        }
    }

    private var toolbar: some View {
        HStack {
            Picker("Mode", selection: $mode) {
                ForEach(ViewMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var contentView: some View {
        switch mode {
        case .tree:
            treeView
        case .raw:
            rawView
        }
    }

    @ViewBuilder
    private var treeView: some View {
        if let node {
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
        Text(key).foregroundStyle(.primary).fontWeight(.medium)
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
