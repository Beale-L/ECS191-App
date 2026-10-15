import SwiftUI

struct LocationSheet: View {
    let location: Location

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let photoURL = location.photoURL {
                    AsyncImage(url: photoURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(location.name)
                        .font(.title2.bold())
                    HStack(spacing: 6) {
                        Text(location.category)
                        if let priceLevel = location.priceLevel {
                            Text("·")
                            Text(String(repeating: "$", count: priceLevel))
                                .accessibilityLabel("Price level \(priceLevel) of 4")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                RatingView(rating: location.rating, reviewCount: location.reviewCount)

                Label(location.address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)

                Button {
                    openURL(location.appleMapsURL)
                } label: {
                    Label("Open in Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(20)
            .padding(.top, 8)
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        LocationSheet(location: Location(
            id: "preview", name: "Central Park", category: "Park", address: "401 C St, Davis, CA 95616",
            latitude: 38.5459, longitude: -121.7446, rating: 4.6, reviewCount: 412, priceLevel: nil, photoURL: nil
        ))
        .presentationDetents([.medium])
    }
}
