import Foundation

// MARK: - Project

struct Project: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var slug: String
    var color: String?
    var groupName: String?
    var createdAt: Date
    var updatedAt: Date
    /// Vercel Edge Config ID storing this project's collaboration bundle.
    /// nil until first push.
    var collabEdgeConfigId: String?
    /// Optional tag identifying environment (Development / Staging / Production / custom).
    var tagId: UUID?

    init(
        id: UUID = UUID(),
        name: String = "Untitled Project",
        slug: String = "",
        color: String? = nil,
        groupName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        collabEdgeConfigId: String? = nil,
        tagId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug.isEmpty ? Project.deriveSlug(from: name) : slug
        self.color = color
        self.groupName = groupName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.collabEdgeConfigId = collabEdgeConfigId
        self.tagId = tagId
    }

    enum CodingKeys: String, CodingKey {
        case id, name, slug, color, groupName, createdAt, updatedAt, collabEdgeConfigId, tagId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        slug = try c.decode(String.self, forKey: .slug)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        groupName = try c.decodeIfPresent(String.self, forKey: .groupName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        collabEdgeConfigId = try c.decodeIfPresent(String.self, forKey: .collabEdgeConfigId)
        tagId = try c.decodeIfPresent(UUID.self, forKey: .tagId)
    }

    // MARK: - Slug Helpers

    /// Derives a URL-safe slug from a display name.
    /// Lowercases, converts non-[a-z0-9] to dash, collapses dashes, trims leading/trailing dashes.
    static func deriveSlug(from name: String) -> String {
        let lowered = name.lowercased()
        let ascii = lowered.unicodeScalars.map { scalar -> Character in
            let v = scalar.value
            if (v >= 97 && v <= 122) || (v >= 48 && v <= 57) { return Character(scalar) }
            return "-"
        }
        let raw = String(ascii)
        let collapsed = raw.components(separatedBy: "-").filter { !$0.isEmpty }.joined(separator: "-")
        return collapsed.isEmpty ? "untitled" : collapsed
    }
}

// MARK: - ProjectTag

struct ProjectTag: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    static let defaults: [ProjectTag] = [
        ProjectTag(name: "Development", colorHex: "#22B8CF"),
        ProjectTag(name: "Staging",     colorHex: "#FFA94D"),
        ProjectTag(name: "Production",  colorHex: "#FF6B6B"),
    ]
}

// MARK: - ProjectsManifest

struct ProjectsManifest: Codable {
    var projects: [Project]
    var activeProjectId: UUID?
    /// Group names that exist independently (e.g., created before any project is assigned).
    var customGroupNames: [String]
    /// User-defined project tags (env labels). Seeded with defaults on first run.
    var tags: [ProjectTag]

    init(projects: [Project] = [], activeProjectId: UUID? = nil, customGroupNames: [String] = [], tags: [ProjectTag] = ProjectTag.defaults) {
        self.projects = projects
        self.activeProjectId = activeProjectId
        self.customGroupNames = customGroupNames
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case projects, activeProjectId, customGroupNames, tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = try c.decode([Project].self, forKey: .projects)
        activeProjectId = try c.decodeIfPresent(UUID.self, forKey: .activeProjectId)
        customGroupNames = (try? c.decodeIfPresent([String].self, forKey: .customGroupNames)) ?? []
        tags = (try? c.decodeIfPresent([ProjectTag].self, forKey: .tags)) ?? ProjectTag.defaults
    }
}
