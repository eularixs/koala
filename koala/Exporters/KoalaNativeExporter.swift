import Foundation

final class KoalaNativeExporter {

    static func export(_ collection: KoalaCollection) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(collection)
        } catch {
            throw ImportError.malformed("Failed to encode collection: \(error.localizedDescription)")
        }
    }

    static func `import`(_ data: Data) throws -> KoalaCollection {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(KoalaCollection.self, from: data)
        } catch {
            throw ImportError.malformed("Failed to decode Koala native JSON: \(error.localizedDescription)")
        }
    }
}
