import Foundation

/// The parts of `seed.json` the UI tests check against. UI tests can't import
/// the app module, so they decode the same file from the source tree. This
/// works on the simulator, which can read the host file system.
struct SeedFixture: Decodable {
    struct Collection: Decodable {
        let title: String
        let tag: String
        let authorName: String
        let locationIDs: [String]
        let likeCount: Int
        let dislikeCount: Int
    }

    struct Location: Decodable {
        let id: String
        let name: String
        let address: String
        let rating: Double
        let reviewCount: Int
    }

    let collections: [Collection]
    let locations: [Location]

    static let shared: SeedFixture = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "YelpClone/Data/seed.json")
        do {
            return try JSONDecoder().decode(SeedFixture.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Couldn't load \(url.path): \(error)")
        }
    }()

    func locations(in collection: Collection) -> [Location] {
        collection.locationIDs.compactMap { id in locations.first { $0.id == id } }
    }

    /// The ten hand-written collections at the top of the grid. Tests that open
    /// every card use these; walking all 300+ would take hours.
    var handWritten: ArraySlice<Collection> { collections.prefix(10) }

    func collection(titled title: String) -> Collection {
        collections.first { $0.title == title }!
    }
}
