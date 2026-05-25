import Foundation

// MARK: - VercelToken

struct VercelToken: Codable, Hashable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpired: Bool { expiresAt < Date() }

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt    = "expires_at"
    }
}

// MARK: - VercelUser

struct VercelUser: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var email: String

    enum CodingKeys: String, CodingKey {
        case id    = "id"
        case name  = "name"
        case email = "email"
    }
}

// MARK: - VercelProject

struct VercelProject: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var framework: String?

    enum CodingKeys: String, CodingKey {
        case id        = "id"
        case name      = "name"
        case framework = "framework"
    }
}

// MARK: - DeploymentStatus

enum DeploymentStatus: String, Codable, CaseIterable, Identifiable {
    case queued   = "QUEUED"
    case building = "BUILDING"
    case ready    = "READY"
    case error    = "ERROR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .queued:   return "Queued"
        case .building: return "Building"
        case .ready:    return "Ready"
        case .error:    return "Error"
        }
    }
}

// MARK: - Deployment

struct Deployment: Identifiable, Codable, Hashable {
    var id: String
    var url: String
    var state: DeploymentStatus

    enum CodingKeys: String, CodingKey {
        case id    = "id"
        case url   = "url"
        case state = "state"
    }
}
