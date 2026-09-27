import Foundation

/// A pantry batch with remaining quantity and optional expiry.
struct Ingredient: Identifiable, Codable, Equatable, Sendable {
    let id: UUID

    var name: String

    var quantity: Decimal

    var unit: String

    /// Expiry is a local calendar day; the batch is valid through that day.
    var expiryDate: Date?

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Decimal,
        unit: String,
        expiryDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.expiryDate = expiryDate
    }

    var isAvailable: Bool { quantity > 0 }
}
