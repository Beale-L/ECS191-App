import MapKit
import SwiftUI

/// Adds a place that isn't listed anywhere: move the map under the pin, then
/// name it. The address fills in from the pin's position and can be edited.
struct DropPinView: View {
    let suggestedName: String
    @Binding var draft: CollectionDraft

    @Environment(\.dismiss) private var dismiss
    @State private var position = MapCameraPosition.region(PlaceSearch.region.zoomed(to: 0.02))
    @State private var center = MapFraming.davis.center
    @State private var name = ""
    @State private var category = "Restaurant"
    @State private var address = ""
    /// The last address filled in from the pin, to tell it apart from typing.
    @State private var lookedUpAddress = ""
    @State private var isLookingUpAddress = false

    private static let categories = ["Restaurant", "Fast Food", "Cafe", "Bar", "Bakery", "Store", "Park", "Other"]

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position)
                .mapStyle(.standard(pointsOfInterest: .including([.restaurant, .cafe, .foodMarket, .store, .park])))
                .onMapCameraChange(frequency: .onEnd) { context in
                    center = context.region.center
                }
                .overlay {
                    // The pin's point sits at the map's center.
                    Image(systemName: "mappin")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.red)
                        .offset(y: -17)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .frame(height: 280)
                .accessibilityLabel("Map. Move it so the pin is on the place.")

            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("PinNameField")
                    Picker("Category", selection: $category) {
                        ForEach(Self.categories, id: \.self) { Text($0) }
                    }
                    HStack {
                        TextField("Address", text: $address)
                            .accessibilityIdentifier("PinAddressField")

                        if isLookingUpAddress { ProgressView() }
                    }
                } footer: {
                    Text("Move the map so the pin is on the place. The address fills in automatically.")
                }
            }
        }
        .navigationTitle("Drop a Pin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: add)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear { if name.isEmpty { name = suggestedName } }
        .task(id: CoordinateKey(center)) { await lookUpAddress() }
    }

    /// True once the person has typed their own address; the pin stops overwriting it.
    private var addressWasEdited: Bool { address != lookedUpAddress }

    private func lookUpAddress() async {
        guard !addressWasEdited else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isLookingUpAddress = true
        let found = await PlaceSearch.address(at: center)
        // If the lookup fails, clear the old address rather than leave one
        // that no longer matches the pin. The person can type it instead.
        if !Task.isCancelled, !addressWasEdited {
            lookedUpAddress = found ?? ""
            address = found ?? ""
        }
        isLookingUpAddress = false
    }

    private func add() {
        let place = Location.userAdded(
            name: trimmedName,
            category: category,
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            coordinate: center
        )
        draft.addNewPlace(place)
        dismiss()
    }

    /// Coordinates aren't Equatable; this lets `.task(id:)` rerun when the pin moves.
    private struct CoordinateKey: Equatable {
        let latitude: Double
        let longitude: Double
        init(_ coordinate: CLLocationCoordinate2D) {
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }
    }
}

private extension MKCoordinateRegion {
    func zoomed(to span: CLLocationDegrees) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
    }
}
