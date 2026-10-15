import SwiftUI

struct CollectionCard: View {
    let collection: MapCollection
    let locations: [Location]
    let likeCount: Int
    /// Extra context, such as which places matched a search.
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CollectionCover(collection: collection, locations: locations)
                .padding(.bottom, 2)

            TagChip(tag: collection.tag)

            Text(collection.title)
                .font(.headline)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)

            Text("by \(collection.authorName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let note {
                Label(note, systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .lineLimit(2)
            }

            HStack {
                Label("^[\(locations.count) place](inflect: true)", systemImage: "mappin")
                Spacer(minLength: 4)
                Label("\(likeCount)", systemImage: "hand.thumbsup")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(CompactLabelStyle())
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The card's image: the uploaded cover if there is one, otherwise a map
/// snapshot with a dot per location.
struct CollectionCover: View {
    let collection: MapCollection
    let locations: [Location]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var snapshot: UIImage?

    var body: some View {
        let style = TagStyle(tag: collection.tag)
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    ZStack {
                        LinearGradient(
                            colors: [style.color.opacity(0.35), style.color.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: style.symbol)
                            .font(.largeTitle)
                            .foregroundStyle(style.color.opacity(0.6))

                        if let url = collection.coverImageURL {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.clear
                            }
                        } else if let snapshot {
                            Image(uiImage: snapshot)
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .task(id: SnapshotRequest(size: proxy.size, colorScheme: colorScheme, locationIDs: collection.locationIDs)) {
                        guard collection.coverImageURL == nil else { return }
                        let image = await MapSnapshotCache.shared.image(
                            for: locations,
                            // Include the places, so editing a collection redraws its cover.
                            cacheKey: "\(collection.id)-\(collection.locationIDs.joined(separator: ","))",
                            size: proxy.size,
                            scale: displayScale,
                            colorScheme: colorScheme,
                            pinColor: UIColor(style.color)
                        )
                        withAnimation(.easeOut(duration: 0.2)) { snapshot = image }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }

    private struct SnapshotRequest: Equatable {
        let size: CGSize
        let colorScheme: ColorScheme
        let locationIDs: [Location.ID]
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
