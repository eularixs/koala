import Foundation

/// Tiny JSONPath evaluator — supports a practical subset of the spec:
///
///   `$`              root
///   `.key`           child by name
///   `["key"]`        child by name (bracket form, also `['key']`)
///   `[N]`            array index (negative not supported)
///   `[*]`            wildcard — every array element or every object value
///   `.*`             wildcard child (same as `[*]`)
///   `..key`          recursive descent for a key
///   `..[*]`          recursive descent for every value
///
/// Designed for the response-body filter box — must NEVER crash on
/// malformed input. On parse / eval errors `evaluate(_:in:)` returns `nil`
/// so the caller can show a "no match" hint.
enum JSONPathEvaluator {

    // MARK: - Public API

    /// Evaluate `path` against `json` (a `JSONSerialization` object graph:
    /// `[String: Any]`, `[Any]`, `String`, `NSNumber`, `NSNull`).
    ///
    /// - Returns: list of matched values. `nil` if the path is malformed.
    ///            Empty array means "valid path, no match".
    static func evaluate(_ path: String, in json: Any) -> [Any]? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let tokens = tokenize(trimmed) else { return nil }
        guard tokens.first == .root else { return nil }

        var current: [Any] = [json]
        for token in tokens.dropFirst() {
            current = step(token, on: current)
            if current.isEmpty { break }
        }
        return current
    }

    // MARK: - Tokens

    private enum Token: Equatable {
        case root
        case child(String)            // .key  or  ["key"]
        case index(Int)               // [N]
        case wildcard                 // [*]  or  .*
        case recursiveChild(String)   // ..key
        case recursiveWildcard        // ..[*]  or ..*
    }

    // MARK: - Tokenizer

    private static func tokenize(_ path: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(path)
        var i = 0
        let n = chars.count

        guard n > 0, chars[0] == "$" else { return nil }
        tokens.append(.root)
        i = 1

        while i < n {
            let c = chars[i]

            if c == "." {
                // Either `..` (recursive) or `.key` / `.*`
                if i + 1 < n, chars[i + 1] == "." {
                    i += 2
                    // recursive descent — next must be key, `*`, or `[*]`
                    if i < n, chars[i] == "*" {
                        tokens.append(.recursiveWildcard)
                        i += 1
                    } else if i < n, chars[i] == "[" {
                        // ..[*] or ..[N] or ..["key"]
                        guard let (innerTok, consumed) = parseBracket(chars, from: i) else { return nil }
                        switch innerTok {
                        case .wildcard:
                            tokens.append(.recursiveWildcard)
                        case .child(let k):
                            tokens.append(.recursiveChild(k))
                        case .index:
                            // ..[N] not particularly meaningful — reject
                            return nil
                        default:
                            return nil
                        }
                        i += consumed
                    } else {
                        guard let (key, consumed) = parseIdentifier(chars, from: i), !key.isEmpty else { return nil }
                        tokens.append(.recursiveChild(key))
                        i += consumed
                    }
                } else {
                    i += 1
                    if i < n, chars[i] == "*" {
                        tokens.append(.wildcard)
                        i += 1
                    } else {
                        guard let (key, consumed) = parseIdentifier(chars, from: i), !key.isEmpty else { return nil }
                        tokens.append(.child(key))
                        i += consumed
                    }
                }
            } else if c == "[" {
                guard let (tok, consumed) = parseBracket(chars, from: i) else { return nil }
                tokens.append(tok)
                i += consumed
            } else {
                // Unexpected char (allow nothing else after `$`).
                return nil
            }
        }

        return tokens
    }

    /// Parse `[N]`, `[*]`, `["key"]`, `['key']`. Returns the token and the
    /// number of characters consumed (including both brackets).
    private static func parseBracket(_ chars: [Character], from start: Int) -> (Token, Int)? {
        let n = chars.count
        guard start < n, chars[start] == "[" else { return nil }
        var j = start + 1
        // skip whitespace
        while j < n, chars[j] == " " { j += 1 }
        guard j < n else { return nil }

        let inner: Token
        if chars[j] == "*" {
            inner = .wildcard
            j += 1
        } else if chars[j] == "\"" || chars[j] == "'" {
            let quote = chars[j]
            j += 1
            var key = ""
            while j < n, chars[j] != quote {
                key.append(chars[j])
                j += 1
            }
            guard j < n, chars[j] == quote else { return nil }
            j += 1
            inner = .child(key)
        } else if chars[j] == "-" || chars[j].isNumber {
            var numStr = ""
            if chars[j] == "-" { numStr.append("-"); j += 1 }
            while j < n, chars[j].isNumber {
                numStr.append(chars[j])
                j += 1
            }
            guard let num = Int(numStr) else { return nil }
            inner = .index(num)
        } else {
            return nil
        }

        // skip trailing whitespace
        while j < n, chars[j] == " " { j += 1 }
        guard j < n, chars[j] == "]" else { return nil }
        j += 1
        return (inner, j - start)
    }

    /// Parse a bare identifier: `[A-Za-z_][A-Za-z0-9_-]*`. Returns the key and
    /// chars consumed.
    private static func parseIdentifier(_ chars: [Character], from start: Int) -> (String, Int)? {
        let n = chars.count
        var j = start
        var key = ""
        while j < n {
            let c = chars[j]
            if c == "." || c == "[" { break }
            key.append(c)
            j += 1
        }
        return (key, j - start)
    }

    // MARK: - Evaluation step

    private static func step(_ token: Token, on values: [Any]) -> [Any] {
        switch token {
        case .root:
            // root should never appear here — first token only
            return values

        case .child(let key):
            var out: [Any] = []
            for v in values {
                if let dict = v as? [String: Any], let child = dict[key] {
                    out.append(child)
                }
            }
            return out

        case .index(let idx):
            var out: [Any] = []
            for v in values {
                if let arr = v as? [Any] {
                    let normalized = idx >= 0 ? idx : arr.count + idx
                    if normalized >= 0, normalized < arr.count {
                        out.append(arr[normalized])
                    }
                }
            }
            return out

        case .wildcard:
            var out: [Any] = []
            for v in values {
                if let arr = v as? [Any] {
                    out.append(contentsOf: arr)
                } else if let dict = v as? [String: Any] {
                    // Stable order for predictable output.
                    for k in dict.keys.sorted() {
                        if let child = dict[k] { out.append(child) }
                    }
                }
            }
            return out

        case .recursiveChild(let key):
            var out: [Any] = []
            for v in values {
                collectRecursive(in: v, key: key, into: &out)
            }
            return out

        case .recursiveWildcard:
            var out: [Any] = []
            for v in values {
                collectAllDescendants(in: v, into: &out)
            }
            return out
        }
    }

    private static func collectRecursive(in value: Any, key: String, into out: inout [Any]) {
        if let dict = value as? [String: Any] {
            if let v = dict[key] { out.append(v) }
            for k in dict.keys.sorted() {
                if let child = dict[k] {
                    collectRecursive(in: child, key: key, into: &out)
                }
            }
        } else if let arr = value as? [Any] {
            for item in arr {
                collectRecursive(in: item, key: key, into: &out)
            }
        }
    }

    private static func collectAllDescendants(in value: Any, into out: inout [Any]) {
        if let dict = value as? [String: Any] {
            for k in dict.keys.sorted() {
                if let child = dict[k] {
                    out.append(child)
                    collectAllDescendants(in: child, into: &out)
                }
            }
        } else if let arr = value as? [Any] {
            for item in arr {
                out.append(item)
                collectAllDescendants(in: item, into: &out)
            }
        }
    }
}
