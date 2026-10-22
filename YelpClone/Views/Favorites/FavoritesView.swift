import SwiftUI

/// The signed-in user's favorite collections, and places they saved on their own.
struct FavoritesView: View {
    enum Shelf: String, CaseIterable, Identifiable {
        case collections = "Collections"
        case places = "Places"
        var id: Self { self }
    }

    @Environment(ExploreModel.self) private var model
    @Environment(UserStore.self) private var user
    @State private var shelf = Shelf.collections

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Favorites")
                .collectionMapDestination()
        }
        .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if !user.isSignedIn {
            ContentUnavailableView {
                Label("Sign In to See Favorites", systemImage: "heart")
            } description: {
                Text("Favorite collections and save places to keep them here.")
            } actions: {
                Button("Sign In") { user.requestSignIn() }
                    .buttonStyle(.borderedProminent)
            }
        } else if let base = model.catalog {
            let catalog = user.catalog(from: base)
            VStack(spacing: 0) {
                Picker("Show", selection: $shelf) {
                    ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch shelf {
                case .collections: collections(in: catalog)
                case .places: SavedPlacesList(catalog: catalog)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func collections(in catalog: Catalog) -> some View {
        let favorites = catalog.collections.filter { user.isFavorite($0.id) }
        if favorites.isEmpty {
            ContentUnavailableView(
                "No Favorites Yet",
                systemImage: "heart",
                description: Text("Tap the heart on a collection, or hold down its card, to save it here.")
            )
        } else {
            CollectionGrid(catalog: catalog, collections: favorites)
        }
    }
}

/// Places saved one at a time, newest first. Tapping one shows its details.
private struct SavedPlacesList: View {
    let catalog: Catalog

    @Environment(UserStore.self) private var user
    @State private var selected: Location?

    private struct Row: Identifiable {
        let location: Location
        /// Where it was saved from, if that collection still exists.
        let collection: MapCollection?
        var id: Location.ID { location.id }
    }

    var body: some View {
        // Skip places that no longer exist, such as an added place whose data was lost.
        let rows = user.savedPlaces.compactMap { saved in
            catalog.location(id: saved.locationID).map {
                Row(location: $0, collection: saved.collectionID.flatMap(catalog.collection(id:)))
            }
        }
        Group {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No Saved Places",
                    systemImage: "bookmark",
                    description: Text("Tap a pin on any collection's map, then tap Save to keep just that place here.")
                )
            } else {
                List(rows) { row in
                    Button {
                        selected = row.location
                    } label: {
                        SavedPlaceRow(location: row.location, collection: row.collection)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button("Remove", systemImage: "bookmark.slash", role: .destructive) {
                            user.perform(.savePlace(row.location.id, from: nil))
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $selected) { location in
            LocationSheet(location: location)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct SavedPlaceRow: View {
    let location: Location
    let collection: MapCollection?

    var body: some View {
        let style = collection.map { TagStyle(tag: $0.tag) }
        HStack(spacing: 12) {
            Image(systemName: style?.symbol ?? "mappin")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(style?.color ?? .accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.headline)
                Text(location.category)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let collection {
                    Text("From \(collection.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
