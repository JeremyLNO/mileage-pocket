import Foundation
import SwiftData

/// Only the fields the selected country's rule pack actually needs are shown in the UI;
/// the model carries the superset so switching country never loses data.
@Model
final class Vehicle {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?
    var model: String?
    var registration: String?
    var vehicleTypeRaw: String = VehicleType.car.rawValue
    var fuelTypeRaw: String?
    /// French "chevaux fiscaux" and equivalents.
    var fiscalHorsepower: Int?
    /// Engine displacement in cm³ (Ireland bands, among others).
    var engineCapacity: Int?
    var powerKW: Int?
    var isDefault: Bool = false
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String = "", vehicleType: VehicleType = .car, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.vehicleTypeRaw = vehicleType.rawValue
        self.isDefault = isDefault
        self.createdAt = Date()
    }

    var vehicleType: VehicleType {
        get { VehicleType(rawValue: vehicleTypeRaw) ?? .car }
        set { vehicleTypeRaw = newValue.rawValue }
    }

    var fuelType: FuelType? {
        get { fuelTypeRaw.flatMap(FuelType.init(rawValue:)) }
        set { fuelTypeRaw = newValue?.rawValue }
    }
}
