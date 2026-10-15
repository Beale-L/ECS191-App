import CoreLocation
import Foundation
import MapKit
import Testing
@testable import YelpClone

@MainActor
struct AddedPlacesTests {
    private let persistence = InMemoryUserStatePersistence()
    private let base: Catalog

    init() async throws {
        base = try await LocalCollectionStore().loadCatalog()
    }

    private let mcdonalds = Location.userAdded(
        id: "added-mcdonalds-38.5600_-121.7600", name: "McDonald's", category: "Fast Food",
        address: "1515 W Covell Blvd, Davis", coordinate: CLLocationCoordinate2D(latitude: 38.56, longitude: -121.76)
    )

    private func draft(with places: [Location], using ids: [String]? = nil) -> CollectionDraft {
        var draft = CollectionDraft()
        draft.title = "Late Night Run"
        draft.tag = "Fast Food"
        for place in places { draft.addNewPlace(place) }
        if let ids { draft.locationIDs = ids }
        return draft
    }

    // MARK: Model

    @Test func addedPlacesAreUnratedAndMarked() {
        let pin = Location.userAdded(name: "New Spot", category: "Restaurant", address: "", coordinate: .init(latitude: 38.54, longitude: -121.74))
        #expect(pin.isUserAdded)
        #expect(pin.id.hasPrefix("added-"))
        #expect(pin.reviewCount == 0)
        #expect(pin.priceLevel == nil)
        #expect(base.allLocations.allSatisfy { !$0.isUserAdded }, "bundled places never use the added prefix")
    }

    @Test func draftHoldsNewPlacesUntilSaved() {
        var draft = CollectionDraft()
        draft.addNewPlace(mcdonalds)
        draft.addNewPlace(mcdonalds)
        #expect(draft.newPlaces == [mcdonalds])
        #expect(draft.locationIDs == [mcdonalds.id])
    }

    // MARK: Saving

    @Test func savingKeepsOnlyUsedNewPlaces() throws {
        let store = UserStore(persistence: persistence)
        store.beginSession(as: "alice")
        let unused = Location.userAdded(name: "Changed My Mind", category: "Cafe", address: "", coordinate: .init(latitude: 38.55, longitude: -121.75))
        let saved = try #require(store.saveCollection(draft(with: [mcdonalds, unused], using: [mcdonalds.id, "loc-redrum"])))

        let catalog = store.catalog(from: base)
        #expect(catalog.locations(in: saved).map(\.name) == ["McDonald's", "Redrum Burger"])
        #expect(catalog.location(id: unused.id) == nil, "a place removed before saving isn't kept")
        #expect(catalog.allLocations.contains(mcdonalds), "added places can be reused in later collections")
        #expect(catalog.search("mcdonalds").map(\.collection.id) == [saved.id], "search finds collections by added places")
    }

    @Test func cancelledDraftsLeaveNoPlacesBehind() {
        let store = UserStore(persistence: persistence)
        store.beginSession(as: "alice")
        _ = draft(with: [mcdonalds])  // never saved
        #expect(store.catalog(from: base).location(id: mcdonalds.id) == nil)
    }

    @Test func addedPlacesSurviveRelaunch() throws {
        let store = UserStore(persistence: persistence)
        store.beginSession(as: "alice")
        try #require(store.saveCollection(draft(with: [mcdonalds])))
        let relaunched = UserStore(persistence: persistence)
        #expect(relaunched.catalog(from: base).location(id: mcdonalds.id) == mcdonalds)
    }

    // MARK: Sharing

    @Test func linksCarryAddedPlaces() throws {
        let store = UserStore(persistence: persistence)
        store.beginSession(as: "alice")
        let saved = try #require(store.saveCollection(draft(with: [mcdonalds], using: [mcdonalds.id, "loc-redrum"])))
        let places = store.catalog(from: base).locations(in: saved)

        let decoded = try #require(CollectionLink.decode(CollectionLink.url(for: saved, places: places)))
        #expect(decoded.places == [mcdonalds], "only the added place is embedded; bundled ones are referenced by ID")
    }

    @Test func receivingALinkAddsItsPlaces() throws {
        let sender = MapCollection(id: "user-late", title: "Late Night Run", tag: "Fast Food", authorName: "carol",
                                   description: "", coverImageURL: nil, locationIDs: [mcdonalds.id, "loc-redrum"],
                                   likeCount: 0, dislikeCount: 0)
        let url = CollectionLink.url(for: sender, places: [mcdonalds])

        let store = UserStore(persistence: persistence)  // a different device: no McDonald's yet
        let router = AppRouter()
        router.open(url, base: base, user: store)

        #expect(router.linkError == nil)
        let catalog = store.catalog(from: base)
        let received = try #require(catalog.collection(id: "user-late"))
        #expect(catalog.locations(in: received).map(\.name) == ["McDonald's", "Redrum Burger"])
        #expect(catalog.location(id: mcdonalds.id)?.reviewCount == 0, "received added places are unrated")
    }

    @Test func linksCantReplaceBundledPlaces() throws {
        // A hand-made link that tries to redefine a bundled place.
        let payload: [String: Any] = [
            "id": "user-evil", "title": "Sneaky", "tag": "Burgers", "authorName": "mallory", "description": "",
            "locationIDs": ["loc-redrum"],
            "places": [["id": "loc-redrum", "name": "Fake Redrum", "category": "Burgers", "address": "", "latitude": 0, "longitude": 0]],
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let data = json.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let url = try #require(URL(string: "daviscollections://collection?data=\(data)"))
        let decoded = try #require(CollectionLink.decode(url))
        #expect(decoded.places.isEmpty)

        let store = UserStore(persistence: persistence)
        AppRouter().open(url, base: base, user: store)
        #expect(store.catalog(from: base).location(id: "loc-redrum")?.name == "Redrum Burger")
    }

    // MARK: Apple Maps helpers

    @Test func categoryNamesAreReadable() {
        #expect(PlaceSearch.categoryName(.restaurant) == "Restaurant")
        #expect(PlaceSearch.categoryName(.foodMarket) == "Food Market")
        #expect(PlaceSearch.categoryName(.movieTheater) == "Movie Theater")
        #expect(PlaceSearch.categoryName(nil) == "Place")
    }

    @Test func searchResultIDsAreStable() {
        let spot = CLLocationCoordinate2D(latitude: 38.560012, longitude: -121.759988)
        let first = PlaceSearch.stableID(name: "McDonald's", coordinate: spot)
        #expect(first == PlaceSearch.stableID(name: "McDonald's", coordinate: spot))
        #expect(first == "added-mcdonalds-38.5600_-121.7600")
        #expect(first != PlaceSearch.stableID(name: "McDonald's", coordinate: .init(latitude: 38.5435, longitude: -121.7400)))
    }

    @Test func duplicatesOfBundledPlacesAreDetected() throws {
        let redrum = try #require(base.location(id: "loc-redrum"))
        let fromMaps = Location.userAdded(name: "Redrum Burger", category: "Restaurant", address: "",
                                          coordinate: .init(latitude: redrum.latitude + 0.0004, longitude: redrum.longitude))
        let farAway = Location.userAdded(name: "Redrum Burger", category: "Restaurant", address: "",
                                         coordinate: .init(latitude: redrum.latitude + 0.02, longitude: redrum.longitude))
        #expect(PlaceSearch.isSamePlace(fromMaps, as: redrum))
        #expect(!PlaceSearch.isSamePlace(farAway, as: redrum), "same name but across town is a different place")
        #expect(!PlaceSearch.isSamePlace(mcdonalds, as: redrum))
    }

    @Test func filesWithoutAddedPlacesStillLoad() throws {
        let oldFile = Data(#"{"username":"alice","users":{},"receivedCollections":[]}"#.utf8)
        #expect(try JSONDecoder().decode(SavedUserState.self, from: oldFile).addedPlaces == [])
    }
}
