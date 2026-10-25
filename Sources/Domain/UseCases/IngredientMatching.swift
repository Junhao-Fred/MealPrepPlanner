//  Created by Junhao Huang on 2026/10/23.

import Foundation

/// The one rule recipes, pantry stock and the shopping list use to decide that two ingredients are the same.
/// Names ignore whitespace, case and simple English plurals; units convert within mass, volume and count.
enum IngredientMatching {
    struct Key: Hashable, Sendable {
        let name: String
        /// The unit amounts are compared in, such as "g" for kilograms. Unknown units stay as typed.
        let unit: String
    }

    static func key(name: String, unit: String) -> Key {
        Key(name: normalizedName(name), unit: conversion(for: unit).base)
    }

    /// `quantity` of `unit` expressed in the key's comparison unit.
    static func baseQuantity(_ quantity: Decimal, unit: String) -> Decimal {
        quantity * conversion(for: unit).factor
    }

    /// A comparison-unit amount expressed back in `unit`, rounded to six decimal places.
    static func quantity(fromBase base: Decimal, unit: String) -> Decimal {
        var exact = base / conversion(for: unit).factor
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 6, .plain)
        return rounded
    }

    /// Shows a total in its comparison unit, switching g to kg and ml to l from 1000.
    static func readableAmount(_ base: Decimal, baseUnit: String) -> (quantity: Decimal, unit: String) {
        switch baseUnit {
        case "g" where base >= 1000: return (quantity(fromBase: base, unit: "kg"), "kg")
        case "ml" where base >= 1000: return (quantity(fromBase: base, unit: "l"), "l")
        default: return (quantity(fromBase: base, unit: baseUnit), baseUnit)
        }
    }

    /// True when `unit` is already its own comparison unit, so totals can be shown in it unchanged.
    static func isBaseUnit(_ unit: String) -> Bool {
        conversion(for: unit).factor == 1
    }

    static func normalizedName(_ name: String) -> String {
        singular(compact(name))
    }

    private static func compact(_ text: String) -> String {
        text.filter { !$0.isWhitespace }.lowercased()
    }

    private static func conversion(for unit: String) -> (base: String, factor: Decimal) {
        let compacted = compact(unit)
        return conversions[compacted] ?? (singular(compacted), 1)
    }

    /// Drops common English plural endings: tomatoes, berries, eggs, peaches.
    private static func singular(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") {
            return String(word.dropLast(3)) + "y"
        }
        for suffix in ["oes", "ches", "shes", "xes", "sses", "zes"] where word.hasSuffix(suffix) {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s") && !["ss", "us", "is"].contains(where: word.hasSuffix) {
            return String(word.dropLast())
        }
        return word
    }

    private static let conversions: [String: (base: String, factor: Decimal)] = {
        var table: [String: (base: String, factor: Decimal)] = [:]
        func add(_ names: [String], base: String, factor: String) {
            for name in names { table[name] = (base, Decimal(string: factor)!) }
        }
        add(["g", "gram", "grams", "gr"], base: "g", factor: "1")
        add(["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"], base: "g", factor: "1000")
        add(["mg", "milligram", "milligrams"], base: "g", factor: "0.001")
        add(["oz", "ounce", "ounces"], base: "g", factor: "28.349523")
        add(["lb", "lbs", "pound", "pounds"], base: "g", factor: "453.59237")
        add(["ml", "milliliter", "milliliters", "millilitre", "millilitres"], base: "ml", factor: "1")
        add(["l", "liter", "liters", "litre", "litres"], base: "ml", factor: "1000")
        add(["cl"], base: "ml", factor: "10")
        add(["dl"], base: "ml", factor: "100")
        add(["tsp", "teaspoon", "teaspoons"], base: "ml", factor: "5")
        add(["tbsp", "tablespoon", "tablespoons"], base: "ml", factor: "15")
        add(["cup", "cups"], base: "ml", factor: "240")
        add(["piece", "pieces", "pc", "pcs", "count", "each", "ea", "item", "items", "whole"], base: "piece", factor: "1")
        return table
    }()
}
