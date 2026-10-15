import Foundation
import Testing
@testable import YelpClone

@MainActor
struct M1BrowseTests {
    /// Exit criterion 6: each Apple Maps link points at its own location.
    @Test func appleMapsURLsMatchLocations() throws {
        let seed = try LocalCollectionStore().loadSeed()
        for location in seed.locations {
            let items = URLComponents(url: location.appleMapsURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(location.appleMapsURL.host == "maps.apple.com")
            #expect(items.first { $0.name == "ll" }?.value == "\(location.latitude),\(location.longitude)", "\(location.id)")
            #expect(items.first { $0.name == "q" }?.value == location.name, "\(location.id)")
        }
    }

    /// A load failure shows the error state, and Retry recovers.
    @Test func failedLoadShowsErrorAndRetryRecovers() async {
        let store = FlakyStore()
        let model = ExploreModel(store: store)

        await model.load()
        guard case .failed(let message) = model.phase else {
            Issue.record("expected the failed phase, got \(model.phase)")
            return
        }
        #expect(message == CollectionStoreError.missingSeedFile.errorDescription)

        store.state.shouldFail = false
        await model.retry()
        #expect(model.catalog?.collections.isEmpty == false)
    }
}

/// Fails until told otherwise, then loads the bundled seed.
private struct FlakyStore: CollectionStore {
    final class State { var shouldFail = true }
    let state = State()

    func loadCatalog() async throws -> Catalog {
        if state.shouldFail { throw CollectionStoreError.missingSeedFile }
        return try await LocalCollectionStore().loadCatalog()
    }
}
