import SwiftUI

/// The Explore grid, filtered to the signed-in user's favorites.
struct FavoritesView: View {
    @Environment(ExploreModel.self) private var model
    @Environment(UserStore.self) private var user

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
                Text("Favorite collections to keep them here.")
            } actions: {
                Button("Sign In") { user.requestSignIn() }
                    .buttonStyle(.borderedProminent)
            }
        } else if let base = model.catalog {
            let catalog = user.catalog(from: base)
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
        } else {
            ProgressView()
        }
    }
}
