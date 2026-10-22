import Foundation

/// A label people already use, and how many collections use it.
struct TagSuggestion: Hashable {
    let tag: String
    let count: Int
}

/// Suggestions for the collection editor, drawn from what other people made.
extension Catalog {
    /// Labels matching what's typed, most used first. Labels that start with
    /// the text (or have a word that does) come before ones that only contain
    /// it. An exact match is left out, since there's nothing left to complete.
    /// With nothing typed, returns the most used labels as ideas.
    func tagSuggestions(for typed: String, limit: Int = 5) -> [TagSuggestion] {
        let text = Self.normalized(typed.trimmingCharacters(in: .whitespaces))
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for collection in collections {
            let key = Self.normalized(collection.tag)
            counts[key, default: 0] += 1
            if display[key] == nil { display[key] = collection.tag }
        }
        guard counts[text] == nil else { return [] }

        func rank(_ key: String) -> Int? {
            if text.isEmpty || key.hasPrefix(text) { return 0 }
            if key.split(separator: " ").contains(where: { $0.hasPrefix(text) }) { return 1 }
            if key.contains(text) { return 2 }
            return nil
        }
        return counts.keys
            .compactMap { key in rank(key).map { (key, $0) } }
            .sorted { ($0.1, -counts[$0.0]!, $0.0) < ($1.1, -counts[$1.0]!, $1.0) }
            .prefix(limit)
            .map { TagSuggestion(tag: display[$0.0]!, count: counts[$0.0]!) }
    }

    /// Places that fit a new collection's label and title, best first.
    ///
    /// A place scores for every collection it's in that shares the label, and
    /// for each title word shared with that collection's label, title, or description.
    /// A category that matches the label counts too, so "Coffee" finds cafés
    /// nobody has collected yet. Ties go to the more reviewed place.
    func suggestedPlaces(tag: String, title: String, excluding: Set<Location.ID> = [], limit: Int = 8) -> [Location] {
        let tagKey = Self.normalized(tag.trimmingCharacters(in: .whitespaces))
        let titleWords = Self.keywords(in: title)
        guard !tagKey.isEmpty || !titleWords.isEmpty else { return [] }

        var scores: [Location.ID: Int] = [:]
        for collection in collections {
            var weight = Self.normalized(collection.tag) == tagKey ? 3 : 0
            let text = Self.keywords(in: "\(collection.tag) \(collection.title) \(collection.description)")
            weight += titleWords.intersection(text).count
            guard weight > 0 else { continue }
            for id in collection.locationIDs { scores[id, default: 0] += weight }
        }
        if !tagKey.isEmpty {
            let tagWords = Self.keywords(in: tag)
            for place in allLocations {
                let category = Self.normalized(place.category)
                if category == tagKey || !tagWords.isDisjoint(with: Self.keywords(in: place.category)) {
                    scores[place.id, default: 0] += 4
                }
            }
        }
        return top(scores, excluding: excluding, limit: limit)
    }

    /// Places that often appear in the same collections as the selected ones.
    func placesOftenPaired(with selected: [Location.ID], excluding: Set<Location.ID> = [], limit: Int = 6) -> [Location] {
        let picked = Set(selected)
        guard !picked.isEmpty else { return [] }
        var scores: [Location.ID: Int] = [:]
        for collection in collections {
            let shared = picked.intersection(collection.locationIDs).count
            guard shared > 0 else { continue }
            for id in collection.locationIDs { scores[id, default: 0] += shared }
        }
        return top(scores, excluding: excluding.union(picked), limit: limit)
    }

    /// Places in the most collections, for when there's nothing to go on yet.
    func popularPlaces(excluding: Set<Location.ID> = [], limit: Int = 8) -> [Location] {
        var scores: [Location.ID: Int] = [:]
        for collection in collections {
            for id in collection.locationIDs { scores[id, default: 0] += 1 }
        }
        return top(scores, excluding: excluding, limit: limit)
    }

    private func top(_ scores: [Location.ID: Int], excluding: Set<Location.ID>, limit: Int) -> [Location] {
        scores
            .filter { $0.value > 0 && !excluding.contains($0.key) }
            .compactMap { id, score in location(id: id).map { ($0, score) } }
            .sorted { ($0.1, $0.0.reviewCount) > ($1.1, $1.0.reviewCount) }
            .prefix(limit)
            .map(\.0)
    }

    /// Words worth matching on: lowercased, 3+ letters, minus filler words.
    /// A trailing "s" is dropped, so "Bars" matches "Bar".
    static func keywords(in text: String) -> Set<String> {
        let words = normalized(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : String($0) }
        return Set(words.filter { $0.count >= 3 && !stopWords.contains($0) })
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "you", "your", "that", "this", "are", "but", "not", "all", "our",
        "best", "davi", "davis", "place", "spot", "where", "what", "into", "from", "out", "near", "worth",
        "get", "one", "two", "too", "who", "can", "how", "just", "most", "more", "only", "each", "here",
    ]
}

/// Place suggestions for a draft, grouped the way the editor shows them.
struct PlaceIdeas {
    /// Places that fit the label and title.
    let forLabel: [Location]
    /// Places that show up alongside the ones already picked.
    let pairedWithPicks: [Location]
    /// Popular places, only when there's nothing else to go on.
    let popular: [Location]

    init(catalog: Catalog, draft: CollectionDraft) {
        let picked = Set(draft.locationIDs)
        forLabel = catalog.suggestedPlaces(tag: draft.tag, title: draft.title, excluding: picked)
        pairedWithPicks = catalog.placesOftenPaired(with: draft.locationIDs, excluding: picked.union(forLabel.map(\.id)))
        popular = forLabel.isEmpty && pairedWithPicks.isEmpty ? catalog.popularPlaces(excluding: picked) : []
    }

    /// The top few, for one-tap adds in the editor. Empty until the draft has
    /// a label, title, or place to base them on.
    var quick: [Location] {
        Array((forLabel + pairedWithPicks).prefix(3))
    }

    var isEmpty: Bool { forLabel.isEmpty && pairedWithPicks.isEmpty && popular.isEmpty }
}
