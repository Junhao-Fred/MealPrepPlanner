//  Created by Mingchen Liang on 2026/10/20.

import Foundation
import Testing
@testable import MealPrepPlanner

@MainActor
@Suite("Ingredient entry form state")
struct IngredientEntryDraftTests {
    private let locale = Locale(identifier: "en_AU")

    @Test("Expiry is optional and a selected day uses the supplied calendar")
    func optionalExpiryUsesLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 11 * 3_600))
        var draft = makeDraft()
        draft.expiryDate = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 20, hour: 15, minute: 30
        )))
        let expected = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)))

        #expect(try draft.makeIngredient(locale: locale, calendar: calendar).expiryDate == nil)
        draft.hasExpiryDate = true
        #expect(try draft.makeIngredient(locale: locale, calendar: calendar).expiryDate == expected)
        draft.hasExpiryDate = false
        #expect(try draft.makeIngredient(locale: locale, calendar: calendar).expiryDate == nil)
    }

    @Test("Localized decimal input and repeated conversions preserve the batch identity")
    func localizedQuantityAndStableID() throws {
        var draft = makeDraft()
        draft.quantityText = "1,25"

        let first = try draft.makeIngredient(locale: Locale(identifier: "de_DE"))
        let second = try draft.makeIngredient(locale: Locale(identifier: "de_DE"))

        #expect(first.quantity == Decimal(125) / 100)
        #expect(first.id == draft.id)
        #expect(second == first)
        #expect(makeDraft().id != draft.id)
    }

    @Test("Invalid quantities cannot produce a savable ingredient", arguments: ["", "0", "-1", "12g"])
    func rejectsInvalidQuantity(text: String) {
        var draft = makeDraft()
        draft.quantityText = text

        do {
            _ = try draft.makeIngredient(locale: locale)
            Issue.record("Expected PantryError.invalidQuantity")
        } catch let error as PantryError {
            #expect(error == .invalidQuantity)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("A failed save can retry the same draft without losing input or creating a second batch")
    func failedSaveRetriesSameBatch() async throws {
        var draft = makeDraft()
        draft.name = " Rice "
        draft.unit = " g "
        let repository = InMemoryMealRepository()
        let model = PantryViewModel(repository: repository)
        await repository.fail(.write, with: .writeFailed)

        let failed = await model.save(try draft.makeIngredient(locale: locale))
        #expect(!failed)
        #expect(model.ingredients.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(draft.name == " Rice ")
        #expect(draft.quantityText == "100.5")
        #expect(draft.unit == " g ")

        await repository.clearFailures()
        let saved = await model.save(try draft.makeIngredient(locale: locale))
        #expect(saved)
        let stored = try await repository.fetchAvailableIngredients()
        #expect(stored.count == 1)
        #expect(stored.first?.id == draft.id)
        #expect(stored.first?.name == "Rice")
        #expect(stored.first?.unit == "g")
        #expect(stored.first?.expiryDate == nil)
        let writes = await repository.writeCount
        #expect(writes == 1)
    }

    @Test("An added ingredient appears in the shared list and explicit usage updates its quantity")
    func addThenUseStock() async throws {
        let draft = makeDraft()
        let repository = InMemoryMealRepository()
        let model = PantryViewModel(repository: repository)
        let ingredient = try draft.makeIngredient(locale: locale)

        let saved = await model.save(ingredient)
        #expect(saved)
        #expect(model.ingredients == [ingredient])
        let used = await model.useIngredient(id: draft.id, quantity: Decimal(255) / 10)

        var expected = ingredient
        expected.quantity = 75
        #expect(used)
        #expect(model.ingredients == [expected])
        #expect(model.errorMessage == nil)
        let writes = await repository.writeCount
        #expect(writes == 2)
    }

    private func makeDraft() -> IngredientEntryDraft {
        var draft = IngredientEntryDraft()
        draft.name = "Rice"
        draft.unit = "g"
        draft.quantityText = "100.5"
        return draft
    }
}
