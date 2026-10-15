import Foundation

/// The collection editor's state, with the rules a collection must meet.
struct CollectionDraft: Equatable {
    /// Set when editing an existing collection.
    var editingID: MapCollection.ID?
    var title = ""
    var tag = ""
    var description = ""
    var locationIDs: [Location.ID] = []
    /// Places added from Apple Maps or a dropped pin during this edit. They're
    /// kept on the device only once the collection is saved.
    var newPlaces: [Location] = []

    static let titleLength = 3...60
    static let tagLength = 2...24
    static let maxDescriptionLength = 280

    init() {}

    init(editing collection: MapCollection) {
        editingID = collection.id
        title = collection.title
        tag = collection.tag
        description = collection.description
        locationIDs = collection.locationIDs
    }

    var isEditing: Bool { editingID != nil }

    enum Problem: Equatable {
        case title, tag, description, places

        var message: String {
            switch self {
            case .title: "Give it a title of 3 to 60 characters."
            case .tag: "Add a label of 2 to 24 characters."
            case .description: "Keep the description to 280 characters."
            case .places: "Add at least one place."
            }
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTag: String { tag.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    var problems: [Problem] {
        var problems: [Problem] = []
        if !Self.titleLength.contains(trimmedTitle.count) { problems.append(.title) }
        if !Self.tagLength.contains(trimmedTag.count) { problems.append(.tag) }
        if trimmedDescription.count > Self.maxDescriptionLength { problems.append(.description) }
        if locationIDs.isEmpty { problems.append(.places) }
        return problems
    }

    var isValid: Bool { problems.isEmpty }

    /// Adds a place that isn't in the catalog yet, and selects it.
    mutating func addNewPlace(_ place: Location) {
        if !newPlaces.contains(where: { $0.id == place.id }) { newPlaces.append(place) }
        if !locationIDs.contains(place.id) { locationIDs.append(place.id) }
    }

    /// Adds the place, or removes it if it's already in the draft.
    mutating func togglePlace(_ id: Location.ID) {
        if let index = locationIDs.firstIndex(of: id) {
            locationIDs.remove(at: index)
        } else {
            locationIDs.append(id)
        }
    }

    func collection(id: MapCollection.ID, authorName: String, createdAt: Date?, likeCount: Int, dislikeCount: Int) -> MapCollection {
        MapCollection(
            id: id,
            title: trimmedTitle,
            tag: trimmedTag,
            authorName: authorName,
            description: trimmedDescription,
            coverImageURL: nil,
            locationIDs: locationIDs,
            likeCount: likeCount,
            dislikeCount: dislikeCount,
            createdAt: createdAt
        )
    }
}
