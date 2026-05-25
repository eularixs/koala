import Foundation

enum VariableResolver {

    static func resolve(
        _ input: String,
        environment: KoalaEnvironment?,
        globals: [KeyValuePair],
        collectionVariables: [KeyValuePair] = []
    ) -> String {
        let pattern = #"\{\{([^{}]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }

        let lookup = buildLookup(
            globals: globals,
            environment: environment,
            collectionVariables: collectionVariables
        )

        let range = NSRange(input.startIndex..., in: input)
        var result = input
        let matches = regex.matches(in: input, range: range).reversed()
        for match in matches {
            guard let swiftRange = Range(match.range(at: 0), in: result),
                  let nameRange = Range(match.range(at: 1), in: input) else { continue }
            let varName = String(input[nameRange]).trimmingCharacters(in: .whitespaces)
            if let value = lookup[varName] {
                result.replaceSubrange(swiftRange, with: value)
            }
        }
        return result
    }

    static func resolveAll(
        in request: KoalaRequest,
        environment: KoalaEnvironment?,
        globals: [KeyValuePair]
    ) -> KoalaRequest {
        var r = request
        r.url = resolve(r.url, environment: environment, globals: globals)
        r.name = resolve(r.name, environment: environment, globals: globals)
        r.queryParams = r.queryParams.map { resolveKV($0, environment: environment, globals: globals) }
        r.headers = r.headers.map { resolveKV($0, environment: environment, globals: globals) }
        r.body = resolveBody(r.body, environment: environment, globals: globals)
        r.auth = resolveAuth(r.auth, environment: environment, globals: globals)
        return r
    }

    private static func buildLookup(
        globals: [KeyValuePair],
        environment: KoalaEnvironment?,
        collectionVariables: [KeyValuePair]
    ) -> [String: String] {
        var lookup: [String: String] = [:]
        for kv in globals where kv.isEnabled {
            lookup[kv.key] = kv.value
        }
        if let env = environment {
            for variable in env.variables where variable.isEnabled {
                lookup[variable.key] = variable.value
            }
        }
        for kv in collectionVariables where kv.isEnabled {
            lookup[kv.key] = kv.value
        }
        return lookup
    }

    private static func resolveKV(
        _ pair: KeyValuePair,
        environment: KoalaEnvironment?,
        globals: [KeyValuePair]
    ) -> KeyValuePair {
        var p = pair
        p.key = resolve(p.key, environment: environment, globals: globals)
        p.value = resolve(p.value, environment: environment, globals: globals)
        return p
    }

    private static func resolveBody(
        _ body: RequestBody,
        environment: KoalaEnvironment?,
        globals: [KeyValuePair]
    ) -> RequestBody {
        let r: (String) -> String = { resolve($0, environment: environment, globals: globals) }
        switch body {
        case .none:
            return .none
        case .json(let s):
            return .json(r(s))
        case .raw(let content, let contentType):
            return .raw(content: r(content), contentType: contentType)
        case .graphql(let query, let variables):
            return .graphql(query: r(query), variables: r(variables))
        case .formURLEncoded(let pairs):
            return .formURLEncoded(pairs.map { resolveKV($0, environment: environment, globals: globals) })
        case .multipart(let items):
            return .multipart(items.map { resolveMultipart($0, environment: environment, globals: globals) })
        case .binary(let url):
            return .binary(url)
        }
    }

    private static func resolveMultipart(
        _ item: MultipartItem,
        environment: KoalaEnvironment?,
        globals: [KeyValuePair]
    ) -> MultipartItem {
        var m = item
        m.key = resolve(m.key, environment: environment, globals: globals)
        if m.type == .text {
            m.value = resolve(m.value, environment: environment, globals: globals)
        }
        return m
    }

    private static func resolveAuth(
        _ auth: AuthConfig,
        environment: KoalaEnvironment?,
        globals: [KeyValuePair]
    ) -> AuthConfig {
        let r: (String) -> String = { resolve($0, environment: environment, globals: globals) }
        switch auth {
        case .none:
            return .none
        case .bearer(let token):
            return .bearer(token: r(token))
        case .basic(let username, let password):
            return .basic(username: r(username), password: r(password))
        case .apiKey(let key, let value, let location):
            return .apiKey(key: r(key), value: r(value), location: location)
        case .oauth2(let config):
            return .oauth2(config)
        case .awsSignature(let config):
            return .awsSignature(config)
        }
    }
}
