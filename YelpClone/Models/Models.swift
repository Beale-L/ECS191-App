import CoreLocation
import Foundation

/// A user-made "map": a named set of locations under one tag, e.g. "Parks".
struct MapCollection: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let tag: String
    let authorName: String
    let description: String
    let coverImageURL: URL?
    let locationIDs: [Location.ID]
    let likeCount: Int
    let dislikeCount: Int
    /// Set for collections made in the app; seeded ones have none.
    var createdAt: Date? = nil
}

struct Location: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let category: String
    let address: String
    let latitude: Double
    let longitude: Double
    /// 0–5 stars.
    let rating: Double
    let reviewCount: Int
    /// 1–4 ($–$$$$). `nil` for free places such as parks.
    let priceLevel: Int?
    let photoURL: URL?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Places people add from Apple Maps or by dropping a pin use this ID prefix.
    static let addedIDPrefix = "added-"

    /// Added by a user rather than bundled. These have no rating yet.
    var isUserAdded: Bool { id.hasPrefix(Self.addedIDPrefix) }

    /// A place a user added, with no rating or price.
    static func userAdded(id: Location.ID = addedIDPrefix + UUID().uuidString, name: String, category: String,
                          address: String, coordinate: CLLocationCoordinate2D) -> Location {
        Location(
            id: id, name: name, category: category, address: address,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            rating: 0, reviewCount: 0, priceLevel: nil, photoURL: nil
        )
    }

    /// Apple Maps link that drops a pin labeled with this location's name.
    var appleMapsURL: URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: name),
        ]
        return components.url!
    }
}

struct Comment: Identifiable, Hashable, Codable {
    let id: String
    let collectionID: MapCollection.ID
    let authorName: String
    let text: String
    let createdAt: Date
}

enum Reaction: String, Codable {
    case like
    case dislike
}

/// Everything the browse screens need, with locations indexed by ID.
struct Catalog {
    let collections: [MapCollection]
    /// Every bundled place, sorted by name.
    let allLocations: [Location]
    private let locationsByID: [Location.ID: Location]
    private let commentsByCollection: [MapCollection.ID: [Comment]]

    init(collections: [MapCollection], locations: [Location], comments: [Comment] = []) {
        self.collections = collections
        self.allLocations = locations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.locationsByID = Dictionary(locations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.commentsByCollection = Dictionary(grouping: comments, by: \.collectionID)
    }

    private init(collections: [MapCollection], locationsByID: [Location.ID: Location], comments: [MapCollection.ID: [Comment]]) {
        self.collections = collections
        self.allLocations = locationsByID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.locationsByID = locationsByID
        self.commentsByCollection = comments
    }

    /// This catalog with `extra` collections first and user-added `places`
    /// included. Extras replace any seeded collection with the same ID.
    func adding(_ extra: [MapCollection], places: [Location] = []) -> Catalog {
        guard !extra.isEmpty || !places.isEmpty else { return self }
        let extraIDs = Set(extra.map(\.id))
        var locations = locationsByID
        for place in places where locations[place.id] == nil { locations[place.id] = place }
        return Catalog(
            collections: extra + collections.filter { !extraIDs.contains($0.id) },
            locationsByID: locations,
            comments: commentsByCollection
        )
    }

    func collection(id: MapCollection.ID) -> MapCollection? {
        collections.first { $0.id == id }
    }

    func location(id: Location.ID) -> Location? {
        locationsByID[id]
    }

    func locations(in collection: MapCollection) -> [Location] {
        collection.locationIDs.compactMap { locationsByID[$0] }
    }

    /// Seeded comments only; `UserStore` adds the ones posted on this device.
    func comments(for collectionID: MapCollection.ID) -> [Comment] {
        commentsByCollection[collectionID] ?? []
    }

    /// Collections where every word of the query appears in the title, tag,
    /// author, or description, or in the name or category of one of its places.
    /// Ignores case, accents, and apostrophes. An empty query matches everything.
    func search(_ query: String) -> [SearchResult] {
        let words = Self.normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else {
            return collections.map { SearchResult(collection: $0, matchingPlaces: []) }
        }
        return collections.compactMap { collection in
            let ownText = Self.normalized([collection.title, collection.tag, collection.authorName, collection.description].joined(separator: " "))
            let places = locations(in: collection)
            let placeText = places.map { Self.normalized("\($0.name) \($0.category)") }
            let unmatchedByCollection = words.filter { !ownText.contains($0) }
            guard unmatchedByCollection.allSatisfy({ word in placeText.contains { $0.contains(word) } }) else { return nil }
            // Explain matches the card itself doesn't show.
            let matchingPlaces = zip(places, placeText)
                .filter { _, text in unmatchedByCollection.contains { text.contains($0) } }
                .map { place, _ in place.name }
            return SearchResult(collection: collection, matchingPlaces: matchingPlaces)
        }
    }

    /// Lowercased, with accents and apostrophes removed, for matching search text.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0 != "'" && $0 != "’" }
    }
}

struct SearchResult: Identifiable {
    let collection: MapCollection
    /// Names of places that matched words the collection's own text didn't.
    let matchingPlaces: [String]

    var id: MapCollection.ID { collection.id }
}
