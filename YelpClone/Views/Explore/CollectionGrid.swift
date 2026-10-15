import SwiftUI

/// Two-column grid of collection cards. Used by Explore and Favorites.
struct CollectionGrid: View {
    let catalog: Catalog
    let collections: [MapCollection]
    let notes: [MapCollection.ID: String]

    @Environment(UserStore.self) private var user

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top),
    ]

    init(catalog: Catalog, collections: [MapCollection]? = nil, notes: [MapCollection.ID: String] = [:]) {
        self.catalog = catalog
        self.collections = collections ?? catalog.collections
        self.notes = notes
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(collections) { collection in
                    let locations = catalog.locations(in: collection)
                    NavigationLink(value: collection) {
                        CollectionCard(
                            collection: collection,
                            locations: locations,
                            likeCount: user.likeCount(for: collection),
                            note: notes[collection.id]
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(
                            user.isFavorite(collection.id) ? "Unfavorite" : "Favorite",
                            systemImage: user.isFavorite(collection.id) ? "heart.slash" : "heart"
                        ) {
                            user.perform(.favorite(collection.id))
                        }
                        ShareLink(
                            item: CollectionLink.url(for: collection, places: locations),
                            subject: Text(collection.title),
                            message: Text(CollectionLink.message(for: collection, placeCount: locations.count)),
                            preview: CollectionLink.preview(for: collection)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

extension View {
    /// Opens a `MapCollection` navigation value on its map.
    func collectionMapDestination() -> some View {
        navigationDestination(for: MapCollection.self) { collection in
            CollectionMapDestination(collection: collection)
        }
    }
}

/// Shows the latest version of a collection, so edits appear right away,
/// and closes itself if the collection is deleted.
private struct CollectionMapDestination: View {
    let collection: MapCollection
    @Environment(ExploreModel.self) private var model
    @Environment(UserStore.self) private var user
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let catalog = model.catalog.map { user.catalog(from: $0) }
        if let current = catalog?.collection(id: collection.id) {
            CollectionMapView(
                collection: current,
                locations: catalog?.locations(in: current) ?? [],
                seededComments: catalog?.comments(for: current.id) ?? []
            )
            // A new identity when places change, so the camera refits them.
            .id(current.locationIDs)
        } else {
            ContentUnavailableView("Collection Deleted", systemImage: "trash")
                .onAppear { dismiss() }
        }
    }
}
