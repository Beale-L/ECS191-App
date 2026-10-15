import Foundation
import Testing
@testable import YelpClone

@MainActor
struct SharingTests {
    private let persistence = InMemoryUserStatePersistence()
    private let base: Catalog

    init() async throws {
        base = try await LocalCollectionStore().loadCatalog()
    }

    private func draft(title: String = "Taco Tour", tag: String = "Tacos",
                       places: [String] = ["loc-dos-coyotes", "loc-redrum"]) -> CollectionDraft {
        var draft = CollectionDraft()
        draft.title = title
        draft.tag = tag
        draft.description = "  Every taco worth the trip.  "
        draft.locationIDs = places
        return draft
    }

    private func signedInStore(_ name: String = "alice") -> UserStore {
        let store = UserStore(persistence: persistence)
        store.beginSession(as: name)
        return store
    }

    // MARK: Links

    @Test func linkRoundTripsEveryField() throws {
        let collection = try #require(base.collection(id: "col-pizza-night"))
        let url = CollectionLink.url(for: collection)
        #expect(url.scheme == "daviscollections")
        #expect(url.host == "collection")

        let decoded = try #require(CollectionLink.decode(url)?.collection)
        #expect(decoded.id == collection.id)
        #expect(decoded.title == collection.title)
        #expect(decoded.tag == collection.tag)
        #expect(decoded.authorName == collection.authorName)
        #expect(decoded.description == collection.description)
        #expect(decoded.locationIDs == collection.locationIDs)
        #expect(decoded.likeCount == 0, "likes stay on the sender's device")
    }

    @Test func linkSurvivesUnicodeAndPunctuation() throws {
        let collection = MapCollection(
            id: "user-1", title: "Café crawl: “best” crêpes & more?", tag: "Brunch", authorName: "zoë",
            description: "Line 1\nLine 2 /+=", coverImageURL: nil, locationIDs: ["loc-crepeville"], likeCount: 9, dislikeCount: 1
        )
        let decoded = try #require(CollectionLink.decode(CollectionLink.url(for: collection))?.collection)
        #expect(decoded.title == collection.title)
        #expect(decoded.description == collection.description)
        #expect(decoded.authorName == "zoë")
    }

    @Test(arguments: [
        "https://example.com/collection?data=abc",
        "daviscollections://other?data=abc",
        "daviscollections://collection",
        "daviscollections://collection?data=not-base64!!",
        "daviscollections://collection?data=e30",  // "{}"
    ])
    func invalidLinksAreRejected(link: String) throws {
        #expect(CollectionLink.decode(try #require(URL(string: link))) == nil)
    }

    // MARK: Drafts

    @Test func draftValidation() {
        #expect(draft().isValid)
        #expect(draft(title: "ab").problems == [.title])
        #expect(draft(title: String(repeating: "x", count: 61)).problems == [.title])
        #expect(draft(tag: " x ").problems == [.tag])
        #expect(draft(places: []).problems == [.places])

        var long = draft()
        long.description = String(repeating: "x", count: 281)
        #expect(long.problems == [.description])
    }

    @Test func togglePlaceAddsAndRemoves() {
        var draft = CollectionDraft()
        draft.togglePlace("a")
        draft.togglePlace("b")
        draft.togglePlace("a")
        #expect(draft.locationIDs == ["b"])
    }

    // MARK: Creating, editing, deleting

    @Test func createdCollectionIsPublishedFirstAndSearchable() throws {
        let store = signedInStore()
        let created = try #require(store.saveCollection(draft()))
        #expect(created.id.hasPrefix("user-"))
        #expect(created.authorName == "alice")
        #expect(created.description == "Every taco worth the trip.", "text is trimmed")
        #expect(created.createdAt != nil)

        let catalog = store.catalog(from: base)
        #expect(catalog.collections.first?.id == created.id)
        #expect(catalog.collections.count == base.collections.count + 1)
        #expect(catalog.search("tacos").map(\.collection.id) == [created.id], "findable by its label")
        #expect(store.myCollections.map(\.id) == [created.id])
        #expect(store.isAuthor(of: created.id))
    }

    @Test func guestsAndInvalidDraftsCantSave() {
        let guest = UserStore(persistence: persistence)
        #expect(guest.saveCollection(draft()) == nil)

        let store = signedInStore()
        #expect(store.saveCollection(draft(places: [])) == nil)
        #expect(store.publishedCollections.isEmpty)
    }

    @Test func editingKeepsIdentityAndCounts() throws {
        let store = signedInStore()
        let created = try #require(store.saveCollection(draft()))

        var edit = CollectionDraft(editing: created)
        edit.title = "Taco Tour, Revised"
        edit.tag = "Mexican"
        edit.locationIDs = ["loc-dos-coyotes"]
        let updated = try #require(store.saveCollection(edit))

        #expect(updated.id == created.id)
        #expect(updated.createdAt == created.createdAt)
        #expect(store.publishedCollections.count == 1)
        #expect(store.catalog(from: base).collection(id: created.id)?.title == "Taco Tour, Revised")
        #expect(store.catalog(from: base).collection(id: created.id)?.locationIDs == ["loc-dos-coyotes"])
    }

    @Test func onlyTheAuthorCanEditOrDelete() throws {
        let store = signedInStore("alice")
        let created = try #require(store.saveCollection(draft()))

        store.beginSession(as: "bob")
        #expect(!store.isAuthor(of: created.id))
        var edit = CollectionDraft(editing: created)
        edit.title = "Hijacked"
        #expect(store.saveCollection(edit) == nil)
        store.deleteCollection(created.id)
        #expect(store.publishedCollections.map(\.title) == ["Taco Tour"], "bob can see it but not change it")
    }

    @Test func deletingRemovesItEverywhere() throws {
        let store = signedInStore("alice")
        let created = try #require(store.saveCollection(draft()))
        store.beginSession(as: "bob")
        store.perform(.favorite(created.id))
        store.perform(.react(created.id, .like))

        store.beginSession(as: "alice")
        store.deleteCollection(created.id)
        #expect(store.publishedCollections.isEmpty)

        store.beginSession(as: "bob")
        #expect(!store.isFavorite(created.id))
        #expect(store.reaction(to: created.id) == nil)
    }

    // MARK: Receiving links

    @Test func receivingKeepsOneCopyForEveryone() {
        let store = UserStore(persistence: persistence)
        let shared = MapCollection(id: "user-from-elsewhere", title: "Shared", tag: "Tacos", authorName: "carol",
                                   description: "", coverImageURL: nil, locationIDs: ["loc-redrum"], likeCount: 0, dislikeCount: 0)
        store.receive(shared)
        store.receive(shared)
        #expect(store.publishedCollections.map(\.id) == ["user-from-elsewhere"])
        #expect(!store.isAuthor(of: shared.id))

        store.beginSession(as: "dave")
        #expect(store.catalog(from: base).collection(id: shared.id) != nil, "received collections are public on the device")
    }

    @Test func routerOpensKnownCollectionsWithoutCopying() throws {
        let store = UserStore(persistence: persistence)
        let router = AppRouter()
        router.tab = .profile
        let pizza = try #require(base.collection(id: "col-pizza-night"))

        router.open(CollectionLink.url(for: pizza), base: base, user: store)
        #expect(router.tab == .explore)
        #expect(router.explorePath.map(\.id) == ["col-pizza-night"])
        #expect(store.publishedCollections.isEmpty, "seeded collections aren't duplicated")
    }

    @Test func routerReceivesNewCollectionsAndDropsUnknownPlaces() throws {
        let store = UserStore(persistence: persistence)
        let router = AppRouter()
        let shared = MapCollection(id: "user-abc", title: "From a Friend", tag: "Tacos", authorName: "carol", description: "",
                                   coverImageURL: nil, locationIDs: ["loc-redrum", "loc-from-the-future"], likeCount: 0, dislikeCount: 0)

        router.open(CollectionLink.url(for: shared), base: base, user: store)
        #expect(router.linkError == nil)
        #expect(router.explorePath.first?.id == "user-abc")
        #expect(store.catalog(from: base).collection(id: "user-abc")?.locationIDs == ["loc-redrum"])

        store.beginSession(as: "erin")
        store.perform(.favorite("user-abc"))
        #expect(store.isFavorite("user-abc"), "a received collection can be favorited")
    }

    @Test func routerReportsUnusableLinks() throws {
        let store = UserStore(persistence: persistence)
        let router = AppRouter()

        router.open(try #require(URL(string: "daviscollections://collection?data=bad")), base: base, user: store)
        #expect(router.linkError != nil)

        router.linkError = nil
        let noKnownPlaces = MapCollection(id: "user-x", title: "Mystery", tag: "Tacos", authorName: "carol", description: "",
                                          coverImageURL: nil, locationIDs: ["loc-unknown"], likeCount: 0, dislikeCount: 0)
        router.open(CollectionLink.url(for: noKnownPlaces), base: base, user: store)
        #expect(router.linkError != nil)
        #expect(store.publishedCollections.isEmpty)
        #expect(router.explorePath.isEmpty)
    }

    @Test func newCollectionWaitsForSignInToFinish() {
        let store = UserStore(persistence: persistence)
        let router = AppRouter()

        router.startNewCollection(user: store)
        #expect(!router.isComposing)
        #expect(store.isRequestingSignIn)

        store.beginSession(as: "frank")
        #expect(!router.isComposing, "not until the sign-in sheet has dismissed")
        router.signInSheetDidDismiss(user: store)
        #expect(router.isComposing)
    }

    @Test func cancellingSignInDoesNotOpenTheEditor() {
        let store = UserStore(persistence: persistence)
        let router = AppRouter()
        router.startNewCollection(user: store)
        store.cancelSignIn()
        router.signInSheetDidDismiss(user: store)
        #expect(!router.isComposing)
    }

    // MARK: Persistence

    @Test func collectionsSurviveRelaunch() throws {
        let store = signedInStore()
        let created = try #require(store.saveCollection(draft()))
        let relaunched = UserStore(persistence: persistence)
        #expect(relaunched.myCollections == [created])
    }

    @Test func filesSavedBeforeCollectionsExistedStillLoad() throws {
        let oldFile = Data(#"{"username":"alice","users":{"alice":{"reactions":{},"favorites":["col-brunch"],"comments":[]}}}"#.utf8)
        let state = try JSONDecoder().decode(SavedUserState.self, from: oldFile)
        #expect(state.username == "alice")
        #expect(state.users["alice"]?.favorites == ["col-brunch"])
        #expect(state.users["alice"]?.collections == [])
        #expect(state.receivedCollections == [])
    }
}
