import MapKit
import SwiftUI
import UIKit

/// Renders small static map images with a dot per location for collection
/// cards. A live `Map` per grid cell would be far heavier than an image.
final class MapSnapshotCache {
    static let shared = MapSnapshotCache()

    private let cache = NSCache<NSString, UIImage>()

    func image(
        for locations: [Location],
        cacheKey: String,
        size: CGSize,
        scale: CGFloat,
        colorScheme: ColorScheme,
        pinColor: UIColor
    ) async -> UIImage? {
        guard size.width > 0, size.height > 0, !locations.isEmpty else { return nil }

        let key = "\(cacheKey)-\(Int(size.width))x\(Int(size.height))@\(scale)-\(colorScheme)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let options = MKMapSnapshotter.Options()
        options.region = MapFraming.region(fitting: locations.map(\.coordinate), padding: 1.6)
        options.size = size
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection { traits in
            traits.displayScale = scale
            traits.userInterfaceStyle = colorScheme == .dark ? .dark : .light
        }

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            snapshot.image.draw(at: .zero)
            for location in locations {
                let point = snapshot.point(for: location.coordinate)
                let dot = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: dot.insetBy(dx: -2, dy: -2)).fill()
                pinColor.setFill()
                UIBezierPath(ovalIn: dot).fill()
            }
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
