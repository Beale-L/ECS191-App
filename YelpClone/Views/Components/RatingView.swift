import SwiftUI

struct RatingView: View {
    let rating: Double
    let reviewCount: Int

    var body: some View {
        if reviewCount == 0 {
            // Places people add from Apple Maps or a pin don't have reviews yet.
            Label("Not yet rated", systemImage: "star")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            stars
        }
    }

    private var stars: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: symbol(forStar: index))
                }
            }
            .foregroundStyle(.orange)

            Text(rating, format: .number.precision(.fractionLength(1)))
                .fontWeight(.semibold)
            Text("(^[\(reviewCount) review](inflect: true))")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating, format: .number.precision(.fractionLength(1))) out of 5, \(reviewCount) reviews")
    }

    private func symbol(forStar index: Int) -> String {
        let remainder = rating - Double(index)
        if remainder >= 0.75 { return "star.fill" }
        if remainder >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}
