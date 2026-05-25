import Foundation

// MARK: - Supporting types

enum APIKeyLocation: String, Codable, CaseIterable, Identifiable {
    case header = "header"
    case query  = "query"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .header: return "Header"
        case .query:  return "Query Param"
        }
    }
}

struct OAuth2Config: Codable, Hashable {
    var clientId: String
    var clientSecret: String
    var authorizationURL: String
    var tokenURL: String
    var redirectURI: String
    var scope: String
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Date?

    static var empty: OAuth2Config {
        OAuth2Config(
            clientId: "",
            clientSecret: "",
            authorizationURL: "",
            tokenURL: "",
            redirectURI: "",
            scope: ""
        )
    }
}

struct AWSSignatureConfig: Codable, Hashable {
    var accessKeyId: String
    var secretAccessKey: String
    var sessionToken: String?
    var region: String
    var service: String

    static var empty: AWSSignatureConfig {
        AWSSignatureConfig(accessKeyId: "", secretAccessKey: "", region: "", service: "")
    }
}

// MARK: - AuthConfig

enum AuthConfig: Codable, Hashable {
    case none
    case bearer(token: String)
    case basic(username: String, password: String)
    case apiKey(key: String, value: String, location: APIKeyLocation)
    case oauth2(OAuth2Config)
    case awsSignature(AWSSignatureConfig)

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type, token, username, password, key, value, location, config
    }

    private enum AuthType: String, Codable {
        case none, bearer, basic, apiKey, oauth2, awsSignature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(AuthType.self, forKey: .type)
        switch type {
        case .none:
            self = .none
        case .bearer:
            let token = try container.decode(String.self, forKey: .token)
            self = .bearer(token: token)
        case .basic:
            let username = try container.decode(String.self, forKey: .username)
            let password = try container.decode(String.self, forKey: .password)
            self = .basic(username: username, password: password)
        case .apiKey:
            let key      = try container.decode(String.self, forKey: .key)
            let value    = try container.decode(String.self, forKey: .value)
            let location = try container.decode(APIKeyLocation.self, forKey: .location)
            self = .apiKey(key: key, value: value, location: location)
        case .oauth2:
            let config = try container.decode(OAuth2Config.self, forKey: .config)
            self = .oauth2(config)
        case .awsSignature:
            let config = try container.decode(AWSSignatureConfig.self, forKey: .config)
            self = .awsSignature(config)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(AuthType.none, forKey: .type)
        case .bearer(let token):
            try container.encode(AuthType.bearer, forKey: .type)
            try container.encode(token, forKey: .token)
        case .basic(let username, let password):
            try container.encode(AuthType.basic, forKey: .type)
            try container.encode(username, forKey: .username)
            try container.encode(password, forKey: .password)
        case .apiKey(let key, let value, let location):
            try container.encode(AuthType.apiKey, forKey: .type)
            try container.encode(key, forKey: .key)
            try container.encode(value, forKey: .value)
            try container.encode(location, forKey: .location)
        case .oauth2(let config):
            try container.encode(AuthType.oauth2, forKey: .type)
            try container.encode(config, forKey: .config)
        case .awsSignature(let config):
            try container.encode(AuthType.awsSignature, forKey: .type)
            try container.encode(config, forKey: .config)
        }
    }

    // MARK: UI helpers

    var displayName: String {
        switch self {
        case .none:         return "No Auth"
        case .bearer:       return "Bearer Token"
        case .basic:        return "Basic Auth"
        case .apiKey:       return "API Key"
        case .oauth2:       return "OAuth 2.0"
        case .awsSignature: return "AWS Signature"
        }
    }
}
