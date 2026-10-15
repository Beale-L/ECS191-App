import SwiftUI

@main
struct YelpCloneApp: App {
    @State private var explore = ExploreModel(store: LocalCollectionStore())
    @State private var user = UserStore.forLaunch()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(explore)
                .environment(user)
                .environment(router)
        }
    }
}

struct RootTabView: View {
    @Environment(ExploreModel.self) private var explore
    @Environment(UserStore.self) private var user
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            ExploreView()
                .tabItem { Label("Explore", systemImage: "map") }
                .tag(AppRouter.Tab.explore)
            FavoritesView()
                .tabItem { Label("Favorites", systemImage: "heart") }
                .tag(AppRouter.Tab.favorites)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppRouter.Tab.profile)
        }
        .signInGate { router.signInSheetDidDismiss(user: user) }
        .sheet(isPresented: $router.isComposing) {
            if let base = explore.catalog {
                CollectionEditor(catalog: user.catalog(from: base)) { saved in
                    router.show(saved)
                }
            }
        }
        .onOpenURL { url in
            Task {
                // A link can launch the app before collections have loaded.
                await explore.loadIfNeeded()
                router.open(url, base: explore.catalog, user: user)
            }
        }
        .alert("Can't Open Link", isPresented: Binding(
            get: { router.linkError != nil },
            set: { if !$0 { router.linkError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.linkError ?? "")
        }
    }
}

#Preview {
    RootTabView()
        .environment(ExploreModel(store: LocalCollectionStore()))
        .environment(UserStore(persistence: InMemoryUserStatePersistence()))
        .environment(AppRouter())
}
