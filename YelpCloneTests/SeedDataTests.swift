import MapKit
import Testing
@testable import YelpClone

@MainActor
struct SeedDataTests {
    private let seed: SeedFile
    private let catalog: Catalog

    init() async throws {
        let store = LocalCollectionStore()
        seed = try store.loadSeed()
        catalog = try await store.loadCatalog()
    }

    @Test func seedMeetsStage1Minimums() {
        #expect(seed.collections.count >= 6)
        #expect(Set(seed.collections.map(\.tag)).count >= 4)
    }

    @Test func seedHasActivityCollections() {
        #expect(seed.collections.count >= 300)
        let tags = Set(seed.collections.map(\.tag))
        for tag in ["Mountain Biking", "Date Night", "Bars", "Animal Watching"] {
            #expect(tags.contains(tag), "no \(tag) collections")
        }
        #expect(Set(seed.collections.map { $0.title.lowercased() }).count == seed.collections.count, "duplicate titles")
    }

    @Test func idsAreUnique() {
        #expect(Set(seed.collections.map(\.id)).count == seed.collections.count)
        #expect(Set(seed.locations.map(\.id)).count == seed.locations.count)
    }

    @Test func everyLocationIDResolves() {
        for collection in seed.collections {
            for id in collection.locationIDs {
                #expect(catalog.location(id: id) != nil, "\(collection.id) references missing location \(id)")
            }
        }
    }

    @Test func everyLocationBelongsToACollection() {
        let referenced = Set(seed.collections.flatMap(\.locationIDs))
        for location in seed.locations {
            #expect(referenced.contains(location.id), "\(location.id) is not in any collection")
        }
    }

    @Test func locationValuesAreInRange() {
        for location in seed.locations {
            #expect((0...5).contains(location.rating), "\(location.id) rating")
            #expect(location.reviewCount >= 0, "\(location.id) reviewCount")
            if let priceLevel = location.priceLevel {
                #expect((1...4).contains(priceLevel), "\(location.id) priceLevel")
            }
            // Catches swapped or mistyped coordinates: everything is within a
            // day trip of Davis, from Lake Berryessa to Sacramento.
            #expect((38.40...38.80).contains(location.latitude), "\(location.id) latitude")
            #expect((-122.30 ... -121.45).contains(location.longitude), "\(location.id) longitude")
        }
    }

    @Test func everyCommentBelongsToACollection() {
        let ids = Set(seed.collections.map(\.id))
        for comment in seed.comments {
            #expect(ids.contains(comment.collectionID), "\(comment.id) references missing collection \(comment.collectionID)")
        }
        #expect(Set(seed.comments.map(\.id)).count == seed.comments.count)
    }

    @Test func seedIncludesACollectionWithNoComments() {
        #expect(seed.collections.contains { catalog.comments(for: $0.id).isEmpty })
    }

    @Test func seedIncludesMapFramingEdgeCases() {
        let sizes = seed.collections.map(\.locationIDs.count)
        #expect(sizes.contains(1), "need a single-location collection")
        #expect(sizes.contains { $0 >= 15 }, "need a 15+ location collection")
    }
}

struct MapFramingTests {
    @Test func regionContainsEveryCoordinate() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 38.5328, longitude: -121.7932),
            CLLocationCoordinate2D(latitude: 38.5780, longitude: -121.7075),
            CLLocationCoordinate2D(latitude: 38.5459, longitude: -121.7446),
        ]
        let region = MapFraming.region(fitting: coordinates)
        for coordinate in coordinates {
            #expect(abs(coordinate.latitude - region.center.latitude) <= region.span.latitudeDelta / 2)
            #expect(abs(coordinate.longitude - region.center.longitude) <= region.span.longitudeDelta / 2)
        }
    }

    @Test func singleCoordinateGetsMinimumSpan() {
        let point = CLLocationCoordinate2D(latitude: 38.5412, longitude: -121.7335)
        let region = MapFraming.region(fitting: [point], minimumSpan: 0.008)
        #expect(region.center.latitude == point.latitude)
        #expect(region.span.latitudeDelta == 0.008)
        #expect(region.span.longitudeDelta == 0.008)
    }

    @Test func emptyFallsBackToDavis() {
        let region = MapFraming.region(fitting: [])
        #expect(region.center.latitude == MapFraming.davis.center.latitude)
    }
}
