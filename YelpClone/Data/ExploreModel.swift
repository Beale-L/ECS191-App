import Observation

@Observable
final class ExploreModel {
    enum Phase {
        case loading
        case loaded(Catalog)
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private let store: any CollectionStore

    init(store: any CollectionStore) {
        self.store = store
    }

    var catalog: Catalog? {
        if case .loaded(let catalog) = phase { catalog } else { nil }
    }

    /// Loads or reloads the catalog. Existing content stays on screen while refreshing.
    func load() async {
        do {
            phase = .loaded(try await store.loadCatalog())
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Loads unless a load already finished; Explore and Favorites both call this.
    func loadIfNeeded() async {
        if case .loading = phase { await load() }
    }

    func retry() async {
        phase = .loading
        await load()
    }
}
