import Foundation

// MARK: - ImportError

enum ImportError: LocalizedError {
    case malformed(String)
    case unsupportedVersion(String)

    var errorDescription: String? {
        switch self {
        case .malformed(let detail):
            return "Malformed import data: \(detail)"
        case .unsupportedVersion(let version):
            return "Unsupported format version: \(version)"
        }
    }
}
