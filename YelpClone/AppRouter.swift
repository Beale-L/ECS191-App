import Foundation
import Observation

/// App-wide navigation: the selected tab, the Explore stack, the New
/// Collection sheet, and incoming share links.
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case explore, favorites, profile
    }

    var tab: Tab = .explore
    var explorePath: [MapCollection] = []
    var isComposing = false
    /// Shown in an alert when a share link can't be opened.
    var linkError: String?

    /// A guest tapped New Collection; open the editor once they've signed in.
    private var composeAfterSignIn = false

    /// Opens a collection's map on the Explore tab.
    func show(_ collection: MapCollection) {
        tab = .explore
        explorePath = [collection]
    }

    /// Creating a collection needs an account, so a guest signs in first.
    func startNewCollection(user: UserStore) {
        if user.isSignedIn {
            isComposing = true
        } else {
            composeAfterSignIn = true
            user.requestSignIn()
        }
    }

    /// Called once the sign-in sheet has finished dismissing, so the editor
    /// isn't presented while another sheet is still animating away.
    func signInSheetDidDismiss(user: UserStore) {
        guard composeAfterSignIn else { return }
        composeAfterSignIn = false
        if user.isSignedIn { isComposing = true }
    }

    /// Opens a share link: shows the collection if this device has it,
    /// otherwise keeps a copy and shows that.
    func open(_ url: URL, base: Catalog?, user: UserStore) {
        guard let decoded = CollectionLink.decode(url) else {
            linkError = "This link doesn't point to a collection."
            return
        }
        guard let base else {
            linkError = "Collections couldn't be loaded, so this link can't be opened right now."
            return
        }
        let shared = decoded.collection
        if let existing = user.catalog(from: base).collection(id: shared.id) {
            show(existing)
            return
        }
        // Places the sender added travel in the link; keep the ones this collection uses.
        user.addPlaces(decoded.places.filter { shared.locationIDs.contains($0.id) })
        // Drop places this device still doesn't have.
        let catalog = user.catalog(from: base)
        let knownIDs = shared.locationIDs.filter { catalog.location(id: $0) != nil }
        guard !knownIDs.isEmpty else {
            linkError = "None of the places in “\(shared.title)” are available in this version of the app."
            return
        }
        let received = MapCollection(
            id: shared.id, title: shared.title, tag: shared.tag, authorName: shared.authorName,
            description: shared.description, coverImageURL: nil, locationIDs: knownIDs,
            likeCount: 0, dislikeCount: 0
        )
        user.receive(received)
        show(user.catalog(from: base).collection(id: received.id) ?? received)
    }
}
