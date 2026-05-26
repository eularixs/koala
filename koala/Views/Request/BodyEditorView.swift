import SwiftUI
import UniformTypeIdentifiers

// MARK: - BodyTypeTag

private enum BodyTypeTag: String, CaseIterable, Identifiable {
    case none = "None"
    case json = "JSON"
    case formURLEncoded = "Form"
    case multipart = "Multipart"
    case raw = "Raw"
    case graphql = "GraphQL"
    case binary = "Binary"

    var id: String { rawValue }
}

// MARK: - BodyEditorView

struct BodyEditorView: View {
    @Binding var request: KoalaRequest

    @State private var selectedTag: BodyTypeTag = .none
    @State private var showFilePicker: Bool = false
    @State private var multipartFilePickerIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            typePicker
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider()

            bodyContent
                .padding(12)
        }
        .onAppear { selectedTag = tag(for: request.body) }
        .onChange(of: selectedTag) { _, newTag in switchBody(to: newTag) }
    }

    // MARK: - Picker

    private var typePicker: some View {
        Picker("Body Type", selection: $selectedTag) {
            ForEach(BodyTypeTag.allCases) { tag in
                Text(tag.rawValue).tag(tag)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Content

    @ViewBuilder
    private var bodyContent: some View {
        switch request.body {
        case .none:
            noneView

        case .json(let text):
            jsonBinding(text: text)

        case .formURLEncoded:
            KeyValueEditorView(items: formBinding)

        case .multipart(let items):
            multipartEditor(items: items)

        case .raw(let content, let contentType):
            rawEditor(content: content, contentType: contentType)

        case .graphql(let query, let variables):
            graphqlEditor(query: query, variables: variables)

        case .binary(let url):
            binaryEditor(url: url)
        }
    }

    // MARK: - None

    private var noneView: some View {
        Text("No body")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
    }

    // MARK: - JSON

    @ViewBuilder
    private func jsonBinding(text: String) -> some View {
        let binding = Binding<String>(
            get: {
                if case .json(let s) = request.body { return s }
                return text
            },
            set: { request.body = .json($0) }
        )
        CodeEditorView(text: binding, language: "json")
    }

    // MARK: - Form URL-Encoded

    private var formBinding: Binding<[KeyValuePair]> {
        Binding<[KeyValuePair]>(
            get: {
                if case .formURLEncoded(let pairs) = request.body { return pairs }
                return []
            },
            set: { request.body = .formURLEncoded($0) }
        )
    }

    // MARK: - Multipart

    @ViewBuilder
    private func multipartEditor(items: [MultipartItem]) -> some View {
        MultipartTableView(
            items: multipartBinding,
            showFilePicker: $showFilePicker,
            filePickerIndex: $multipartFilePickerIndex
        )
    }

    private var multipartBinding: Binding<[MultipartItem]> {
        Binding<[MultipartItem]>(
            get: {
                if case .multipart(let items) = request.body { return items }
                return []
            },
            set: { request.body = .multipart($0) }
        )
    }

    // MARK: - Raw

    @ViewBuilder
    private func rawEditor(content: String, contentType: String) -> some View {
        let contentBinding = Binding<String>(
            get: { if case .raw(let c, _) = request.body { return c } else { return content } },
            set: { newContent in
                if case .raw(_, let ct) = request.body { request.body = .raw(content: newContent, contentType: ct) }
            }
        )
        let typeBinding = Binding<String>(
            get: { if case .raw(_, let ct) = request.body { return ct } else { return contentType } },
            set: { newType in
                if case .raw(let c, _) = request.body { request.body = .raw(content: c, contentType: newType) }
            }
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Content-Type:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("text/plain", text: typeBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: 240)
            }
            CodeEditorView(text: contentBinding, language: "text")
        }
    }

    // MARK: - GraphQL

    @ViewBuilder
    private func graphqlEditor(query: String, variables: String) -> some View {
        let queryBinding = Binding<String>(
            get: { if case .graphql(let q, _) = request.body { return q } else { return query } },
            set: { newQ in
                if case .graphql(_, let v) = request.body { request.body = .graphql(query: newQ, variables: v) }
            }
        )
        let variablesBinding = Binding<String>(
            get: { if case .graphql(_, let v) = request.body { return v } else { return variables } },
            set: { newV in
                if case .graphql(let q, _) = request.body { request.body = .graphql(query: q, variables: newV) }
            }
        )

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Query")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                CodeEditorView(text: queryBinding, language: "graphql")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Variables")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                CodeEditorView(text: variablesBinding, language: "json")
            }
        }
    }

    // MARK: - Binary

    @ViewBuilder
    private func binaryEditor(url: URL?) -> some View {
        HStack(spacing: 12) {
            Button("Choose File...") {
                showFilePicker = true
            }
            .buttonStyle(.bordered)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.data]
            ) { result in
                if case .success(let picked) = result {
                    request.body = .binary(picked)
                }
            }

            if let url {
                Text(url.lastPathComponent)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No file selected")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 40, alignment: .leading)
    }

    // MARK: - Helpers

    private func tag(for body: RequestBody) -> BodyTypeTag {
        switch body {
        case .none:           return .none
        case .json:           return .json
        case .formURLEncoded: return .formURLEncoded
        case .multipart:      return .multipart
        case .raw:            return .raw
        case .graphql:        return .graphql
        case .binary:         return .binary
        }
    }

    private func switchBody(to tag: BodyTypeTag) {
        switch tag {
        case .none:           request.body = .none
        case .json:           if case .json = request.body { return }; request.body = .json("")
        case .formURLEncoded: if case .formURLEncoded = request.body { return }; request.body = .formURLEncoded([])
        case .multipart:      if case .multipart = request.body { return }; request.body = .multipart([])
        case .raw:            if case .raw = request.body { return }; request.body = .raw(content: "", contentType: "text/plain")
        case .graphql:        if case .graphql = request.body { return }; request.body = .graphql(query: "", variables: "")
        case .binary:         if case .binary = request.body { return }; request.body = .binary(URL(fileURLWithPath: ""))
        }
    }
}

// MARK: - MultipartTableView

private struct MultipartTableView: View {
    @Binding var items: [MultipartItem]
    @Binding var showFilePicker: Bool
    @Binding var filePickerIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                MultipartRowView(
                    item: rowBinding(index: index),
                    onDelete: { deleteItem(at: index) },
                    onPickFile: { filePickerIndex = index; showFilePicker = true },
                    onKeyChange: { handleKeyChange(for: item) }
                )
                Divider().padding(.leading, 8)
            }
            addButton
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data]) { result in
            handleFilePick(result: result)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("").frame(width: 24)
            Spacer().frame(width: 8)
            Text("Key").frame(maxWidth: .infinity, alignment: .leading)
            columnDivider
            Text("Value").frame(maxWidth: .infinity, alignment: .leading)
            columnDivider
            Text("Type").frame(width: 60, alignment: .leading)
            Spacer().frame(width: 28)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.05))
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 0.5)
            .frame(maxHeight: .infinity)
    }

    private var addButton: some View {
        Button {
            items.append(MultipartItem())
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                Text("Add")
            }
            .font(.caption)
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowBinding(index: Int) -> Binding<MultipartItem> {
        Binding<MultipartItem>(
            get: { items.indices.contains(index) ? items[index] : .empty },
            set: { if items.indices.contains(index) { items[index] = $0 } }
        )
    }

    private func deleteItem(at index: Int) {
        items.remove(at: index)
    }

    private func handleKeyChange(for item: MultipartItem) {
        guard let last = items.last, last.id == item.id, !item.key.isEmpty else { return }
        items.append(MultipartItem())
    }

    private func handleFilePick(result: Result<URL, Error>) {
        guard let idx = filePickerIndex,
              case .success(let url) = result,
              items.indices.contains(idx) else { return }
        items[idx].fileURL = url
        items[idx].type = .file
        filePickerIndex = nil
    }
}

// MARK: - MultipartRowView

private struct MultipartRowView: View {
    @Binding var item: MultipartItem
    let onDelete: () -> Void
    let onPickFile: () -> Void
    let onKeyChange: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Toggle("", isOn: $item.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 24)

            Spacer().frame(width: 8)

            TextField("Key", text: $item.key)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)
                .onChange(of: item.key) { _, _ in onKeyChange() }

            rowColumnDivider

            valueCell
                .frame(maxWidth: .infinity)

            rowColumnDivider

            typePicker
                .frame(width: 60)

            deleteButton.frame(width: 28)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .opacity(item.isEnabled ? 1.0 : 0.5)
    }

    private var rowColumnDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 0.5)
            .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var valueCell: some View {
        if item.type == .text {
            TextField("Value", text: $item.value)
                .textFieldStyle(.plain)
        } else {
            Button(action: onPickFile) {
                Text(item.fileURL?.lastPathComponent ?? "Choose file...")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(item.fileURL == nil ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var typePicker: some View {
        Menu {
            ForEach(MultipartItemType.allCases) { t in
                Button(t.displayName) { switchType(to: t) }
            }
        } label: {
            Text(item.type.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Delete row")
    }

    private func switchType(to newType: MultipartItemType) {
        item.type = newType
        if newType == .file { item.value = "" }
        if newType == .text { item.fileURL = nil }
    }
}

// MARK: - Preview

#Preview("BodyEditorView — JSON") {
    @Previewable @State var request = KoalaRequest(body: .json("{\"key\": \"value\"}"))
    return BodyEditorView(request: $request).frame(width: 600).padding()
}

#Preview("BodyEditorView — None") {
    @Previewable @State var request = KoalaRequest()
    return BodyEditorView(request: $request).frame(width: 600).padding()
}
