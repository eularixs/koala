import Foundation

// MARK: - GraphQL Type Kind

enum GraphQLTypeKind: String, Codable, Hashable {
    case scalar      = "SCALAR"
    case object      = "OBJECT"
    case interface   = "INTERFACE"
    case union       = "UNION"
    case enumKind    = "ENUM"
    case inputObject = "INPUT_OBJECT"
    case list        = "LIST"
    case nonNull     = "NON_NULL"
}

// MARK: - Type Reference (recursive)

/// A lightweight recursive reference used in field args + field types.
/// Mirrors GraphQL introspection `__Type` ref shape: { kind, name, ofType }.
final class GraphQLTypeRef: Codable, Hashable {
    var kind: GraphQLTypeKind
    var name: String?
    var ofType: GraphQLTypeRef?

    init(kind: GraphQLTypeKind, name: String? = nil, ofType: GraphQLTypeRef? = nil) {
        self.kind = kind
        self.name = name
        self.ofType = ofType
    }

    enum CodingKeys: String, CodingKey { case kind, name, ofType }

    /// Unwrap NON_NULL / LIST wrappers to find underlying named type.
    var namedType: GraphQLTypeRef {
        var cur: GraphQLTypeRef = self
        while cur.name == nil, let inner = cur.ofType {
            cur = inner
        }
        return cur
    }

    var isNonNull: Bool { kind == .nonNull }
    var isList: Bool {
        if kind == .list { return true }
        if kind == .nonNull, let inner = ofType { return inner.isList }
        return false
    }

    /// Pretty-print like "[User!]!"
    var displayString: String {
        switch kind {
        case .nonNull:
            return (ofType?.displayString ?? "?") + "!"
        case .list:
            return "[" + (ofType?.displayString ?? "?") + "]"
        default:
            return name ?? "?"
        }
    }

    // Hashable
    static func == (lhs: GraphQLTypeRef, rhs: GraphQLTypeRef) -> Bool {
        lhs.kind == rhs.kind && lhs.name == rhs.name && lhs.ofType == rhs.ofType
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(name)
        hasher.combine(ofType)
    }
}

// MARK: - Input Value (argument or input field)

struct GraphQLInputValue: Codable, Hashable, Identifiable {
    var name: String
    var type: GraphQLTypeRef
    var defaultValue: String?

    var id: String { name }
}

// MARK: - Field

struct GraphQLField: Codable, Hashable, Identifiable {
    var name: String
    var args: [GraphQLInputValue]
    var type: GraphQLTypeRef

    var id: String { name }
}

// MARK: - Enum Value

struct GraphQLEnumValue: Codable, Hashable, Identifiable {
    var name: String
    var id: String { name }
}

// MARK: - Type (top-level)

struct GraphQLType: Codable, Hashable, Identifiable {
    var kind: GraphQLTypeKind
    var name: String?
    var fields: [GraphQLField]?
    var inputFields: [GraphQLInputValue]?
    var enumValues: [GraphQLEnumValue]?

    var id: String { name ?? UUID().uuidString }
}

// MARK: - Schema

struct GraphQLSchema: Hashable {
    var queryRoot: GraphQLType?
    var mutationRoot: GraphQLType?
    var types: [GraphQLType]

    private static let introspectionQuery: String = """
    query IntrospectionQuery {
      __schema {
        queryType { name }
        mutationType { name }
        types {
          kind
          name
          fields {
            name
            args {
              name
              defaultValue
              type { ...TypeRef }
            }
            type { ...TypeRef }
          }
          inputFields {
            name
            defaultValue
            type { ...TypeRef }
          }
          enumValues { name }
        }
      }
    }

    fragment TypeRef on __Type {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                  ofType {
                    kind
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    static var query: String { introspectionQuery }

    // MARK: Parse

    private struct IntrospectionEnvelope: Codable {
        var data: IntrospectionData?
        var errors: [GraphQLErrorEntry]?
    }
    private struct IntrospectionData: Codable {
        var __schema: RawSchema
    }
    private struct RawSchema: Codable {
        var queryType: RootTypeName?
        var mutationType: RootTypeName?
        var types: [GraphQLType]
    }
    private struct RootTypeName: Codable { var name: String? }
    private struct GraphQLErrorEntry: Codable { var message: String }

    static func parse(_ data: Data) throws -> GraphQLSchema {
        let decoder = JSONDecoder()
        let envelope: IntrospectionEnvelope
        do {
            envelope = try decoder.decode(IntrospectionEnvelope.self, from: data)
        } catch {
            throw GraphQLIntrospectionError.schemaParseError(error.localizedDescription)
        }

        if let errors = envelope.errors, !errors.isEmpty {
            throw GraphQLIntrospectionError.schemaParseError(
                errors.map { $0.message }.joined(separator: "; ")
            )
        }

        guard let raw = envelope.data?.__schema else {
            throw GraphQLIntrospectionError.schemaParseError("Missing __schema in response")
        }

        let typesByName: [String: GraphQLType] = Dictionary(
            uniqueKeysWithValues: raw.types.compactMap { t in
                guard let n = t.name else { return nil }
                return (n, t)
            }
        )

        let queryRoot   = raw.queryType?.name.flatMap { typesByName[$0] }
        let mutationRoot = raw.mutationType?.name.flatMap { typesByName[$0] }

        return GraphQLSchema(
            queryRoot: queryRoot,
            mutationRoot: mutationRoot,
            types: raw.types
        )
    }

    // MARK: Lookup

    func type(named name: String) -> GraphQLType? {
        types.first { $0.name == name }
    }
}
