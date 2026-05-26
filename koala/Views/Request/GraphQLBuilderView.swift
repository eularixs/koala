import SwiftUI

// MARK: - Selection Model

/// Path-keyed selection state for a field in the explorer tree.
/// Path = sequence of field names from root, e.g. ["users", "address", "city"].
private struct FieldSelection: Hashable {
    var selected: Bool = false
    /// arg name -> raw string value the user typed
    var args: [String: String] = [:]
}

private enum OperationKind: String, CaseIterable, Identifiable {
    case query, mutation
    var id: String { rawValue }
    var keyword: String { rawValue }
    var defaultName: String {
        switch self {
        case .query:    return "MyQuery"
        case .mutation: return "MyMutation"
        }
    }
}

// MARK: - GraphQLBuilderView

struct GraphQLBuilderView: View {
    @Binding var request: KoalaRequest

    @State private var introspector = GraphQLIntrospector()
    @State private var selections: [String: FieldSelection] = [:]
    @State private var expandedPaths: Set<String> = []
    @State private var operationKind: OperationKind = .query
    @State private var operationName: String = "MyQuery"
    @State private var manualEdit: Bool = false

    var body: some View {
        HSplitView {
            explorerPane
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 500, maxHeight: .infinity)

            queryPane
                .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)

            variablesPane
                .frame(minWidth: 200, idealWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Explorer Pane

    private var explorerPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            explorerHeader
            Divider()
            explorerBody
        }
    }

    private var explorerHeader: some View {
        HStack(spacing: 8) {
            Text("Explorer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Picker("", selection: $operationKind) {
                ForEach(OperationKind.allCases) { k in
                    Text(k.rawValue.capitalized).tag(k)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 140)
            .onChange(of: operationKind) { _, newK in
                if operationName.isEmpty || operationName == "MyQuery" || operationName == "MyMutation" {
                    operationName = newK.defaultName
                }
                regenerateQuery()
            }

            Button {
                Task { await runIntrospect() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Refresh schema (introspect endpoint)")
            .disabled(introspector.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var explorerBody: some View {
        if introspector.isLoading {
            loadingState
        } else if let err = introspector.lastError {
            errorState(err)
        } else if let schema = introspector.schema {
            schemaTree(schema: schema)
        } else {
            emptyState
        }
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Introspecting schema…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Introspection failed")
                .font(.caption.weight(.medium))
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button("Try Again") {
                Task { await runIntrospect() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No schema loaded")
                .font(.caption.weight(.medium))
            Text("Enter a URL above and click the refresh button to introspect.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button {
                Task { await runIntrospect() }
            } label: {
                Label("Introspect", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(request.url.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func schemaTree(schema: GraphQLSchema) -> some View {
        let root: GraphQLType? = operationKind == .query ? schema.queryRoot : schema.mutationRoot
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if let root, let fields = root.fields, !fields.isEmpty {
                    ForEach(fields) { field in
                        FieldRow(
                            field: field,
                            path: [field.name],
                            schema: schema,
                            selections: $selections,
                            expandedPaths: $expandedPaths,
                            onChange: regenerateQuery
                        )
                    }
                } else {
                    Text(operationKind == .query
                         ? "Schema has no Query root."
                         : "Schema has no Mutation root.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .padding(8)
        }
        .background(.background.secondary)
    }

    // MARK: - Query Pane

    private var queryPane: some View {
        let queryBinding = Binding<String>(
            get: {
                if case .graphql(let q, _) = request.body { return q }
                return ""
            },
            set: { newValue in
                manualEdit = true
                if case .graphql(_, let v) = request.body {
                    request.body = .graphql(query: newValue, variables: v)
                } else {
                    request.body = .graphql(query: newValue, variables: "")
                }
            }
        )

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Query")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("OperationName", text: $operationName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: 180)
                    .onChange(of: operationName) { _, _ in regenerateQuery() }
                Spacer()
                if manualEdit {
                    Button("Regenerate") {
                        manualEdit = false
                        regenerateQuery()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Discard manual edits and rebuild from selections")
                }
            }
            CodeEditorView(text: queryBinding, language: "graphql")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Variables Pane

    private var variablesPane: some View {
        let variablesBinding = Binding<String>(
            get: {
                if case .graphql(_, let v) = request.body { return v }
                return ""
            },
            set: { newValue in
                if case .graphql(let q, _) = request.body {
                    request.body = .graphql(query: q, variables: newValue)
                } else {
                    request.body = .graphql(query: "", variables: newValue)
                }
            }
        )

        return VStack(alignment: .leading, spacing: 4) {
            Text("Variables")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            CodeEditorView(text: variablesBinding, language: "json")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func runIntrospect() async {
        do {
            _ = try await introspector.introspect(url: request.url, headers: request.headers)
            // reset selection on new schema
            selections.removeAll()
            expandedPaths.removeAll()
            manualEdit = false
            regenerateQuery()
        } catch {
            // error already captured in introspector.lastError
        }
    }

    private func regenerateQuery() {
        guard !manualEdit else { return }
        guard let schema = introspector.schema else { return }
        let root: GraphQLType? = operationKind == .query ? schema.queryRoot : schema.mutationRoot
        guard let root, let rootFields = root.fields else { return }

        let generated = QueryGenerator.generate(
            operationKind: operationKind,
            operationName: operationName,
            rootFields: rootFields,
            schema: schema,
            selections: selections
        )

        let existingVars: String = {
            if case .graphql(_, let v) = request.body { return v }
            return ""
        }()
        request.body = .graphql(query: generated, variables: existingVars)
    }
}

// MARK: - FieldRow (recursive tree row)

private struct FieldRow: View {
    let field: GraphQLField
    let path: [String]
    let schema: GraphQLSchema
    @Binding var selections: [String: FieldSelection]
    @Binding var expandedPaths: Set<String>
    let onChange: () -> Void

    private var pathKey: String { path.joined(separator: ".") }

    private var selection: FieldSelection {
        selections[pathKey] ?? FieldSelection()
    }

    private var childType: GraphQLType? {
        let named = field.type.namedType
        guard let name = named.name else { return nil }
        return schema.type(named: name)
    }

    private var hasChildren: Bool {
        guard let t = childType, let fs = t.fields else { return false }
        return !fs.isEmpty
    }

    private var isExpanded: Bool {
        expandedPaths.contains(pathKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if selection.selected && !field.args.isEmpty {
                argsBlock
            }
            if isExpanded, let t = childType, let subFields = t.fields {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(subFields) { sub in
                        FieldRow(
                            field: sub,
                            path: path + [sub.name],
                            schema: schema,
                            selections: $selections,
                            expandedPaths: $expandedPaths,
                            onChange: onChange
                        )
                    }
                }
                .padding(.leading, 16)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            disclosureButton
            checkbox
            Text(field.name)
                .font(.system(.caption, design: .monospaced))
            Text(field.type.displayString)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var disclosureButton: some View {
        if hasChildren {
            Button {
                if isExpanded { expandedPaths.remove(pathKey) }
                else { expandedPaths.insert(pathKey) }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
        } else {
            Spacer().frame(width: 12)
        }
    }

    private var checkbox: some View {
        let binding = Binding<Bool>(
            get: { selection.selected },
            set: { newVal in
                var sel = selections[pathKey] ?? FieldSelection()
                sel.selected = newVal
                selections[pathKey] = sel
                if newVal && hasChildren {
                    expandedPaths.insert(pathKey)
                }
                onChange()
            }
        )
        return Toggle("", isOn: binding)
            .toggleStyle(.checkbox)
            .labelsHidden()
    }

    private var argsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(field.args) { arg in
                argRow(arg)
            }
        }
        .padding(.leading, 32)
        .padding(.vertical, 4)
        .padding(.trailing, 8)
    }

    @ViewBuilder
    private func argRow(_ arg: GraphQLInputValue) -> some View {
        let binding = Binding<String>(
            get: { selections[pathKey]?.args[arg.name] ?? "" },
            set: { newVal in
                var sel = selections[pathKey] ?? FieldSelection()
                sel.args[arg.name] = newVal
                selections[pathKey] = sel
                onChange()
            }
        )

        HStack(spacing: 6) {
            Text(arg.name + ":")
                .font(.caption2)
                .foregroundStyle(.secondary)
            argInput(arg: arg, binding: binding)
            Text(arg.type.displayString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func argInput(arg: GraphQLInputValue, binding: Binding<String>) -> some View {
        let named = arg.type.namedType
        if named.kind == .enumKind,
           let typeName = named.name,
           let enumType = schema.type(named: typeName),
           let values = enumType.enumValues, !values.isEmpty
        {
            Menu {
                Button("(none)") { binding.wrappedValue = "" }
                ForEach(values) { v in
                    Button(v.name) { binding.wrappedValue = v.name }
                }
            } label: {
                Text(binding.wrappedValue.isEmpty ? "select…" : binding.wrappedValue)
                    .font(.caption2)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            TextField(arg.defaultValue ?? "value", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
                .frame(maxWidth: 140)
        }
    }
}

// MARK: - QueryGenerator

private enum QueryGenerator {

    static func generate(
        operationKind: OperationKind,
        operationName: String,
        rootFields: [GraphQLField],
        schema: GraphQLSchema,
        selections: [String: FieldSelection]
    ) -> String {
        var lines: [String] = []
        let name = operationName.trimmingCharacters(in: .whitespaces)
        let header: String = {
            if name.isEmpty { return "\(operationKind.keyword) {" }
            return "\(operationKind.keyword) \(name) {"
        }()
        lines.append(header)

        for field in rootFields {
            let path = [field.name]
            if let block = renderField(field: field, path: path, schema: schema,
                                       selections: selections, indent: 1) {
                lines.append(block)
            }
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// Returns indented block for a field if it (or any descendant) is selected.
    private static func renderField(
        field: GraphQLField,
        path: [String],
        schema: GraphQLSchema,
        selections: [String: FieldSelection],
        indent: Int
    ) -> String? {
        let pathKey = path.joined(separator: ".")
        let sel = selections[pathKey] ?? FieldSelection()

        // Build child blocks first
        var childBlocks: [String] = []
        var childType: GraphQLType? = nil
        if let typeName = field.type.namedType.name {
            childType = schema.type(named: typeName)
        }
        if let subFields = childType?.fields {
            for sub in subFields {
                if let block = renderField(field: sub, path: path + [sub.name],
                                           schema: schema, selections: selections,
                                           indent: indent + 1) {
                    childBlocks.append(block)
                }
            }
        }

        // Only emit field if user selected it or any descendant produced output
        guard sel.selected || !childBlocks.isEmpty else { return nil }

        let pad = String(repeating: "  ", count: indent)
        let argsString = renderArgs(field: field, selection: sel)

        if childBlocks.isEmpty {
            return "\(pad)\(field.name)\(argsString)"
        } else {
            var out = "\(pad)\(field.name)\(argsString) {\n"
            out += childBlocks.joined(separator: "\n")
            out += "\n\(pad)}"
            return out
        }
    }

    private static func renderArgs(field: GraphQLField, selection: FieldSelection) -> String {
        let present = field.args.compactMap { arg -> (String, String)? in
            guard let raw = selection.args[arg.name],
                  !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (arg.name, formatArgValue(raw, type: arg.type))
        }
        guard !present.isEmpty else { return "" }
        let parts = present.map { "\($0.0): \($0.1)" }
        return "(" + parts.joined(separator: ", ") + ")"
    }

    /// Best-effort argument literal formatting. Quotes strings, leaves numbers/bools/enums bare.
    private static func formatArgValue(_ raw: String, type: GraphQLTypeRef) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // Variable reference passes through.
        if trimmed.hasPrefix("$") { return trimmed }

        let named = type.namedType
        let typeName = named.name ?? ""

        switch named.kind {
        case .enumKind:
            return trimmed
        case .scalar:
            switch typeName {
            case "Int", "Float":
                if Double(trimmed) != nil { return trimmed }
                return jsonQuoted(trimmed)
            case "Boolean":
                if trimmed == "true" || trimmed == "false" { return trimmed }
                return jsonQuoted(trimmed)
            case "ID", "String":
                return jsonQuoted(trimmed)
            default:
                // Unknown scalar — quote unless it looks like number/bool/object literal.
                if trimmed == "true" || trimmed == "false" { return trimmed }
                if Double(trimmed) != nil { return trimmed }
                if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return trimmed }
                return jsonQuoted(trimmed)
            }
        default:
            // Input objects / lists — pass through verbatim, user is responsible.
            return trimmed
        }
    }

    private static func jsonQuoted(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

// MARK: - Preview

#Preview("GraphQLBuilderView — Empty") {
    @Previewable @State var request = KoalaRequest(
        url: "https://example.com/graphql",
        body: .graphql(query: "", variables: "")
    )
    return GraphQLBuilderView(request: $request)
        .frame(width: 900, height: 500)
}
