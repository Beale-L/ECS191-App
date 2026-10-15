import MapKit
import SwiftUI

/// A collection's locations on a map. Tapping a pin opens its details in a
/// sheet; the map stays interactive behind it so other pins can be tapped.
struct CollectionMapView: View {
    let collection: MapCollection
    let locations: [Location]
    let seededComments: [Comment]

    @Environment(UserStore.self) private var user
    @Environment(ExploreModel.self) private var model
    @State private var position: MapCameraPosition
    @State private var selectedID: Location.ID?
    @State private var isShowingComments = false
    @State private var isEditing = false

    init(collection: MapCollection, locations: [Location], seededComments: [Comment] = []) {
        self.collection = collection
        self.locations = locations
        self.seededComments = seededComments
        _position = State(initialValue: .region(MapFraming.region(fitting: locations.map(\.coordinate))))
    }

    var body: some View {
        let style = TagStyle(tag: collection.tag)
        VStack(spacing: 0) {
            CollectionHeader(collection: collection, placeCount: locations.count)
            ActionBar(collection: collection, commentCount: comments.count) {
                selectedID = nil
                isShowingComments = true
            }

            Map(position: $position, selection: $selectedID) {
                ForEach(locations) { location in
                    Marker(location.name, systemImage: style.symbol, coordinate: location.coordinate)
                        .tint(style.color)
                        .tag(location.id)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Show All", systemImage: "arrow.up.left.and.arrow.down.right") {
                    withAnimation { position = .region(MapFraming.region(fitting: locations.map(\.coordinate))) }
                }
                ShareLink(
                    item: CollectionLink.url(for: collection, places: locations),
                    subject: Text(collection.title),
                    message: Text(CollectionLink.message(for: collection, placeCount: locations.count)),
                    preview: CollectionLink.preview(for: collection)
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                if user.isAuthor(of: collection.id) {
                    Button("Edit", systemImage: "pencil") {
                        selectedID = nil
                        isShowingComments = false
                        isEditing = true
                    }
                }
            }
        }
        // One sheet for both, so switching from a location to comments is a
        // clean swap rather than two sheets racing.
        .sheet(item: presentedSheet) { sheet in
            switch sheet {
            case .location:
                if let selectedLocation {
                    LocationSheet(location: selectedLocation)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
            case .comments:
                CommentsSheet(collectionID: collection.id, comments: comments)
            case .edit:
                if let base = model.catalog {
                    CollectionEditor(catalog: user.catalog(from: base), draft: CollectionDraft(editing: collection))
                }
            }
        }
    }

    private var selectedLocation: Location? {
        locations.first { $0.id == selectedID }
    }

    private var comments: [Comment] {
        user.allComments(for: collection.id, seeded: seededComments)
    }

    /// Every location shares one identity, so tapping another pin swaps the
    /// content without closing the sheet.
    private enum MapSheet: Identifiable {
        case location
        case comments
        case edit
        var id: Self { self }
    }

    private var presentedSheet: Binding<MapSheet?> {
        Binding(
            get: {
                if isEditing { return .edit }
                if isShowingComments { return .comments }
                return selectedLocation == nil ? nil : .location
            },
            set: { newValue in
                if newValue == nil {
                    selectedID = nil
                    isShowingComments = false
                    isEditing = false
                }
            }
        )
    }
}

/// Like, Dislike, Favorite, and Comments. Guests are asked to sign in first.
private struct ActionBar: View {
    let collection: MapCollection
    let commentCount: Int
    let showComments: () -> Void

    @Environment(UserStore.self) private var user

    var body: some View {
        let reaction = user.reaction(to: collection.id)
        let isFavorite = user.isFavorite(collection.id)
        HStack(spacing: 8) {
            ActionButton(
                title: "Like",
                count: user.likeCount(for: collection),
                systemImage: reaction == .like ? "hand.thumbsup.fill" : "hand.thumbsup",
                isActive: reaction == .like
            ) {
                user.perform(.react(collection.id, .like))
            }
            ActionButton(
                title: "Dislike",
                count: user.dislikeCount(for: collection),
                systemImage: reaction == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                isActive: reaction == .dislike
            ) {
                user.perform(.react(collection.id, .dislike))
            }
            ActionButton(
                title: "Favorite",
                count: nil,
                systemImage: isFavorite ? "heart.fill" : "heart",
                isActive: isFavorite
            ) {
                user.perform(.favorite(collection.id))
            }
            ActionButton(
                title: "Comments",
                count: commentCount,
                systemImage: "bubble.left",
                isActive: false,
                action: showComments
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .sensoryFeedback(.selection, trigger: reaction)
        .sensoryFeedback(.selection, trigger: isFavorite)
    }
}

private struct ActionButton: View {
    let title: String
    let count: Int?
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                if let count {
                    Text(count, format: .number)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))
                }
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .accentColor : .secondary)
        .animation(.snappy, value: count)
        .accessibilityLabel(title)
        .accessibilityValue(count.map { "\($0)" } ?? "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct CollectionHeader: View {
    let collection: MapCollection
    let placeCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TagChip(tag: collection.tag)
                Text("by \(collection.authorName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !collection.description.isEmpty {
                Text(collection.description)
                    .font(.subheadline)
                    .lineLimit(3)
            }
            Label("^[\(placeCount) place](inflect: true)", systemImage: "mappin")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

#Preview {
    let seed = try! LocalCollectionStore().loadSeed()
    let catalog = Catalog(collections: seed.collections, locations: seed.locations, comments: seed.comments)
    let collection = catalog.collections[0]
    NavigationStack {
        CollectionMapView(
            collection: collection,
            locations: catalog.locations(in: collection),
            seededComments: catalog.comments(for: collection.id)
        )
    }
    .environment(UserStore(persistence: InMemoryUserStatePersistence()))
    .environment(ExploreModel(store: LocalCollectionStore()))
    .signInGate()
}
