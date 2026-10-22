import SwiftUI

/// Picks places for a collection. Before searching it suggests places that
/// fit the draft; searching covers places in the app and Apple Maps, and a
/// dropped pin covers somewhere Apple Maps doesn't list yet.
struct PlacePicker: View {
    let catalog: Catalog
    @Binding var draft: CollectionDraft

    /// Taken when the picker appears, so a suggestion stays put (with a
    /// checkmark) when tapped instead of jumping to Your Picks.
    @State private var ideas: PlaceIdeas?
    @State private var query = ""
    @State private var mapResults: [Location] = []
    @State private var searchState = SearchState.idle

    private enum SearchState: Equatable {
        case idle, searching, done, failed
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// Bundled places, places added before, and ones added during this edit.
    private var allPlaces: [Location] {
        catalog.allLocations + draft.newPlaces.filter { catalog.location(id: $0.id) == nil }
    }

    private var appPlaces: [Location] {
        let all = allPlaces
        let words = Catalog.normalized(trimmedQuery).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return all }
        return all.filter { place in
            let text = Catalog.normalized("\(place.name) \(place.category) \(place.address)")
            return words.allSatisfy { text.contains($0) }
        }
    }

    /// Apple Maps results that aren't already listed under places in the app.
    private var newMapResults: [Location] {
        let inApp = catalog.allLocations + draft.newPlaces
        return mapResults.filter { result in
            !inApp.contains { $0.id == result.id || PlaceSearch.isSamePlace(result, as: $0) }
        }
    }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                suggestions
            } else {
                Section {
                    if appPlaces.isEmpty {
                        Text("No places in the app match.").foregroundStyle(.secondary)
                    }
                    ForEach(appPlaces) { place in
                        row(place)
                    }
                } header: {
                    Text("In the App")
                }
            }

            if !trimmedQuery.isEmpty {
                Section {
                    switch searchState {
                    case .searching where newMapResults.isEmpty:
                        HStack {
                            ProgressView()
                            Text("Searching Apple Maps…").foregroundStyle(.secondary)
                        }
                    case .failed:
                        Label("Couldn't reach Apple Maps. Check your connection, or drop a pin instead.", systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.secondary)
                    case .done where newMapResults.isEmpty:
                        Text("No other matches on Apple Maps.").foregroundStyle(.secondary)
                    default:
                        ForEach(newMapResults) { place in
                            PlaceRow(place: place, isSelected: draft.locationIDs.contains(place.id)) {
                                if draft.locationIDs.contains(place.id) {
                                    draft.togglePlace(place.id)
                                } else {
                                    draft.addNewPlace(place)
                                }
                            }
                        }
                    }
                } header: {
                    Label("Apple Maps", systemImage: "map")
                }
            }

            if !trimmedQuery.isEmpty {
                Section {
                    dropPinLink
                } footer: {
                    Text("For somewhere that isn't listed yet, like a restaurant that just opened.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search places or Apple Maps")
        .task(id: trimmedQuery) { await searchAppleMaps(for: trimmedQuery) }
        .onAppear { ideas = PlaceIdeas(catalog: catalog, draft: draft) }
        .navigationTitle("Add Places")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .status) {
                Text("^[\(draft.locationIDs.count) place](inflect: true) selected")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What to show before searching: the draft's picks, then ideas, then
    /// ways to find anything else.
    @ViewBuilder
    private var suggestions: some View {
        let ideas = ideas ?? PlaceIdeas(catalog: catalog, draft: draft)
        let shown = Set((ideas.forLabel + ideas.pairedWithPicks + ideas.popular).map(\.id))
        let picks = draft.locationIDs.filter { !shown.contains($0) }.compactMap { id in allPlaces.first { $0.id == id } }

        if !picks.isEmpty {
            Section("Your Picks") {
                ForEach(picks) { row($0) }
            }
        }
        if !ideas.forLabel.isEmpty {
            Section {
                ForEach(ideas.forLabel) { row($0) }
            } header: {
                Text(suggestionHeader)
            } footer: {
                Text("Based on collections with the same label or similar titles.")
            }
        }
        if !ideas.pairedWithPicks.isEmpty {
            Section {
                ForEach(ideas.pairedWithPicks) { row($0) }
            } header: {
                Text("Often Paired With Your Picks")
            }
        }
        if !ideas.popular.isEmpty {
            Section {
                ForEach(ideas.popular) { row($0) }
            } header: {
                Text("Popular Places")
            } footer: {
                Text("Add a label or title to get suggestions that fit your collection.")
            }
        }
        Section {
            NavigationLink {
                AllPlacesList(places: allPlaces, draft: $draft)
            } label: {
                LabeledContent {
                    Text(allPlaces.count, format: .number)
                } label: {
                    Label("Browse All Places", systemImage: "list.bullet")
                }
            }
            .accessibilityIdentifier("BrowseAllPlaces")
            dropPinLink
        } footer: {
            Text("Can't find a place? Search above to look it up on Apple Maps, or drop a pin for somewhere new.")
        }
    }

    private var suggestionHeader: String {
        let tag = draft.tag.trimmingCharacters(in: .whitespaces)
        return tag.isEmpty ? "Suggested for Your Title" : "Suggested for \u{201C}\(tag)\u{201D}"
    }

    private func row(_ place: Location) -> some View {
        PlaceRow(place: place, isSelected: draft.locationIDs.contains(place.id)) {
            draft.togglePlace(place.id)
        }
    }

    private var dropPinLink: some View {
        NavigationLink {
            DropPinView(suggestedName: trimmedQuery, draft: $draft)
        } label: {
            Label("Drop a Pin", systemImage: "mappin.and.ellipse")
        }
        .accessibilityIdentifier("DropPin")
    }

    /// Waits for typing to pause, then searches. A new query cancels the old one.
    private func searchAppleMaps(for text: String) async {
        guard !text.isEmpty else {
            mapResults = []
            searchState = .idle
            return
        }
        searchState = .searching
        do {
            try await Task.sleep(for: .milliseconds(400))
            let results = try await PlaceSearch.search(text)
            mapResults = results
            searchState = .done
        } catch is CancellationError {
            // A newer query took over.
        } catch {
            mapResults = []
            searchState = .failed
        }
    }
}

/// Every place in the app, grouped by type, with its own filter.
private struct AllPlacesList: View {
    let places: [Location]
    @Binding var draft: CollectionDraft
    @State private var filter = ""

    private var groups: [(category: String, places: [Location])] {
        let words = Catalog.normalized(filter.trimmingCharacters(in: .whitespaces)).split(whereSeparator: \.isWhitespace)
        let matching = places.filter { place in
            let text = Catalog.normalized("\(place.name) \(place.category) \(place.address)")
            return words.allSatisfy { text.contains($0) }
        }
        return Dictionary(grouping: matching, by: \.category)
            .map { (category: $0.key, places: $0.value) }
            .sorted { $0.category.localizedStandardCompare($1.category) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.category) { group in
                Section(group.category) {
                    ForEach(group.places) { place in
                        PlaceRow(place: place, isSelected: draft.locationIDs.contains(place.id)) {
                            draft.togglePlace(place.id)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $filter, prompt: "Filter places")
        .overlay {
            if groups.isEmpty { ContentUnavailableView.search(text: filter) }
        }
        .navigationTitle("All Places")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlaceRow: View {
    let place: Location
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .foregroundStyle(.primary)
                    Text(place.address.isEmpty ? place.category : "\(place.category) · \(place.address)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("PlaceRow")
    }
}
