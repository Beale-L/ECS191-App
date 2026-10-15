import SwiftUI

/// Picks places for a collection: places already in the app, results from
/// Apple Maps, or a dropped pin for somewhere Apple Maps doesn't list yet.
struct PlacePicker: View {
    let catalog: Catalog
    @Binding var draft: CollectionDraft

    @State private var query = ""
    @State private var mapResults: [Location] = []
    @State private var searchState = SearchState.idle

    private enum SearchState: Equatable {
        case idle, searching, done, failed
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// Bundled places, places added before, and ones added during this edit.
    private var appPlaces: [Location] {
        let fresh = draft.newPlaces.filter { catalog.location(id: $0.id) == nil }
        let all = catalog.allLocations + fresh
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
            // Before searching, put the ways to add a new place up top, where
            // they're easy to find above the long list.
            if trimmedQuery.isEmpty {
                Section {
                    dropPinLink
                } footer: {
                    Text("Can't find a place? Search above to look it up on Apple Maps, or drop a pin for somewhere new.")
                }
            }

            Section {
                ForEach(appPlaces) { place in
                    PlaceRow(place: place, isSelected: draft.locationIDs.contains(place.id)) {
                        draft.togglePlace(place.id)
                    }
                }
            } header: {
                Text(trimmedQuery.isEmpty ? "Places in the App" : "In the App")
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
    }
}
