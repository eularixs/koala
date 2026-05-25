import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - ResponseView

struct ResponseView: View {
    let response: KoalaResponse?
    let curlCommand: String
    var onSaveResponse: (() -> Void)? = nil

    @State private var selectedTab: ResponseTab = .body
    @State private var bodySubTab: BodyTab = .pretty
    @State private var showFileExporter: Bool = false

    var body: some View {
        Group {
            if let response {
                VStack(spacing: 0) {
                    topBar(response: response)
                    Divider()
                    tabBar
                    Divider()
                    tabContent(response: response)
                }
            } else {
                emptyState
            }
        }
    }

    // MARK: - Top Bar

    private func topBar(response: KoalaResponse) -> some View {
        HStack(spacing: 10) {
            StatusBadgeView(statusCode: response.statusCode)

            Text("\(response.durationMs) ms")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.secondary)

            Text(formattedSize(response.sizeBytes))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                copyCurlToClipboard()
            } label: {
                Label("Copy as cURL", systemImage: "doc.on.clipboard")
                    .font(.caption)
            }
            .buttonStyle(.bordered)

            Button {
                showFileExporter = true
                onSaveResponse?()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .fileExporter(
                isPresented: $showFileExporter,
                document: ResponseDocument(data: response.body),
                contentType: .data,
                defaultFilename: "response"
            ) { _ in }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack {
            Picker("Response Tab", selection: $selectedTab) {
                ForEach(ResponseTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(response: KoalaResponse) -> some View {
        switch selectedTab {
        case .body:    bodyTab(response: response)
        case .headers: headersTab(response: response)
        case .cookies: cookiesTab(response: response)
        case .timeline: timelineTab(response: response)
        }
    }

    // MARK: - Body Tab

    @ViewBuilder
    private func bodyTab(response: KoalaResponse) -> some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Body Sub-Tab", selection: $bodySubTab) {
                    ForEach(BodyTab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            Divider()

            switch bodySubTab {
            case .pretty:
                JSONViewerView(data: response.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .raw:
                ScrollView {
                    Text(String(data: response.body, encoding: .utf8) ?? "<binary data>")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .preview:
                WebPreviewView(data: response.body, headers: response.headers)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Headers Tab

    private func headersTab(response: KoalaResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(response.headers.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .top, spacing: 0) {
                        Text(key)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.primary)

                        Text(response.headers[key] ?? "")
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    Divider().padding(.leading, 12)
                }
            }
        }
    }

    // MARK: - Cookies Tab

    private func cookiesTab(response: KoalaResponse) -> some View {
        let cookies = parseCookies(from: response.headers)
        return ScrollView {
            if cookies.isEmpty {
                Text("No cookies in this response.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(cookies) { cookie in
                        CookieRowView(cookie: cookie)
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }

    // MARK: - Timeline Tab

    private func timelineTab(response: KoalaResponse) -> some View {
        let tl = response.timeline
        let total = max(tl.totalMs, 1)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TimelineRowView(label: "DNS Lookup",   ms: tl.dnsMs,      color: .teal,   totalMs: total)
                TimelineRowView(label: "TCP Connect",  ms: tl.connectMs,  color: .blue,   totalMs: total)
                TimelineRowView(label: "TLS Handshake",ms: tl.tlsMs,      color: .purple, totalMs: total)
                TimelineRowView(label: "TTFB",         ms: tl.ttfbMs,     color: .orange, totalMs: total)
                TimelineRowView(label: "Download",     ms: tl.downloadMs, color: .green,  totalMs: total)

                Divider()

                HStack {
                    Text("Total")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(tl.totalMs) ms")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Send a request to see the response.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    }

    private func copyCurlToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(curlCommand, forType: .string)
    }

    private func parseCookies(from headers: [String: String]) -> [ParsedCookie] {
        let setCookieHeaders = headers.filter { $0.key.lowercased() == "set-cookie" }
        return setCookieHeaders.enumerated().compactMap { idx, pair in
            ParsedCookie.parse(from: pair.value, id: idx)
        }
    }
}

// MARK: - ParsedCookie

struct ParsedCookie: Identifiable {
    let id: Int
    let name: String
    let value: String
    let domain: String?
    let path: String?
    let expires: String?
    let httpOnly: Bool
    let secure: Bool

    static func parse(from header: String, id: Int) -> ParsedCookie? {
        let parts = header.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first else { return nil }
        let nameValue = first.components(separatedBy: "=")
        guard nameValue.count >= 2 else { return nil }
        let name = nameValue[0]
        let value = nameValue.dropFirst().joined(separator: "=")

        var domain: String?
        var path: String?
        var expires: String?
        var httpOnly = false
        var secure = false

        for part in parts.dropFirst() {
            let lower = part.lowercased()
            if lower == "httponly" { httpOnly = true }
            else if lower == "secure" { secure = true }
            else if lower.hasPrefix("domain=") { domain = String(part.dropFirst(7)) }
            else if lower.hasPrefix("path=") { path = String(part.dropFirst(5)) }
            else if lower.hasPrefix("expires=") { expires = String(part.dropFirst(8)) }
        }

        return ParsedCookie(id: id, name: name, value: value, domain: domain, path: path,
                            expires: expires, httpOnly: httpOnly, secure: secure)
    }
}

// MARK: - CookieRowView

private struct CookieRowView: View {
    let cookie: ParsedCookie

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(cookie.name)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                Text("=")
                    .foregroundStyle(.secondary)
                Text(cookie.value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(spacing: 8) {
                if let domain = cookie.domain {
                    Label(domain, systemImage: "globe").font(.caption).foregroundStyle(.secondary)
                }
                if let path = cookie.path {
                    Label(path, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                }
                if cookie.httpOnly {
                    Text("HttpOnly").font(.caption2).padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }
                if cookie.secure {
                    Text("Secure").font(.caption2).padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - TimelineRowView

private struct TimelineRowView: View {
    let label: String
    let ms: Int
    let color: Color
    let totalMs: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let fraction = max(0, min(1, Double(ms) / Double(totalMs)))
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.7))
                        .frame(width: geo.size.width * fraction, height: 12)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 12)

            Text("\(ms) ms")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - WebPreviewView

private struct WebPreviewView: NSViewRepresentable {
    let data: Data
    let headers: [String: String]

    func makeNSView(context: Context) -> WKWebView { WKWebView() }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let contentType = headers.first(where: { $0.key.lowercased() == "content-type" })?.value ?? ""
        if contentType.lowercased().contains("html") {
            webView.load(data, mimeType: "text/html", characterEncodingName: "UTF-8", baseURL: URL(string: "about:blank")!)
        } else {
            let text = String(data: data, encoding: .utf8) ?? ""
            webView.loadHTMLString("<pre>\(text)</pre>", baseURL: nil)
        }
    }
}

// MARK: - ResponseDocument (FileExporter)

private struct ResponseDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Previews

#Preview("ResponseView — JSON") {
    let json = #"{"id":1,"name":"Koala","version":"1.0"}"#.data(using: .utf8)!
    let response = KoalaResponse(
        statusCode: 200,
        statusText: "OK",
        headers: ["Content-Type": "application/json"],
        body: json,
        durationMs: 142,
        sizeBytes: json.count,
        timeline: ResponseTimeline(dnsMs: 12, connectMs: 30, tlsMs: 45, ttfbMs: 50, downloadMs: 5)
    )

    return ResponseView(response: response, curlCommand: "curl https://example.com")
        .frame(width: 700, height: 500)
}

#Preview("ResponseView — Empty") {
    ResponseView(response: nil, curlCommand: "")
        .frame(width: 700, height: 300)
}
