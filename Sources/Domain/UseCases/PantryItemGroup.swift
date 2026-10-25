//  Created by Junhao Huang on 2026/10/23.

import Foundation

/// All pantry batches of one ingredient, as `IngredientMatching` defines it, shown and used as one item.
/// Batches stay separate in storage so each keeps its own expiry date.
struct PantryItemGroup: Identifiable, Equatable, Sendable {
    let id: IngredientMatching.Key
    let name: String
    /// Total of every batch, in `unit`.
    let quantity: Decimal
    let unit: String
    /// Soonest expiry first; undated batches last.
    let batches: [Ingredient]

    var earliestExpiry: Date? { batches.first?.expiryDate }

    /// Groups batches by ingredient, ordered by name. Batches that all use one unit keep it;
    /// mixed units are totalled in g or ml, or kg or l from 1000.
    static func group(_ ingredients: [Ingredient]) -> [PantryItemGroup] {
        let grouped = Dictionary(grouping: ingredients) { IngredientMatching.key(name: $0.name, unit: $0.unit) }
        return grouped.map { key, batches in
            let sorted = batches.sorted(by: soonestFirst)
            let units = Set(sorted.map { $0.unit.filter { !$0.isWhitespace }.lowercased() })
            let (quantity, unit): (Decimal, String)
            if units.count == 1, let first = sorted.first {
                quantity = sorted.reduce(0) { $0 + $1.quantity }
                unit = first.unit
            } else {
                let base = sorted.reduce(Decimal(0)) { $0 + IngredientMatching.baseQuantity($1.quantity, unit: $1.unit) }
                (quantity, unit) = IngredientMatching.readableAmount(base, baseUnit: key.unit)
            }
            return PantryItemGroup(id: key, name: displayName(sorted), quantity: quantity, unit: unit, batches: sorted)
        }
        .sorted { ($0.name.lowercased(), $0.id.unit) < ($1.name.lowercased(), $1.id.unit) }
    }

    static func soonestFirst(_ lhs: Ingredient, _ rhs: Ingredient) -> Bool {
        (lhs.expiryDate ?? .distantFuture, lhs.id.uuidString) < (rhs.expiryDate ?? .distantFuture, rhs.id.uuidString)
    }

    /// The shortest spelling, so "Tomato" is preferred over "Tomatoes".
    private static func displayName(_ batches: [Ingredient]) -> String {
        batches.map(\.name).min { ($0.count, $0) < ($1.count, $1) } ?? ""
    }
}
