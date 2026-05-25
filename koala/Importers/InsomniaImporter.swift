import Foundation

// MARK: - Insomnia v4 DTOs

private struct INExport: Decodable {
    let _type: String
    let __export_format: Int?
    let resources: [INResource]
}

private struct INResource: Decodable {
    let _id: String
    let _type: String
    let parentId: String?
    let name: String?
    let method: String?
    let url: String?
    let headers: [INHeader]?
    let parameters: [INQueryParam]?
    let body: INBody?
    let authentication: INAuthentication?
}

private struct INHeader: Decodable {
    let name: String
    let value: String
    let disabled: Bool?
}

private struct INQueryParam: Decodable {
    let name: String
    let value: String?
    let disabled: Bool?
}

private struct INBody: Decodable {
    let mimeType: String?
    let text: String?
    let params: [INBodyParam]?
}

private struct INBodyParam: Decodable {
    let name: String
    let value: String?
    let disabled: Bool?
    let type: String?
}

private struct INAuthentication: Decodable {
    let type: String?
    let token: String?
    let username: String?
    let password: String?
    let key: String?
    let value: String?
    let addTo: String?
}

// MARK: - InsomniaImporter

final class InsomniaImporter {

    static func parse(data: Data) throws -> [KoalaCollection] {
        let decoder = JSONDecoder()
        let export: INExport
        do {
            export = try decoder.decode(INExport.self, from: data)
        } catch {
            throw ImportError.malformed("Could not decode Insomnia JSON: \(error.localizedDescription)")
        }

        guard export._type == "export" else {
            throw ImportError.malformed("Expected _type 'export', got '\(export._type)'")
        }

        let workspaces = export.resources.filter { $0._type == "workspace" }
        guard !workspaces.isEmpty else {
            throw ImportError.malformed("No workspace resources found in Insomnia export")
        }

        return workspaces.map { buildCollection(workspace: $0, resources: export.resources) }
    }

    // MARK: - Private helpers

    private static func buildCollection(workspace: INResource, resources: [INResource]) -> KoalaCollection {
        let items = buildItems(parentId: workspace._id, resources: resources)
        return KoalaCollection(name: workspace.name ?? "Insomnia Import", items: items)
    }

    private static func buildItems(parentId: String, resources: [INResource]) -> [CollectionItem] {
        let children = resources.filter { $0.parentId == parentId }
        return children.compactMap { resource in
            switch resource._type {
            case "request_group":
                let nested = buildItems(parentId: resource._id, resources: resources)
                let folder = Folder(name: resource.name ?? "Group", items: nested)
                return .folder(folder)
            case "request":
                return .request(buildRequest(resource))
            default:
                return nil
            }
        }
    }

    private static func buildRequest(_ resource: INResource) -> KoalaRequest {
        let method = methodValue(resource.method ?? "GET")
        let headers = (resource.headers ?? []).map { h in
            KeyValuePair(key: h.name, value: h.value, isEnabled: !(h.disabled ?? false))
        }
        let queryParams = (resource.parameters ?? []).map { p in
            KeyValuePair(key: p.name, value: p.value ?? "", isEnabled: !(p.disabled ?? false))
        }
        return KoalaRequest(
            name: resource.name ?? "Request",
            method: method,
            url: resource.url ?? "",
            queryParams: queryParams,
            headers: headers,
            auth: mapAuth(resource.authentication),
            body: mapBody(resource.body)
        )
    }

    private static func mapAuth(_ auth: INAuthentication?) -> AuthConfig {
        guard let auth = auth else { return .none }
        switch auth.type {
        case "bearer":
            return .bearer(token: auth.token ?? "")
        case "basic":
            return .basic(username: auth.username ?? "", password: auth.password ?? "")
        case "apikey":
            let loc: APIKeyLocation = (auth.addTo == "queryParams") ? .query : .header
            return .apiKey(key: auth.key ?? "", value: auth.value ?? "", location: loc)
        default:
            return .none
        }
    }

    private static func mapBody(_ body: INBody?) -> RequestBody {
        guard let body = body else { return .none }
        let mime = body.mimeType ?? ""
        if mime.contains("application/json") {
            return .json(body.text ?? "{}")
        }
        if mime.contains("application/x-www-form-urlencoded") {
            let pairs = (body.params ?? []).map { p in
                KeyValuePair(key: p.name, value: p.value ?? "", isEnabled: !(p.disabled ?? false))
            }
            return .formURLEncoded(pairs)
        }
        if mime.contains("multipart/form-data") {
            let items = (body.params ?? []).map { p in
                MultipartItem(key: p.name, value: p.value ?? "", type: p.type == "file" ? .file : .text)
            }
            return .multipart(items)
        }
        if mime.contains("application/graphql") || mime == "graphql" {
            return .graphql(query: body.text ?? "", variables: "")
        }
        if let text = body.text, !text.isEmpty {
            return .raw(content: text, contentType: mime.isEmpty ? "text/plain" : mime)
        }
        return .none
    }

    private static func methodValue(_ raw: String) -> HTTPMethodValue {
        let upper = raw.uppercased()
        if let m = HTTPMethod(rawValue: upper) { return .standard(m) }
        return .custom(upper)
    }
}
