//  Created by Mingchen Liang on 2026/10/20.

import Foundation

/// Parses a whole positive quantity input, without accepting partial numbers or grouping.
enum PantryQuantityParser {
    static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        let parts = input.components(separatedBy: separator)
        guard parts.count <= 2,
              parts.allSatisfy({ part in
                  !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
              }) else { return nil }

        let normalized = parts.joined(separator: ".")
        guard let quantity = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              !quantity.isNaN, quantity > 0 else { return nil }
        return quantity
    }
}
