import MapKit

/// Finds places that aren't bundled, using Apple Maps. Results become
/// user-added `Location`s with no rating.
enum PlaceSearch {
    /// Davis and the surrounding area, where searches are focused.
    static let region = MKCoordinateRegion(
        center: MapFraming.davis.center,
        span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
    )

    static func search(_ query: String) async throws -> [Location] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = [.pointOfInterest, .address]
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(15).map(location(from:))
    }

    /// A short street address for a dropped pin, or nil if none was found.
    static func address(at coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first
            else { return nil }
            return item.address?.shortAddress ?? item.address?.fullAddress
        } else {
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
            return formatted(placemark)
        }
    }

    static func location(from item: MKMapItem) -> Location {
        let name = item.name ?? "Unnamed Place"
        let coordinate: CLLocationCoordinate2D
        let address: String
        if #available(iOS 26, *) {
            coordinate = item.location.coordinate
            address = item.address?.shortAddress ?? item.address?.fullAddress ?? ""
        } else {
            coordinate = item.placemark.coordinate
            address = formatted(item.placemark)
        }
        return Location.userAdded(
            id: stableID(name: name, coordinate: coordinate),
            name: name,
            category: categoryName(item.pointOfInterestCategory),
            address: address,
            coordinate: coordinate
        )
    }

    /// The same Apple Maps place gets the same ID every time, so adding it to
    /// two collections doesn't create two copies.
    static func stableID(name: String, coordinate: CLLocationCoordinate2D) -> Location.ID {
        let dashed = Catalog.normalized(name).map { $0.isLetter || $0.isNumber ? $0 : Character("-") }
        let slug = String(dashed).split(separator: "-").joined(separator: "-")
        return Location.addedIDPrefix + "\(slug)-\(String(format: "%.4f_%.4f", coordinate.latitude, coordinate.longitude))"
    }

    /// "MKPOICategoryFastFood" → "Fast Food".
    static func categoryName(_ category: MKPointOfInterestCategory?) -> String {
        guard let raw = category?.rawValue else { return "Place" }
        let name = raw.replacingOccurrences(of: "MKPOICategory", with: "")
        var words = ""
        for character in name {
            if character.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(character)
        }
        return words.isEmpty ? "Place" : words
    }

    /// True when an Apple Maps result is a bundled place: similar name, within about 150 m.
    static func isSamePlace(_ result: Location, as bundled: Location) -> Bool {
        let a = Catalog.normalized(result.name), b = Catalog.normalized(bundled.name)
        guard a.contains(b) || b.contains(a) else { return false }
        let distance = CLLocation(latitude: result.latitude, longitude: result.longitude)
            .distance(from: CLLocation(latitude: bundled.latitude, longitude: bundled.longitude))
        return distance < 150
    }

    /// For iOS 17–25, before `MKMapItem.address` existed.
    private static func formatted(_ placemark: CLPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street, placemark.locality].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
    }
}
