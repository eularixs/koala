import Foundation

// MARK: - CodeLanguage

enum CodeLanguage: String, CaseIterable, Identifiable {
    case curl = "cURL"
    case swiftURLSession = "Swift URLSession"
    case jsFetch = "JavaScript fetch"
    case nodeAxios = "Node.js axios"
    case pythonRequests = "Python requests"
    case goNetHttp = "Go net/http"
    case rustReqwest = "Rust reqwest"
    case rubyNetHttp = "Ruby Net::HTTP"
    case phpCurl = "PHP curl"
    case csharpHttpClient = "C# HttpClient"
    case kotlinOkHttp = "Kotlin OkHttp"

    var id: String { rawValue }
}

// MARK: - CodeGenerator
//
// Multi-language code snippet generator. Variables (`{{var}}`) are resolved via
// `VariableResolver.resolveAll(...)` before rendering so the output is a fully
// concrete, runnable snippet.
//
// NOTE: multipart/form-data bodies are intentionally NOT rendered by the
// per-language emitters yet -- they require per-language file/streaming APIs
// that vary widely. A placeholder comment is emitted instead. cURL keeps its
// existing handling via `HTTPClientService.curlCommand(...)`.

enum CodeGenerator {

    static func generate(
        _ request: KoalaRequest,
        language: CodeLanguage,
        environment: KoalaEnvironment?,
        globals: [KeyValuePair]
    ) -> String {
        let resolved = VariableResolver.resolveAll(in: request, environment: environment, globals: globals)
        let ctx = SnippetContext(request: resolved)

        switch language {
        case .curl:
            return HTTPClientService().curlCommand(for: request, environment: environment, globalVariables: globals)
        case .swiftURLSession:   return swiftURLSession(ctx)
        case .jsFetch:           return jsFetch(ctx)
        case .nodeAxios:         return nodeAxios(ctx)
        case .pythonRequests:    return pythonRequests(ctx)
        case .goNetHttp:         return goNetHttp(ctx)
        case .rustReqwest:       return rustReqwest(ctx)
        case .rubyNetHttp:       return rubyNetHttp(ctx)
        case .phpCurl:           return phpCurl(ctx)
        case .csharpHttpClient:  return csharpHttpClient(ctx)
        case .kotlinOkHttp:      return kotlinOkHttp(ctx)
        }
    }
}

// MARK: - Snippet context

private struct SnippetContext {
    let method: String
    let url: String
    let headers: [(key: String, value: String)]
    let body: BodyPayload

    enum BodyPayload {
        case none
        case json(String)
        case form([(String, String)])
        case raw(content: String, contentType: String)
        case graphql(query: String, variables: String)
        case multipartPlaceholder
        case binary(URL)
    }

    init(request: KoalaRequest) {
        self.method = request.method.rawValue

        var urlString = request.url.trimmingCharacters(in: .whitespaces)
        let enabledParams = request.queryParams.filter { $0.isEnabled && !$0.key.isEmpty }
        if !enabledParams.isEmpty, var components = URLComponents(string: urlString) {
            var items = components.queryItems ?? []
            for p in enabledParams {
                items.append(URLQueryItem(name: p.key, value: p.value))
            }
            components.queryItems = items
            urlString = components.string ?? urlString
        }

        var collected: [(String, String)] = []
        for h in request.headers where h.isEnabled && !h.key.isEmpty {
            collected.append((h.key, h.value))
        }

        switch request.auth {
        case .none:
            break
        case .bearer(let token):
            collected.append(("Authorization", "Bearer \(token)"))
        case .basic(let user, let pass):
            let raw = "\(user):\(pass)"
            let b64 = Data(raw.utf8).base64EncodedString()
            collected.append(("Authorization", "Basic \(b64)"))
        case .apiKey(let key, let value, let location):
            switch location {
            case .header:
                collected.append((key, value))
            case .query:
                if var components = URLComponents(string: urlString) {
                    var items = components.queryItems ?? []
                    items.append(URLQueryItem(name: key, value: value))
                    components.queryItems = items
                    urlString = components.string ?? urlString
                }
            }
        case .oauth2, .awsSignature:
            break
        }

        switch request.body {
        case .none:
            self.body = .none
        case .json(let s):
            collected.append(("Content-Type", "application/json"))
            self.body = .json(s)
        case .formURLEncoded(let pairs):
            collected.append(("Content-Type", "application/x-www-form-urlencoded"))
            self.body = .form(pairs.filter { $0.isEnabled }.map { ($0.key, $0.value) })
        case .raw(let content, let contentType):
            collected.append(("Content-Type", contentType))
            self.body = .raw(content: content, contentType: contentType)
        case .graphql(let q, let v):
            collected.append(("Content-Type", "application/json"))
            self.body = .graphql(query: q, variables: v)
        case .multipart:
            collected.append(("Content-Type", "multipart/form-data"))
            self.body = .multipartPlaceholder
        case .binary(let url):
            collected.append(("Content-Type", "application/octet-stream"))
            self.body = .binary(url)
        }

        var seen: [String: Int] = [:]
        var out: [(String, String)] = []
        for (k, v) in collected {
            let lc = k.lowercased()
            if let idx = seen[lc] {
                out[idx] = (k, v)
            } else {
                seen[lc] = out.count
                out.append((k, v))
            }
        }

        self.url = urlString
        self.headers = out
    }

    var bodyAsString: String? {
        switch body {
        case .none, .binary, .multipartPlaceholder:
            return nil
        case .json(let s):
            return s
        case .raw(let content, _):
            return content
        case .form(let pairs):
            var comp = URLComponents()
            comp.queryItems = pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
            return comp.percentEncodedQuery ?? ""
        case .graphql(let q, let v):
            var payload: [String: Any] = ["query": q]
            if !v.isEmpty, let obj = try? JSONSerialization.jsonObject(with: Data(v.utf8)) {
                payload["variables"] = obj
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let s = String(data: data, encoding: .utf8) {
                return s
            }
            return q
        }
    }

    var hasBody: Bool {
        if case .none = body { return false }
        if case .multipartPlaceholder = body { return false }
        return true
    }
}

// MARK: - String escaping helpers

private func escDQ(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
}

private func escGoBacktick(_ s: String) -> String {
    s.replacingOccurrences(of: "`", with: "` + \"`\" + `")
}

private func jsTemplateLiteral(_ s: String) -> String {
    "`" + s.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`", with: "\\`")
        .replacingOccurrences(of: "${", with: "\\${") + "`"
}

// MARK: - Swift URLSession

private func swiftURLSession(_ ctx: SnippetContext) -> String {
    var lines: [String] = []
    lines.append("import Foundation")
    lines.append("")
    lines.append("guard let url = URL(string: \"\(escDQ(ctx.url))\") else { fatalError(\"Invalid URL\") }")
    lines.append("var request = URLRequest(url: url)")
    lines.append("request.httpMethod = \"\(ctx.method)\"")
    for (k, v) in ctx.headers {
        lines.append("request.setValue(\"\(escDQ(v))\", forHTTPHeaderField: \"\(escDQ(k))\")")
    }
    if let body = ctx.bodyAsString {
        lines.append("let bodyString = \"\"\"")
        lines.append(body)
        lines.append("\"\"\"")
        lines.append("request.httpBody = bodyString.data(using: .utf8)")
    } else if case .binary(let url) = ctx.body {
        lines.append("request.httpBody = try? Data(contentsOf: URL(fileURLWithPath: \"\(escDQ(url.path))\"))")
    } else if case .multipartPlaceholder = ctx.body {
        lines.append("// TODO: build multipart/form-data body (not generated)")
    }
    lines.append("")
    lines.append("let task = URLSession.shared.dataTask(with: request) { data, response, error in")
    lines.append("    if let error = error { print(\"Error:\", error); return }")
    lines.append("    if let data = data, let body = String(data: data, encoding: .utf8) { print(body) }")
    lines.append("}")
    lines.append("task.resume()")
    return lines.joined(separator: "\n")
}

// MARK: - JavaScript fetch

private func jsFetch(_ ctx: SnippetContext) -> String {
    var lines: [String] = []
    lines.append("const url = \"\(escDQ(ctx.url))\";")
    lines.append("")
    lines.append("const options = {")
    lines.append("  method: \"\(ctx.method)\",")
    if !ctx.headers.isEmpty {
        lines.append("  headers: {")
        for (k, v) in ctx.headers {
            lines.append("    \"\(escDQ(k))\": \"\(escDQ(v))\",")
        }
        lines.append("  },")
    }
    if let body = ctx.bodyAsString {
        lines.append("  body: \(jsTemplateLiteral(body)),")
    } else if case .multipartPlaceholder = ctx.body {
        lines.append("  // TODO: build FormData multipart body (not generated)")
    }
    lines.append("};")
    lines.append("")
    lines.append("fetch(url, options)")
    lines.append("  .then((res) => res.text())")
    lines.append("  .then((body) => console.log(body))")
    lines.append("  .catch((err) => console.error(err));")
    return lines.joined(separator: "\n")
}

// MARK: - Node.js axios

private func nodeAxios(_ ctx: SnippetContext) -> String {
    var lines: [String] = []
    lines.append("const axios = require(\"axios\");")
    lines.append("")
    lines.append("const config = {")
    lines.append("  method: \"\(ctx.method.lowercased())\",")
    lines.append("  url: \"\(escDQ(ctx.url))\",")
    if !ctx.headers.isEmpty {
        lines.append("  headers: {")
        for (k, v) in ctx.headers {
            lines.append("    \"\(escDQ(k))\": \"\(escDQ(v))\",")
        }
        lines.append("  },")
    }
    if let body = ctx.bodyAsString {
        lines.append("  data: \(jsTemplateLiteral(body)),")
    } else if case .multipartPlaceholder = ctx.body {
        lines.append("  // TODO: multipart body (use form-data package)")
    }
    lines.append("};")
    lines.append("")
    lines.append("axios(config)")
    lines.append("  .then((response) => console.log(JSON.stringify(response.data, null, 2)))")
    lines.append("  .catch((error) => console.error(error));")
    return lines.joined(separator: "\n")
}

// MARK: - Python requests

private func pythonRequests(_ ctx: SnippetContext) -> String {
    var lines: [String] = []
    lines.append("import requests")
    lines.append("")
    lines.append("url = \"\(escDQ(ctx.url))\"")
    if !ctx.headers.isEmpty {
        lines.append("headers = {")
        for (k, v) in ctx.headers {
            lines.append("    \"\(escDQ(k))\": \"\(escDQ(v))\",")
        }
        lines.append("}")
    } else {
        lines.append("headers = {}")
    }
    if let body = ctx.bodyAsString {
        lines.append("payload = \"\"\"\(body)\"\"\"")
        lines.append("response = requests.request(\"\(ctx.method)\", url, headers=headers, data=payload)")
    } else if case .multipartPlaceholder = ctx.body {
        lines.append("# TODO: multipart body (use files={...})")
        lines.append("response = requests.request(\"\(ctx.method)\", url, headers=headers)")
    } else {
        lines.append("response = requests.request(\"\(ctx.method)\", url, headers=headers)")
    }
    lines.append("print(response.text)")
    return lines.joined(separator: "\n")
}

// MARK: - Go net/http

private func goNetHttp(_ ctx: SnippetContext) -> String {
    var lines: [String] = []
    lines.append("package main")
    lines.append("")
    lines.append("import (")
    lines.append("\t\"fmt\"")
    lines.append("\t\"io\"")
    if ctx.hasBody { lines.append("\t\"strings\"") }
    lines.append("\t\"net/http\"")
    lines.append(")")
    lines.append("")
    lines.append("func main() {")
    lines.append("\turl := \"\(escDQ(ctx.url))\"")
    if let body = ctx.bodyAsString {
        lines.append("\tpayload := strings.NewReader(`\(escGoBacktick(body))`)")
        lines.append("\treq, err := http.NewRequest(\"\(ctx.method)\", url, payload)")
    } else {
        lines.append("\treq, err := http.NewRequest(\"\(ctx.method)\", url, nil)")
    }
    lines.append("\tif err != nil { panic(err) }")
    for (k, v) in ctx.headers {
        lines.append("\treq.Header.Add(\"\(escDQ(k))\", \"\(escDQ(v))\")")
    }
    lines.append("\tres, err := http.DefaultClient.Do(req)")
    lines.append("\tif err != nil { panic(err) }")
    lines.append("\tdefer res.Body.Close()")
    lines.append("\tbody, _ := io.ReadAll(res.Body)")
    lines.append("\tfmt.Println(string(body))")
    lines.append("}")
    return lines.joined(separator: "\n")
}

// MARK: - Rust reqwest

private func rustReqwest(_ ctx: SnippetContext) -> String {
    var lines: [String] = []
    lines.append("// Cargo.toml: reqwest = { version = \"0.12\", features = [\"blocking\", \"json\"] }")
    lines.append("use reqwest::blocking::Client;")
    lines.append("use reqwest::header::{HeaderMap, HeaderName, HeaderValue};")
    lines.append("use std::str::FromStr;")
    lines.append("")
    lines.append("fn main() -> Result<(), Box<dyn std::error::Error>> {")
    lines.append("    let client = Client::new();")
    lines.append("    let mut headers = HeaderMap::new();")
    for (k, v) in ctx.headers {
        lines.append("    headers.insert(HeaderName::from_str(\"\(escDQ(k))\")?, HeaderValue::from_str(\"\(escDQ(v))\")?);")
    }
    let methodCall = ctx.method.lowercased()
    if let body = ctx.bodyAsString {
        lines.append("    let body = r#\"\(body)\"#;")
        lines.append("    let res = client.\(methodCall)(\"\(escDQ(ctx.url))\")")
        lines.append("        .headers(headers)")
        lines.append("        .body(body)")
        lines.append("        .send()?;")
    } else {
        lines.append("    let res = client.\(methodCall)(\"\(escDQ(ctx.url))\")")
        lines.append("        .headers(headers)")
        lines.append("        .send()?;")
    }
    lines.append("    println!(\"{}\", res.text()?);")
    lines.append("    Ok(())")
    lines.append("}")
    return lines.joined(separator: "\n")
}

// MARK: - Ruby Net::HTTP

private func rubyNetHttp(_ ctx: SnippetContext) -> String {
    var lines: [String] = []
    lines.append("require 'uri'")
    lines.append("require 'net/http'")
    lines.append("")
    lines.append("url = URI(\"\(escDQ(ctx.url))\")")
    lines.append("http = Net::HTTP.new(url.host, url.port)")
    lines.append("http.use_ssl = (url.scheme == \"https\")")
    let reqClass: String
    switch ctx.method.uppercased() {
    case "GET":    reqClass = "Net::HTTP::Get"
    case "POST":   reqClass = "Net::HTTP::Post"
    case "PUT":    reqClass = "Net::HTTP::Put"
    case "PATCH":  reqClass = "Net::HTTP::Patch"
    case "DELETE": reqClass = "Net::HTTP::Delete"
    case "HEAD":   reqClass = "Net::HTTP::Head"
    default:       reqClass = "Net::HTTP::Get"
    }
    lines.append("request = \(reqClass).new(url)")
    for (k, v) in ctx.headers {
        lines.append("request[\"\(escDQ(k))\"] = \"\(escDQ(v))\"")
    }
    if let body = ctx.bodyAsString {
        lines.append("request.body = \"\(escDQ(body))\"")
    }
    lines.append("response = http.request(request)")
    lines.append("puts response.read_body")
    return lines.joined(separator: "\n")
}

// MARK: - PHP curl

private func phpCurl(_ ctx: SnippetContext) -> String {
    var lines: [String] = []
    lines.append("<?php")
    lines.append("$curl = curl_init();")
    lines.append("curl_setopt_array($curl, [")
    lines.append("    CURLOPT_URL => \"\(escDQ(ctx.url))\",")
    lines.append("    CURLOPT_RETURNTRANSFER => true,")
    lines.append("    CURLOPT_CUSTOMREQUEST => \"\(ctx.method)\",")
    if let body = ctx.bodyAsString {
        lines.append("    CURLOPT_POSTFIELDS => \"\(escDQ(body))\",")
    }
    if !ctx.headers.isEmpty {
        lines.append("    CURLOPT_HTTPHEADER => [")
        for (k, v) in ctx.headers {
            lines.append("        \"\(escDQ(k)): \(escDQ(v))\",")
        }
        lines.append("    ],")
    }
    lines.append("]);")
    lines.append("")
    lines.append("$response = curl_exec($curl);")
    lines.append("curl_close($curl);")
    lines.append("echo $response;")
    return lines.joined(separator: "\n")
}

// MARK: - C# HttpClient

private func csharpHttpClient(_ ctx: SnippetContext) -> String {
    var lines: [String] = []
    lines.append("using System;")
    lines.append("using System.Net.Http;")
    lines.append("using System.Threading.Tasks;")
    lines.append("")
    lines.append("class Program {")
    lines.append("    static async Task Main() {")
    lines.append("        var client = new HttpClient();")
    lines.append("        var request = new HttpRequestMessage(new HttpMethod(\"\(ctx.method)\"), \"\(escDQ(ctx.url))\");")
    for (k, v) in ctx.headers {
        if k.lowercased() == "content-type" { continue }
        lines.append("        request.Headers.TryAddWithoutValidation(\"\(escDQ(k))\", \"\(escDQ(v))\");")
    }
    if let body = ctx.bodyAsString {
        let ct = ctx.headers.first { $0.key.lowercased() == "content-type" }?.value ?? "application/json"
        lines.append("        request.Content = new StringContent(\"\(escDQ(body))\", System.Text.Encoding.UTF8, \"\(escDQ(ct))\");")
    }
    lines.append("        var response = await client.SendAsync(request);")
    lines.append("        var body = await response.Content.ReadAsStringAsync();")
    lines.append("        Console.WriteLine(body);")
    lines.append("    }")
    lines.append("}")
    return lines.joined(separator: "\n")
}

// MARK: - Kotlin OkHttp

private func kotlinOkHttp(_ ctx: SnippetContext) -> String {
    var lines: [String] = []
    lines.append("import okhttp3.MediaType.Companion.toMediaTypeOrNull")
    lines.append("import okhttp3.OkHttpClient")
    lines.append("import okhttp3.Request")
    lines.append("import okhttp3.RequestBody.Companion.toRequestBody")
    lines.append("")
    lines.append("fun main() {")
    lines.append("    val client = OkHttpClient()")
    if let body = ctx.bodyAsString {
        let ct = ctx.headers.first { $0.key.lowercased() == "content-type" }?.value ?? "application/json"
        lines.append("    val mediaType = \"\(escDQ(ct))\".toMediaTypeOrNull()")
        lines.append("    val body = \"\"\"\(body)\"\"\".toRequestBody(mediaType)")
    }
    lines.append("    val request = Request.Builder()")
    lines.append("        .url(\"\(escDQ(ctx.url))\")")
    if ctx.bodyAsString != nil {
        lines.append("        .method(\"\(ctx.method)\", body)")
    } else {
        lines.append("        .method(\"\(ctx.method)\", null)")
    }
    for (k, v) in ctx.headers {
        lines.append("        .addHeader(\"\(escDQ(k))\", \"\(escDQ(v))\")")
    }
    lines.append("        .build()")
    lines.append("")
    lines.append("    client.newCall(request).execute().use { response ->")
    lines.append("        println(response.body?.string())")
    lines.append("    }")
    lines.append("}")
    return lines.joined(separator: "\n")
}
