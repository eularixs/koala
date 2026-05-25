import Foundation

// MARK: - Project

struct Project: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var slug: String
    var color: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Untitled Project",
        slug: String = "",
        color: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.slug = slug.isEmpty ? Project.deriveSlug(from: name) : slug
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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

// MARK: - ProjectsManifest

struct ProjectsManifest: Codable {
    var projects: [Project]
    var activeProjectId: UUID?

    init(projects: [Project] = [], activeProjectId: UUID? = nil) {
        self.projects = projects
        self.activeProjectId = activeProjectId
    }
}
