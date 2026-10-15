import SwiftUI

/// Landing page: a grid of collections that opens each one on a map.
struct ExploreView: View {
    @Environment(ExploreModel.self) private var model
    @Environment(UserStore.self) private var user
    @Environment(AppRouter.self) private var router
    @State private var query = ""

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.explorePath) {
            content
                .navigationTitle("Explore")
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Collections, tags, or places")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Collection", systemImage: "plus") {
                            router.startNewCollection(user: user)
                        }
                    }
                }
                .collectionMapDestination()
        }
        .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Loading collections…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load Collections", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await model.retry() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let base):
            // Seeded collections plus ones made or received on this device.
            let catalog = user.catalog(from: base)
            if catalog.collections.isEmpty {
                ScrollView {
                    ContentUnavailableView(
                        "No Collections Yet",
                        systemImage: "map",
                        description: Text("Collections people share will show up here.")
                    )
                    .containerRelativeFrame(.vertical)
                }
                .refreshable { await model.load() }
            } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                CollectionGrid(catalog: catalog)
                    .refreshable { await model.load() }
            } else {
                let results = catalog.search(query)
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    CollectionGrid(catalog: catalog, collections: results.map(\.collection), notes: Self.notes(for: results))
                }
            }
        }
    }

    /// "Includes Temple Coffee Roasters" for cards that matched by place.
    private static func notes(for results: [SearchResult]) -> [MapCollection.ID: String] {
        var notes: [MapCollection.ID: String] = [:]
        for result in results {
            guard let first = result.matchingPlaces.first else { continue }
            let others = result.matchingPlaces.count - 1
            notes[result.id] = others == 0 ? "Includes \(first)" : "Includes \(first) and \(others) more"
        }
        return notes
    }
}

#Preview {
    ExploreView()
        .environment(ExploreModel(store: LocalCollectionStore()))
        .environment(UserStore(persistence: InMemoryUserStatePersistence()))
        .environment(AppRouter())
}
