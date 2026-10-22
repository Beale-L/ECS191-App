import Testing
@testable import YelpClone

@MainActor
struct SuggestionTests {
    private let catalog: Catalog

    init() async throws {
        catalog = try await LocalCollectionStore().loadCatalog()
    }

    // MARK: Labels

    @Test func completesLabelsFromTheFirstLetters() {
        let tags = catalog.tagSuggestions(for: "ba").map(\.tag)
        #expect(tags.first == "Bars")
        #expect(tags.allSatisfy { Catalog.normalized($0).hasPrefix("ba") || $0.lowercased().contains(" ba") })
    }

    @Test func matchesAWordInsideALabel() {
        #expect(catalog.tagSuggestions(for: "bik").map(\.tag) == ["Mountain Biking"])
        #expect(catalog.tagSuggestions(for: "NIGHT").map(\.tag).contains("Date Night"))
    }

    @Test func prefixMatchesComeBeforeWordMatches() {
        // "Date Night" starts with "d"; "Day Trips" and "Dessert" do too, and
        // none of them should be pushed below a label that only contains a "d".
        let tags = catalog.tagSuggestions(for: "d", limit: 10).map(\.tag)
        let firstNonPrefix = tags.firstIndex { !$0.lowercased().hasPrefix("d") } ?? tags.endIndex
        #expect(tags[..<firstNonPrefix].count >= 3)
        #expect(tags[firstNonPrefix...].allSatisfy { !$0.lowercased().hasPrefix("d") })
    }

    @Test func emptyTextSuggestsTheMostUsedLabels() {
        let suggestions = catalog.tagSuggestions(for: "  ")
        #expect(suggestions.count == 5)
        #expect(suggestions.first?.tag == "Bars")
        #expect(suggestions.map(\.count) == suggestions.map(\.count).sorted(by: >))
    }

    @Test func anExactLabelNeedsNoCompletion() {
        #expect(catalog.tagSuggestions(for: "coffee").isEmpty)
        #expect(catalog.tagSuggestions(for: "zzz").isEmpty)
    }

    // MARK: Places

    @Test func suggestsPlacesThatFitTheLabel() {
        let names = catalog.suggestedPlaces(tag: "Bars", title: "").map(\.category)
        #expect(names.count == 8)
        let barCategories: Set = ["Pub", "Brewery", "Beer Bar", "Sports Bar", "Cocktail Bar", "Bar", "Wine Bar"]
        #expect(names.filter { barCategories.contains($0) }.count >= 6, "got \(names)")
    }

    @Test func titleWordsFindPlacesWithoutALabel() {
        let names = catalog.suggestedPlaces(tag: "", title: "Bats and owls").map(\.name)
        #expect(names.contains("Yolo Causeway Bat Colony"))
    }

    @Test func titleWordsMatchOtherCollectionsLabels() {
        // "Late Night" is a label, so its places beat bars whose titles only say "night".
        let late = Set(catalog.collections.filter { $0.tag == "Late Night" }.flatMap(\.locationIDs))
        let top = catalog.suggestedPlaces(tag: "Fast Food", title: "Late Night Eats", limit: 3)
        #expect(top.allSatisfy { late.contains($0.id) }, "got \(top.map(\.name))")
    }

    @Test func aCategoryMatchCountsEvenIfNobodyCollectedIt() {
        let names = catalog.suggestedPlaces(tag: "Bike Shop", title: "").map(\.name)
        #expect(names.contains("Davis Wheelworks"))
    }

    @Test func pickedPlacesAreNotSuggestedAgain() {
        let first = catalog.suggestedPlaces(tag: "Bars", title: "", limit: 3)
        let again = catalog.suggestedPlaces(tag: "Bars", title: "", excluding: Set(first.map(\.id)))
        #expect(Set(again.map(\.id)).isDisjoint(with: first.map(\.id)))
    }

    @Test func suggestsPlacesPairedWithPicks() {
        let paired = catalog.placesOftenPaired(with: ["loc-stebbins"]).map(\.id)
        #expect(!paired.isEmpty)
        #expect(!paired.contains("loc-stebbins"))
        #expect(paired.contains("loc-blue-ridge") || paired.contains("loc-lake-solano") || paired.contains("loc-monticello-dam"))
    }

    @Test func blankDraftFallsBackToPopularPlaces() {
        let ideas = PlaceIdeas(catalog: catalog, draft: CollectionDraft())
        #expect(ideas.forLabel.isEmpty && ideas.pairedWithPicks.isEmpty)
        #expect(ideas.popular.count == 8)
        #expect(ideas.quick.isEmpty, "no one-tap adds until there's something to base them on")
    }

    @Test func quickAddsComeFromTheDraft() {
        var draft = CollectionDraft()
        draft.tag = "Animal Watching"
        let ideas = PlaceIdeas(catalog: catalog, draft: draft)
        #expect(ideas.quick.count == 3)
        #expect(ideas.popular.isEmpty)
    }

    @Test func keywordsDropFillerAndPlurals() {
        #expect(Catalog.keywords(in: "The Best Bars in Davis") == ["bar"])
        #expect(Catalog.keywords(in: "Ponds & Owls!") == ["pond", "owl"])
    }
}
