import Foundation

// MARK: - Import / Export format enums

enum ImportFormat {
    case postman, openapi, insomnia, apidog, har, swagger, koala
}

enum ExportFormat {
    case postman, openapi, markdown, koalaNative, har
}

// MARK: - ImportExportService

@MainActor
@Observable
final class ImportExportService {

    // MARK: - Import

    func importFile(at url: URL, into projectId: UUID, appState: AppState) throws {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()

        if ext == "har" {
            let collection = try HARImporter.parse(data: data)
            add([collection], projectId: projectId, appState: appState)
            return
        }

        if isCURL(data: data, ext: ext) {
            let source = String(decoding: data, as: UTF8.self)
            let request = try CURLParser.parse(source)
            let collection = KoalaCollection(projectId: projectId, name: "Imported cURL", items: [.request(request)])
            add([collection], projectId: projectId, appState: appState)
            return
        }

        let collections = try parseJSON(data: data)
        add(collections, projectId: projectId, appState: appState)
    }

    // MARK: - Export

    func exportCollection(_ collection: KoalaCollection, as format: ExportFormat, to url: URL) throws {
        switch format {
        case .postman:
            let data = try PostmanExporter.export(collection)
            try data.write(to: url)
        case .openapi:
            let data = try OpenAPIExporter.export(collection)
            try data.write(to: url)
        case .markdown:
            let string = try MarkdownExporter.export(collection)
            try string.write(to: url, atomically: true, encoding: .utf8)
        case .koalaNative:
            let data = try KoalaNativeExporter.export(collection)
            try data.write(to: url)
        case .har:
            let data = try HARExporter.export(collection)
            try data.write(to: url)
        }
    }

    /// Returns (data, string, fileExtension) so the caller can drive fileExporter without writing to disk first.
    func exportCollectionPayload(_ collection: KoalaCollection, as format: ExportFormat) throws -> (Data?, String?, String) {
        switch format {
        case .postman:
            return (try PostmanExporter.export(collection), nil, "json")
        case .openapi:
            return (try OpenAPIExporter.export(collection), nil, "json")
        case .markdown:
            return (nil, try MarkdownExporter.export(collection), "md")
        case .koalaNative:
            return (try KoalaNativeExporter.export(collection), nil, "json")
        case .har:
            return (try HARExporter.export(collection), nil, "har")
        }
    }

    // MARK: - Format detection

    func detectFormat(data: Data) -> ImportFormat? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if let info = obj["info"] as? [String: Any],
           let schema = info["schema"] as? String,
           schema.contains("getpostman.com") { return .postman }

        if obj["openapi"] != nil { return .openapi }
        if obj["swagger"] != nil { return .swagger }
        if (obj["_type"] as? String) == "export" { return .insomnia }
        if obj["log"] is [String: Any] { return .har }
        if obj["apidoc"] != nil || obj["x-apidog-folder"] != nil { return .apidog }
        if obj["id"] != nil && obj["projectId"] != nil && obj["items"] != nil { return .koala }

        return nil
    }

    // MARK: - Private helpers

    private func isCURL(data: Data, ext: String) -> Bool {
        guard ext == "txt" || ext == "" || ext == "curl" else { return false }
        let prefix = String(decoding: data.prefix(64), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.lowercased().hasPrefix("curl")
    }

    private func parseJSON(data: Data) throws -> [KoalaCollection] {
        guard let format = detectFormat(data: data) else {
            throw ImportExportError.unrecognizedFormat
        }
        switch format {
        case .postman:
            return [try PostmanImporter.parse(data: data)]
        case .openapi:
            return [try OpenAPIImporter.parse(data: data)]
        case .insomnia:
            return try InsomniaImporter.parse(data: data)
        case .apidog:
            return [try ApidogImporter.parse(data: data)]
        case .har:
            return [try HARImporter.parse(data: data)]
        case .swagger:
            return [try SwaggerImporter.parse(data: data)]
        case .koala:
            return [try KoalaNativeExporter.import(data)]
        }
    }

    private func add(_ collections: [KoalaCollection], projectId: UUID, appState: AppState) {
        for var col in collections {
            col.projectId = projectId
            appState.collections.append(col)
        }
        appState.saveActiveProject()
    }
}

// MARK: - ImportExportError

enum ImportExportError: LocalizedError {
    case unrecognizedFormat

    var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            return "Unrecognized file format. Supported: Postman, OpenAPI, Swagger, Insomnia, Apidog, HAR, Koala native, cURL."
        }
    }
}
