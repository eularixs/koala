import Foundation

// MARK: - CURLParser

final class CURLParser {

    static func parse(_ input: String) throws -> KoalaRequest {
        let tokens = tokenize(normalizeNewlines(input))
        return try buildRequest(from: tokens)
    }

    // MARK: - Normalization

    /// Collapse backslash-newline continuations into a single line.
    private static func normalizeNewlines(_ input: String) -> String {
        input.replacingOccurrences(of: "\\\n", with: " ")
             .replacingOccurrences(of: "\\\r\n", with: " ")
    }

    // MARK: - Tokenizer

    /// Split the input into shell-like tokens, respecting single/double quotes and `\"` escapes inside double quotes.
    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var i = input.startIndex

        while i < input.endIndex {
            let ch = input[i]

            if ch == "\\" && inDouble {
                let next = input.index(after: i)
                if next < input.endIndex {
                    current.append(input[next])
                    i = input.index(after: next)
                    continue
                }
            }

            if ch == "'" && !inDouble {
                inSingle.toggle()
            } else if ch == "\"" && !inSingle {
                inDouble.toggle()
            } else if (ch == " " || ch == "\t") && !inSingle && !inDouble {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }

            i = input.index(after: i)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Request builder

    private static func buildRequest(from tokens: [String]) throws -> KoalaRequest {
        var url: String?
        var method: String?
        var headers: [KeyValuePair] = []
        var bodyString: String?
        var isGWithData = false
        var username: String?
        var password: String?
        var formItems: [MultipartItem] = []
        var isForm = false

        var idx = 0
        // Skip the leading "curl" token if present
        if tokens.first?.lowercased() == "curl" { idx = 1 }

        while idx < tokens.count {
            let token = tokens[idx]

            switch token {
            case "-X", "--request":
                idx += 1
                if idx < tokens.count { method = tokens[idx].uppercased() }

            case "--url":
                idx += 1
                if idx < tokens.count { url = tokens[idx] }

            case "-H", "--header":
                idx += 1
                if idx < tokens.count {
                    let header = parseHeader(tokens[idx])
                    headers.append(header)
                }

            case "-d", "--data", "--data-raw", "--data-binary", "--data-ascii":
                idx += 1
                if idx < tokens.count { bodyString = tokens[idx] }

            case "-u", "--user":
                idx += 1
                if idx < tokens.count {
                    let parts = tokens[idx].split(separator: ":", maxSplits: 1)
                    username = String(parts.first ?? "")
                    password = parts.count > 1 ? String(parts[1]) : ""
                }

            case "-A", "--user-agent":
                idx += 1
                if idx < tokens.count {
                    headers.append(KeyValuePair(key: "User-Agent", value: tokens[idx]))
                }

            case "-b", "--cookie":
                idx += 1
                if idx < tokens.count {
                    headers.append(KeyValuePair(key: "Cookie", value: tokens[idx]))
                }

            case "-F", "--form":
                idx += 1
                if idx < tokens.count {
                    isForm = true
                    let item = parseFormItem(tokens[idx])
                    formItems.append(item)
                }

            case "-G", "--get":
                isGWithData = true

            case "--compressed":
                break  // ignore

            default:
                // First non-flag argument is the URL
                if !token.hasPrefix("-") && url == nil {
                    url = token
                }
            }

            idx += 1
        }

        guard let resolvedURL = url, !resolvedURL.isEmpty else {
            throw ImportError.malformed("No URL found in cURL command")
        }

        // Determine method
        let resolvedMethod: HTTPMethodValue
        if let m = method {
            resolvedMethod = curlHTTPMethodValue(m)
        } else if isGWithData {
            resolvedMethod = .standard(.get)
        } else if bodyString != nil || isForm {
            resolvedMethod = .standard(.post)
        } else {
            resolvedMethod = .standard(.get)
        }

        // Auth
        let auth: AuthConfig
        if let u = username {
            auth = .basic(username: u, password: password ?? "")
        } else {
            auth = .none
        }

        // Body
        let body: RequestBody
        if isGWithData {
            // -G with -d means append data as query string — body is none
            body = .none
        } else if isForm {
            body = .multipart(formItems)
        } else if let rawBody = bodyString {
            body = parseBodyString(rawBody, existingHeaders: headers)
        } else {
            body = .none
        }

        // Handle -G data → append to query string
        var finalURL = resolvedURL
        if isGWithData, let dataStr = bodyString {
            let sep = finalURL.contains("?") ? "&" : "?"
            finalURL = finalURL + sep + dataStr
        }

        return KoalaRequest(
            name: "Imported Request",
            method: resolvedMethod,
            url: finalURL,
            queryParams: [],
            headers: headers,
            auth: auth,
            body: body
        )
    }

    // MARK: - Helpers

    private static func parseHeader(_ raw: String) -> KeyValuePair {
        if let colonRange = raw.range(of: ":") {
            let key = String(raw[raw.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(raw[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return KeyValuePair(key: key, value: value)
        }
        return KeyValuePair(key: raw, value: "")
    }

    private static func parseFormItem(_ raw: String) -> MultipartItem {
        if let eqRange = raw.range(of: "=") {
            let key = String(raw[raw.startIndex..<eqRange.lowerBound])
            let value = String(raw[eqRange.upperBound...])
            return MultipartItem(key: key, value: value, type: .text)
        }
        return MultipartItem(key: raw, value: "", type: .text)
    }

    private static func parseBodyString(_ body: String, existingHeaders: [KeyValuePair]) -> RequestBody {
        // Check if Content-Type header hints at JSON
        let ctHeader = existingHeaders.first(where: {
            $0.key.lowercased() == "content-type"
        })?.value.lowercased() ?? ""

        if ctHeader.contains("application/json") || isValidJSON(body) {
            return .json(body)
        }
        return .raw(content: body, contentType: "text/plain")
    }

    private static func isValidJSON(_ string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}

// MARK: - HTTPMethodValue convenience (file-private free function)

private func curlHTTPMethodValue(_ rawString: String) -> HTTPMethodValue {
    let upper = rawString.uppercased()
    if let m = HTTPMethod(rawValue: upper) { return .standard(m) }
    return .custom(upper)
}
