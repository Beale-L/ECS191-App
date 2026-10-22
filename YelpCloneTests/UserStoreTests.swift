import Foundation
import Testing
@testable import YelpClone

@MainActor
struct UserStoreTests {
    private let persistence = InMemoryUserStatePersistence()
    private let collection = MapCollection(
        id: "col-test", title: "Test", tag: "Parks", authorName: "author", description: "",
        coverImageURL: nil, locationIDs: [], likeCount: 10, dislikeCount: 2
    )

    private func signedInStore(_ name: String = "alice") -> UserStore {
        let store = UserStore(persistence: persistence)
        store.beginSession(as: name)
        return store
    }

    // MARK: Like / dislike (criteria 9 and 14)

    @Test func likeTogglesOnAndOff() {
        let store = signedInStore()
        store.perform(.react(collection.id, .like))
        #expect(store.reaction(to: collection.id) == .like)
        #expect(store.likeCount(for: collection) == 11)

        store.perform(.react(collection.id, .like))
        #expect(store.reaction(to: collection.id) == nil)
        #expect(store.likeCount(for: collection) == 10)
    }

    @Test func likeAndDislikeAreMutuallyExclusive() {
        let store = signedInStore()
        store.perform(.react(collection.id, .like))
        store.perform(.react(collection.id, .dislike))
        #expect(store.reaction(to: collection.id) == .dislike)
        #expect(store.likeCount(for: collection) == 10)
        #expect(store.dislikeCount(for: collection) == 3)

        store.perform(.react(collection.id, .like))
        #expect(store.reaction(to: collection.id) == .like)
        #expect(store.likeCount(for: collection) == 11)
        #expect(store.dislikeCount(for: collection) == 2)
    }

    @Test func favoriteToggles() {
        let store = signedInStore()
        store.perform(.favorite(collection.id))
        #expect(store.isFavorite(collection.id))
        store.perform(.favorite(collection.id))
        #expect(!store.isFavorite(collection.id))
    }

    // MARK: Saved places

    @Test func savingAPlaceDoesNotFavoriteItsCollection() {
        let store = signedInStore()
        store.perform(.savePlace("loc-central-park", from: collection.id))
        #expect(store.isSaved("loc-central-park"))
        #expect(!store.isFavorite(collection.id))
        #expect(store.savedPlaces.map(\.collectionID) == [collection.id])

        store.perform(.savePlace("loc-central-park", from: collection.id))
        #expect(!store.isSaved("loc-central-park"), "tapping Save again unsaves")
        #expect(store.savedPlaces.isEmpty)
    }

    @Test func savedPlacesAreNewestFirstAndSavedOnce() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = UserStore(persistence: persistence, now: { clock })
        store.beginSession(as: "alice")
        store.perform(.savePlace("loc-a", from: nil))
        clock += 60
        store.perform(.savePlace("loc-b", from: collection.id))
        #expect(store.savedPlaces.map(\.locationID) == ["loc-b", "loc-a"])
        #expect(store.savedPlaces.first?.savedAt == clock)
    }

    @Test func savedPlacesArePerUserAndSurviveRelaunch() {
        let store = signedInStore("alice")
        store.perform(.savePlace("loc-a", from: nil))
        store.beginSession(as: "bob")
        #expect(!store.isSaved("loc-a"), "each user has their own saved places")

        let relaunched = UserStore(persistence: persistence)
        relaunched.beginSession(as: "alice")
        #expect(relaunched.isSaved("loc-a"))
    }

    @Test func stateSavedBeforeSavedPlacesStillLoads() throws {
        let json = #"{"username":"alice","users":{"alice":{"favorites":["col-test"]}}}"#
        let state = try JSONDecoder().decode(SavedUserState.self, from: Data(json.utf8))
        #expect(state.users["alice"]?.favorites == ["col-test"])
        #expect(state.users["alice"]?.savedPlaces == [])
    }

    // MARK: Auth gate (criteria 7 and 8)

    @Test(arguments: [
        PendingAction.react("col-test", .like),
        .react("col-test", .dislike),
        .favorite("col-test"),
        .postComment("col-test", "Nice"),
        .savePlace("loc-test", from: "col-test"),
    ])
    func guestActionWaitsForSignIn(action: PendingAction) {
        let store = UserStore(persistence: persistence)
        store.perform(action)
        #expect(store.isRequestingSignIn)
        #expect(store.pending == action)
        #expect(persistence.saved == SavedUserState(), "nothing changes before sign-in")

        store.beginSession(as: "alice")
        #expect(!store.isRequestingSignIn)
        #expect(store.pending == nil)
        switch action {
        case .react(let id, let reaction): #expect(store.reaction(to: id) == reaction)
        case .favorite(let id): #expect(store.isFavorite(id))
        case .postComment(let id, let text): #expect(store.postedComments(for: id).map(\.text) == [text])
        case .savePlace(let id, _): #expect(store.isSaved(id))
        }
    }

    @Test func cancelDropsThePendingAction() {
        let store = UserStore(persistence: persistence)
        store.perform(.favorite(collection.id))
        store.cancelSignIn()
        #expect(!store.isRequestingSignIn)
        #expect(store.pending == nil)

        store.beginSession(as: "alice")
        #expect(!store.isFavorite(collection.id))
    }

    @Test func invalidUsernameDoesNotSignIn() {
        let store = UserStore(persistence: persistence)
        store.perform(.favorite(collection.id))
        #expect(throws: UserStore.AccountError.self) { try store.createAccount(username: "a b", password: "long enough") }
        #expect(!store.isSignedIn)
        #expect(store.pending != nil, "the action still waits for a valid sign-in")
    }

    @Test(arguments: [
        ("ab", false), ("abc", true), ("grace_2026", true), (String(repeating: "x", count: 20), true),
        (String(repeating: "x", count: 21), false), ("has space", false), ("émile", false), ("  padded  ", true),
    ])
    func usernameValidation(name: String, isValid: Bool) {
        #expect((UserStore.validationError(for: name) == nil) == isValid)
    }

    // MARK: Comments (criterion 11)

    @Test func commentsAreNewestFirstAndPublic() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = UserStore(persistence: persistence, now: { clock })
        let seeded = Comment(id: "seed", collectionID: collection.id, authorName: "seed", text: "Old", createdAt: .distantPast)

        store.beginSession(as: "alice")
        store.perform(.postComment(collection.id, "  First  "))
        clock += 60
        store.beginSession(as: "bob")
        store.perform(.postComment(collection.id, "Second"))
        store.signOut()

        let texts = store.allComments(for: collection.id, seeded: [seeded]).map(\.text)
        #expect(texts == ["Second", "First", "Old"], "guests see everyone's comments, newest first, trimmed")
    }

    @Test func blankCommentIsIgnored() {
        let store = signedInStore()
        store.perform(.postComment(collection.id, "   \n "))
        #expect(store.postedComments(for: collection.id).isEmpty)
    }

    // MARK: Persistence and per-user data (criterion 12)

    @Test func stateSurvivesRelaunch() {
        let store = signedInStore()
        store.perform(.react(collection.id, .dislike))
        store.perform(.favorite(collection.id))
        store.perform(.postComment(collection.id, "Hello"))

        let relaunched = UserStore(persistence: persistence)
        #expect(relaunched.username == "alice")
        #expect(relaunched.reaction(to: collection.id) == .dislike)
        #expect(relaunched.isFavorite(collection.id))
        #expect(relaunched.postedComments(for: collection.id).map(\.text) == ["Hello"])
    }

    @Test func signOutReturnsToGuestAndDataIsPerUser() {
        let store = signedInStore("alice")
        store.perform(.favorite(collection.id))
        store.signOut()
        #expect(!store.isSignedIn)
        #expect(!store.isFavorite(collection.id))

        store.beginSession(as: "bob")
        #expect(!store.isFavorite(collection.id), "bob doesn't see alice's favorites")

        store.beginSession(as: "alice")
        #expect(store.isFavorite(collection.id), "alice's favorites come back")
    }

    @Test func fileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/user-state.json")
        let file = FileUserStatePersistence(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(file.load() == SavedUserState(), "a missing file loads as a fresh install")

        let store = UserStore(persistence: file)
        store.beginSession(as: "alice")
        store.perform(.postComment(collection.id, "Saved"))
        store.perform(.react(collection.id, .like))

        let reloaded = FileUserStatePersistence(url: url).load()
        #expect(reloaded == store.state)

        file.reset()
        #expect(file.load() == SavedUserState())
    }
}
