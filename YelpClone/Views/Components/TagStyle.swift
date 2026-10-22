import SwiftUI

/// Color and SF Symbol for a collection tag, used for chips, pins, and covers.
struct TagStyle {
    let color: Color
    let symbol: String

    init(tag: String) {
        switch tag.lowercased() {
        case "parks": (color, symbol) = (.green, "leaf.fill")
        case "study spots": (color, symbol) = (.brown, "cup.and.saucer.fill")
        case "pizza": (color, symbol) = (.orange, "fork.knife")
        case "burgers": (color, symbol) = (.red, "takeoutbag.and.cup.and.straw.fill")
        case "sightseeing": (color, symbol) = (.blue, "binoculars.fill")
        case "date night": (color, symbol) = (.pink, "wineglass.fill")
        case "brunch": (color, symbol) = (.indigo, "frying.pan.fill")
        case "cheap eats": (color, symbol) = (.mint, "dollarsign.circle.fill")
        case "coffee": (color, symbol) = (.teal, "mug.fill")
        case "mountain biking": (color, symbol) = (.orange, "bicycle")
        case "bars": (color, symbol) = (.yellow, "wineglass")
        case "animal watching": (color, symbol) = (.green, "pawprint.fill")
        case "hiking": (color, symbol) = (.brown, "figure.hiking")
        case "live music": (color, symbol) = (.purple, "music.note")
        case "day trips": (color, symbol) = (.blue, "car.fill")
        case "late night": (color, symbol) = (.indigo, "moon.stars.fill")
        case "sunset spots": (color, symbol) = (.orange, "sun.horizon.fill")
        case "family fun": (color, symbol) = (.cyan, "figure.2.and.child.holdinghands")
        case "farm visits": (color, symbol) = (.green, "carrot.fill")
        case "art": (color, symbol) = (.pink, "paintpalette.fill")
        case "dessert": (color, symbol) = (.pink, "birthday.cake.fill")
        case "rainy day": (color, symbol) = (.gray, "cloud.rain.fill")
        default: (color, symbol) = (.purple, "mappin")
        }
    }
}

struct TagChip: View {
    let tag: String

    var body: some View {
        let style = TagStyle(tag: tag)
        Label(tag, systemImage: style.symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(style.color)
            .background(style.color.opacity(0.15), in: Capsule())
    }
}
