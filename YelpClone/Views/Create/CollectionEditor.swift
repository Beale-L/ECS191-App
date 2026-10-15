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
                        .accessibilityIdentifier("LabelField")
                    LabelSuggestions(tags: catalog.tags, selection: $draft.tag)
                } header: {
                    Text("Label")
                } footer: {
                    Text("Pick a label or type a new one. Labels help people find your collection in search.")
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

/// Existing labels as tappable chips, filtered by what's typed.
private struct LabelSuggestions: View {
    let tags: [String]
    @Binding var selection: String

    private var suggestions: [String] {
        let typed = Catalog.normalized(selection.trimmingCharacters(in: .whitespaces))
        return tags.filter { typed.isEmpty || Catalog.normalized($0).hasPrefix(typed) }
    }

    var body: some View {
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button {
                            selection = tag
                        } label: {
                            TagChip(tag: tag)
                                .overlay {
                                    if tag == selection {
                                        Capsule().strokeBorder(TagStyle(tag: tag).color, lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use label \(tag)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
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
