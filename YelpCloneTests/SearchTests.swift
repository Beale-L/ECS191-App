import Testing
@testable import YelpClone

@MainActor
struct SearchTests {
    private let catalog: Catalog

    init() async throws {
        catalog = try await LocalCollectionStore().loadCatalog()
    }

    private func titles(_ query: String) -> [String] {
        catalog.search(query).map(\.collection.title)
    }

    @Test(arguments: ["", "   "])
    func emptyQueryMatchesEverything(query: String) {
        #expect(titles(query) == catalog.collections.map(\.title))
    }

    @Test func matchesTitleTagAndAuthor() {
        #expect(titles("pizza night") == ["Pizza Night"])
        #expect(titles("Cheap Eats") == ["Cheap Eats Near Campus"])
        #expect(titles("brokeaggie") == ["Cheap Eats Near Campus"])
    }

    @Test func matchesPlacesAndSaysWhich() {
        let results = catalog.search("temple")
        #expect(results.map(\.collection.title) == ["Study Spots That Won't Kick You Out", "Downtown Coffee Crawl"])
        #expect(results.allSatisfy { $0.matchingPlaces == ["Temple Coffee Roasters"] })
    }

    @Test func doesNotListPlacesWhenTheCollectionItselfMatched() {
        let coffeeCrawl = catalog.search("coffee").first { $0.collection.tag == "Coffee" }
        #expect(coffeeCrawl?.matchingPlaces == [])
    }

    @Test func ignoresCaseAccentsAndApostrophes() {
        #expect(titles("CRÊPEVILLE") == ["Brunch Worth the Wait"])
        #expect(titles("steves") == ["Pizza Night"])
        #expect(titles("Steve’s") == ["Pizza Night"])
    }

    @Test func everyWordMustMatch() {
        #expect(Set(titles("venus")) == ["Date Night Downtown", "Brunch Worth the Wait"])
        #expect(titles("date venus") == ["Date Night Downtown"])
    }

    @Test func noMatches() {
        #expect(titles("sushi").isEmpty)
    }
}
