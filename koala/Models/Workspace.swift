import Foundation

// MARK: - MemberRole

enum MemberRole: String, Codable, CaseIterable, Identifiable {
    case owner  = "owner"
    case editor = "editor"
    case viewer = "viewer"

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

// MARK: - WorkspaceMember

struct WorkspaceMember: Identifiable, Codable, Hashable {
    var id: UUID
    var userId: String
    var role: MemberRole
    var joinedAt: Date

    init(
        id: UUID = UUID(),
        userId: String = "",
        role: MemberRole = .viewer,
        joinedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.role = role
        self.joinedAt = joinedAt
    }
}

// MARK: - Workspace

struct Workspace: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kvNamespace: String
    var members: [WorkspaceMember]
    var lastSyncedAt: Date?

    init(
        id: UUID = UUID(),
        name: String = "My Workspace",
        kvNamespace: String = "",
        members: [WorkspaceMember] = [],
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kvNamespace = kvNamespace
        self.members = members
        self.lastSyncedAt = lastSyncedAt
    }

    static var empty: Workspace { Workspace() }
}

// MARK: - SyncPayload

struct SyncPayload: Codable, Hashable {
    var workspaceId: String
    var author: String
    var message: String?
    var timestamp: Date
    var collections: [KoalaCollection]
    var environments: [KoalaEnvironment]
    var mockServers: [MockServer]
    var version: Int

    init(
        workspaceId: String = "",
        author: String = "",
        message: String? = nil,
        timestamp: Date = Date(),
        collections: [KoalaCollection] = [],
        environments: [KoalaEnvironment] = [],
        mockServers: [MockServer] = [],
        version: Int = 1
    ) {
        self.workspaceId = workspaceId
        self.author = author
        self.message = message
        self.timestamp = timestamp
        self.collections = collections
        self.environments = environments
        self.mockServers = mockServers
        self.version = version
    }

    static var empty: SyncPayload { SyncPayload() }
}
