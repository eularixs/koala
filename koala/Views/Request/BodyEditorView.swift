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
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                MultipartRowView(
                    item: itemBinding(index: index),
                    onDelete: { deleteMultipartItem(at: index) },
                    onPickFile: { multipartFilePickerIndex = index; showFilePicker = true }
                )
            }

            Button {
                appendMultipartItem()
            } label: {
                Label("Add Field", systemImage: "plus")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data]
        ) { result in
            handleMultipartFilePick(result: result)
        }
    }

    private func itemBinding(index: Int) -> Binding<MultipartItem> {
        Binding<MultipartItem>(
            get: {
                if case .multipart(let items) = request.body, items.indices.contains(index) {
                    return items[index]
                }
                return MultipartItem.empty
            },
            set: { newItem in
                if case .multipart(var items) = request.body, items.indices.contains(index) {
                    items[index] = newItem
                    request.body = .multipart(items)
                }
            }
        )
    }

    private func appendMultipartItem() {
        if case .multipart(var items) = request.body {
            items.append(MultipartItem())
            request.body = .multipart(items)
        }
    }

    private func deleteMultipartItem(at index: Int) {
        if case .multipart(var items) = request.body {
            items.remove(at: index)
            request.body = .multipart(items)
        }
    }

    private func handleMultipartFilePick(result: Result<URL, Error>) {
        guard let idx = multipartFilePickerIndex,
              case .success(let url) = result,
              case .multipart(var items) = request.body,
              items.indices.contains(idx) else { return }
        items[idx].fileURL = url
        items[idx].type = .file
        request.body = .multipart(items)
        multipartFilePickerIndex = nil
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

// MARK: - MultipartRowView

private struct MultipartRowView: View {
    @Binding var item: MultipartItem
    let onDelete: () -> Void
    let onPickFile: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Key", text: $item.key)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            Picker("Type", selection: $item.type) {
                ForEach(MultipartItemType.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .labelsHidden()
            .fixedSize()

            if item.type == .text {
                TextField("Value", text: $item.value)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
            } else {
                Button(action: onPickFile) {
                    Label(
                        item.fileURL?.lastPathComponent ?? "Choose...",
                        systemImage: "doc"
                    )
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
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
