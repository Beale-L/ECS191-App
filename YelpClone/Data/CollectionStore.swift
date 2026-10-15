import Foundation

/// Source of collections and locations. Stage 1 reads bundled JSON; a backend
/// implementation can replace `LocalCollectionStore` later without view changes.
protocol CollectionStore {
    func loadCatalog() async throws -> Catalog
}

/// The shape of `seed.json`.
struct SeedFile: Codable {
    let collections: [MapCollection]
    let locations: [Location]
    let comments: [Comment]
}

enum CollectionStoreError: LocalizedError {
    case missingSeedFile

    var errorDescription: String? {
        switch self {
        case .missingSeedFile: "The bundled collection data is missing."
        }
    }
}

struct LocalCollectionStore: CollectionStore {
    var bundle: Bundle = .main
    var resourceName = "seed"

    func loadSeed() throws -> SeedFile {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CollectionStoreError.missingSeedFile
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SeedFile.self, from: Data(contentsOf: url))
    }

    func loadCatalog() async throws -> Catalog {
        let seed = try loadSeed()
        return Catalog(collections: seed.collections, locations: seed.locations, comments: seed.comments)
    }
}
