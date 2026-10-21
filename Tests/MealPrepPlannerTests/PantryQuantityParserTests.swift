//  Created by Mingchen Liang on 2026/10/20.

import Foundation
import Testing
@testable import MealPrepPlanner

@Suite("Pantry quantity input")
struct PantryQuantityParserTests {
    @Test("Whole amounts accept surrounding whitespace")
    func parsesWholeAmount() {
        #expect(PantryQuantityParser.parse(" \n25\t ", locale: Locale(identifier: "en_AU")) == 25)
    }

    @Test("Fractional amounts retain decimal precision")
    func parsesDecimalAmount() {
        #expect(PantryQuantityParser.parse("0.125", locale: Locale(identifier: "en_AU")) == Decimal(125) / 1_000)
    }

    @Test("Decimal commas follow the input locale")
    func parsesLocalizedDecimal() {
        #expect(PantryQuantityParser.parse("1,25", locale: Locale(identifier: "de_DE")) == Decimal(125) / 100)
        #expect(PantryQuantityParser.parse("1.25", locale: Locale(identifier: "de_DE")) == nil)
    }

    @Test("Invalid or partial numbers never become stock deductions", arguments: [
        "", "  ", "0", "0.00", "-1", "+1", "NaN", "Infinity", "1e3", "12g", "12.5abc",
        "1 000", "1,000", "1.2.3", ".", ".5", "5.", "1\n2"
    ])
    func rejectsInvalidAmount(input: String) {
        #expect(PantryQuantityParser.parse(input, locale: Locale(identifier: "en_AU")) == nil)
    }
}
