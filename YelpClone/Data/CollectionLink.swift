import Foundation
import SwiftUI

/// Share links for collections.
///
/// Stage 1 has no server, so a link carries the whole collection, encoded in
/// the URL. Places are bundled, so any copy of the app can rebuild it:
/// `daviscollections://collection?data=<base64url JSON>`.
enum CollectionLink {
    static let scheme = "daviscollections"

    /// What a link carries. Likes, dislikes, and comments stay on the sender's device.
    private struct Payload: Codable {
        let id: String
        let title: String
        let tag: String
        let authorName: String
        let description: String
        let locationIDs: [String]
        /// Full details for user-added places, which the recipient won't have.
        /// Missing from links made before places could be added.
        let places: [Place]?
    }

    private struct Place: Codable {
        let id: String
        let name: String
        let category: String
        let address: String
        let latitude: Double
        let longitude: Double
    }

    /// A collection decoded from a link, plus the user-added places it uses.
    struct Shared {
        let collection: MapCollection
        let places: [Location]
    }

    /// `places` are the collection's places; user-added ones are embedded in the link.
    static func url(for collection: MapCollection, places: [Location] = []) -> URL {
        let added = places.filter { $0.isUserAdded && collection.locationIDs.contains($0.id) }
        let payload = Payload(
            id: collection.id,
            title: collection.title,
            tag: collection.tag,
            authorName: collection.authorName,
            description: collection.description,
            locationIDs: collection.locationIDs,
            places: added.isEmpty ? nil : added.map {
                Place(id: $0.id, name: $0.name, category: $0.category, address: $0.address,
                      latitude: $0.latitude, longitude: $0.longitude)
            }
        )
        // Encoding plain strings can't fail.
        let json = try! JSONEncoder().encode(payload)
        var components = URLComponents()
        components.scheme = scheme
        components.host = "collection"
        components.queryItems = [URLQueryItem(name: "data", value: base64URLEncoded(json))]
        return components.url!
    }

    /// The collection a link describes, or nil if it isn't a valid collection link.
    /// Received collections start with no likes or dislikes.
    static func decode(_ url: URL) -> Shared? {
        guard url.scheme == scheme, url.host == "collection",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "data" })?.value,
              let json = base64URLDecoded(value),
              let payload = try? JSONDecoder().decode(Payload.self, from: json),
              !payload.id.isEmpty, !payload.title.isEmpty
        else { return nil }

        let collection = MapCollection(
            id: payload.id,
            title: payload.title,
            tag: payload.tag,
            authorName: payload.authorName,
            description: payload.description,
            coverImageURL: nil,
            locationIDs: payload.locationIDs,
            likeCount: 0,
            dislikeCount: 0
        )
        // Only accept embedded places under the user-added prefix, so a link
        // can't replace a bundled place.
        let places = (payload.places ?? []).map {
            Location(id: $0.id, name: $0.name, category: $0.category, address: $0.address,
                     latitude: $0.latitude, longitude: $0.longitude,
                     rating: 0, reviewCount: 0, priceLevel: nil, photoURL: nil)
        }.filter(\.isUserAdded)
        return Shared(collection: collection, places: places)
    }

    /// Shows the collection's title and tag icon in the share sheet instead of the raw link.
    static func preview(for collection: MapCollection) -> SharePreview<Image, Never> {
        SharePreview(collection.title, image: icon(for: collection.tag))
    }

    /// The share sheet can't draw SF Symbols, so render the tag icon to a bitmap.
    private static func icon(for tag: String) -> Image {
        let style = TagStyle(tag: tag)
        let tile = Image(systemName: style.symbol)
            .font(.system(size: 52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 120, height: 120)
            .background(style.color.gradient)
        let renderer = ImageRenderer(content: tile)
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: style.symbol)
    }

    /// The text that goes with a link in the share sheet.
    static func message(for collection: MapCollection, placeCount: Int) -> String {
        let places = placeCount == 1 ? "1 place" : "\(placeCount) places"
        return "“\(collection.title)” by \(collection.authorName): \(places) in Davis tagged \(collection.tag)."
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecoded(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
