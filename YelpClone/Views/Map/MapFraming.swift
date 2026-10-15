import MapKit

enum MapFraming {
    static let davis = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 38.5449, longitude: -121.7405),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    /// The smallest region containing every coordinate, grown by `padding` so
    /// pins aren't flush with the edges. A single point gets `minimumSpan`.
    static func region(
        fitting coordinates: [CLLocationCoordinate2D],
        padding: Double = 1.4,
        minimumSpan: CLLocationDegrees = 0.008
    ) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLng = longitudes.min(), let maxLng = longitudes.max()
        else { return davis }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * padding, minimumSpan),
                longitudeDelta: max((maxLng - minLng) * padding, minimumSpan)
            )
        )
    }
}
