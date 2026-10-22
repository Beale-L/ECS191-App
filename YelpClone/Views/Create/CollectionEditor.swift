import MapKit
import SwiftUI

/// Creates a collection, or edits one the signed-in user made.
struct CollectionEditor: View {
    /// The merged catalog, for label suggestions and places.
    let catalog: Catalog
    var onSave: (MapCollection) -> Void = { _ in }
    var onDelete: () -> Void = {}

    @Environment(UserStore.self) private var user
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CollectionDraft
    @State private var showsProblems = false
    @State private var isConfirmingDelete = false
    @FocusState private var isEditingLabel: Bool
    private let original: CollectionDraft

    init(catalog: Catalog, draft: CollectionDraft = CollectionDraft(),
         onSave: @escaping (MapCollection) -> Void = { _ in }, onDelete: @escaping () -> Void = {}) {
        self.catalog = catalog
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: draft)
        original = draft
    }

    /// Includes places added during this edit, which aren't in the catalog until saved.
    private var places: [Location] {
        draft.locationIDs.compactMap { id in
            catalog.location(id: id) ?? draft.newPlaces.first { $0.id == id }
        }
    }

    /// Completions while typing. With the field empty, popular labels show
    /// only while it's focused, so they don't crowd a finished form.
    private var labelSuggestions: [TagSuggestion] {
        let isEmpty = draft.tag.trimmingCharacters(in: .whitespaces).isEmpty
        guard !isEmpty || isEditingLabel else { return [] }
        return catalog.tagSuggestions(for: draft.tag)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Best Tacos in Davis", text: $draft.title)
                        .accessibilityIdentifier("TitleField")
                }

                Section {
                    TextField("Tacos", text: $draft.tag)
                        .textInputAutocapitalization(.words)
                        .focused($isEditingLabel)
                        .submitLabel(.done)
                        .accessibilityIdentifier("LabelField")
                    LabelSuggestions(
                        suggestions: labelSuggestions,
                        isShowingIdeas: draft.tag.trimmingCharacters(in: .whitespaces).isEmpty
                    ) { tag in
                        draft.tag = tag
                        isEditingLabel = false
                    }
                } header: {
                    Text("Label")
                } footer: {
                    Text("Start typing to use a label other people use, or make up a new one. Labels help people find your collection in search.")
                }

                Section("Description") {
                    TextField("What ties these places together?", text: $draft.description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("DescriptionField")
                }

                placesSection

                if !places.isEmpty {
                    Section("Preview") {
                        PlacesPreviewMap(places: places, tag: draft.tag)
                            .frame(height: 180)
                            .listRowInsets(EdgeInsets())
                    }
                }

                if showsProblems && !draft.isValid {
                    Section {
                        ForEach(draft.problems, id: \.self) { problem in
                            Label(problem.message, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.red)
                        }
                    }
                }

                if draft.isEditing {
                    Section {
                        Button("Delete Collection", role: .destructive) { isConfirmingDelete = true }
                    }
                }
            }
            .navigationTitle(draft.isEditing ? "Edit Collection" : "New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.isEditing ? "Save" : "Publish", action: save)
                }
            }
            .confirmationDialog("Delete “\(draft.title)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Collection", role: .destructive, action: delete)
            } message: {
                Text("It will be removed from Explore and from everyone's favorites on this device.")
            }
        }
        .interactiveDismissDisabled(draft != original)
    }

    private var placesSection: some View {
        Section {
            ForEach(places) { place in
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                    Text(place.isUserAdded ? "\(place.category) · Added by you" : place.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { draft.locationIDs.remove(atOffsets: $0) }
            .onMove { draft.locationIDs.move(fromOffsets: $0, toOffset: $1) }

            ForEach(quickSuggestions) { place in
                QuickAddRow(place: place) {
                    withAnimation { draft.togglePlace(place.id) }
                }
            }

            NavigationLink {
                PlacePicker(catalog: catalog, draft: $draft)
            } label: {
                Label(places.isEmpty ? "Add Places" : "Add or Remove Places", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("AddPlaces")
        } header: {
            Text(places.isEmpty ? "Places" : "Places (\(places.count))")
        } footer: {
            if places.count > 1 { Text("Swipe to remove a place, or hold and drag to reorder.") }
        }
    }

    /// A few places to add with one tap, based on the label, title, and picks so far.
    private var quickSuggestions: [Location] {
        PlaceIdeas(catalog: catalog, draft: draft).quick
    }

    private func save() {
        guard draft.isValid, let saved = user.saveCollection(draft) else {
            withAnimation { showsProblems = true }
            return
        }
        dismiss()
        onSave(saved)
    }

    private func delete() {
        guard let id = draft.editingID else { return }
        user.deleteCollection(id)
        dismiss()
        onDelete()
    }
}

/// Labels other people use that complete what's typed, as rows under the field.
private struct LabelSuggestions: View {
    let suggestions: [TagSuggestion]
    /// True when nothing is typed, so these are popular labels rather than completions.
    let isShowingIdeas: Bool
    let select: (String) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            if isShowingIdeas {
                Text("Popular labels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    select(suggestion.tag)
                } label: {
                    HStack {
                        TagChip(tag: suggestion.tag)
                        Spacer()
                        Text("^[\(suggestion.count) collection](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use label \(suggestion.tag)")
            }
        }
    }
}

/// A suggested place with a one-tap Add, shown under the draft's places.
private struct QuickAddRow: View {
    let place: Location
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .foregroundStyle(.primary)
                    Text("Suggested · \(place.category)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Add \(place.name)")
        .accessibilityHint("Suggested place")
        .accessibilityIdentifier("QuickAdd")
    }
}

/// A small, non-interactive map of the draft's places.
private struct PlacesPreviewMap: View {
    let places: [Location]
    let tag: String

    var body: some View {
        let style = TagStyle(tag: tag)
        Map(position: .constant(.region(MapFraming.region(fitting: places.map(\.coordinate))))) {
            ForEach(places) { place in
                Marker(place.name, systemImage: style.symbol, coordinate: place.coordinate)
                    .tint(style.color)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    let seed = try! LocalCollectionStore().loadSeed()
    CollectionEditor(catalog: Catalog(collections: seed.collections, locations: seed.locations))
        .environment(UserStore(persistence: InMemoryUserStatePersistence(SavedUserState(username: "preview"))))
}
