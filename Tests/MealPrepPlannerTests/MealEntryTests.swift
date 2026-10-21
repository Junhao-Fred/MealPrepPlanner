//  Created by Mingchen Liang on 2026/10/21.

import Foundation
import Testing
@testable import MealPrepPlanner

@MainActor
@Suite("Meal scheduling form and saves")
struct MealEntryTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let locale = Locale(identifier: "en_AU")

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    @Test("Drafts retain IDs, trim names and convert localized ingredient quantities")
    func draftConversion() throws {
        var draft = makeDraft()
        draft.name = " Rice bowl "
        draft.ingredients[0].name = " Rice "
        draft.ingredients[0].unit = " g "
        draft.ingredients[0].quantityText = "100,5"
        let first = try draft.makeEntry(locale: Locale(identifier: "de_DE"))
        let second = try draft.makeEntry(locale: Locale(identifier: "de_DE"))

        #expect(first == second)
        #expect(first.id == draft.id)
        #expect(first.meal.id == draft.mealID)
        #expect(first.meal.ingredients[0].id == draft.ingredients[0].id)
        #expect(first.meal.ingredients[0].quantity == Decimal(1005) / 10)
        #expect(first.meal.name == "Rice bowl")
        #expect(first.meal.ingredients[0].name == "Rice")
        #expect(first.meal.ingredients[0].unit == "g")
        #expect(!first.isPrepared)
    }

    @Test("Adding and removing rows preserves the retained ingredient's identity")
    func editsRecipeRows() throws {
        var draft = makeDraft()
        let originalID = draft.ingredients[0].id
        var second = MealIngredientDraft()
        second.name = "Water"
        second.quantityText = "200"
        second.unit = "ml"
        draft.ingredients.append(second)
        draft.ingredients.removeAll { $0.id == originalID }

        let entry = try draft.makeEntry(locale: locale)
        #expect(entry.meal.ingredients.count == 1)
        #expect(entry.meal.ingredients[0].id == second.id)
        #expect(entry.meal.ingredients[0].name == "Water")
    }

    @Test("Invalid quantities identify the offending recipe row", arguments: ["", "0", "-1", "12g", "1.2.3"])
    func rejectsInvalidQuantities(text: String) {
        var draft = makeDraft()
        var invalid = MealIngredientDraft()
        invalid.quantityText = text
        draft.ingredients.append(invalid)
        do {
            _ = try draft.makeEntry(locale: locale)
            Issue.record("Expected invalid quantity in row 2")
        } catch let error as MealEntryDraftError {
            #expect(error == .invalidQuantity(row: 2))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Saving a meal outside the displayed week refreshes its date range")
    func savesAndShowsNewDate() async throws {
        let repository = InMemoryMealRepository()
        let model = makeModel(repository)
        var draft = makeDraft()
        draft.scheduledDate = calendar.date(byAdding: .day, value: 10, to: now)!
        let entry = try draft.makeEntry(locale: locale)

        let saved = await model.save(entry)

        #expect(saved)
        #expect(model.rangeStart == calendar.startOfDay(for: entry.scheduledDate))
        #expect(model.days.flatMap(\.entries) == [entry])
        #expect(model.hasLoaded)
        #expect(!model.isBusy)
        #expect(model.errorMessage == nil)
        let writes = await repository.writeCount
        #expect(writes == 1)
    }

    @Test("Name, recipe and scheduling validation still go through the existing save use case")
    func rejectsInvalidPlansWithoutWriting() async throws {
        let repository = InMemoryMealRepository()
        let model = makeModel(repository)
        let entry = try makeDraft().makeEntry(locale: locale)
        var blankName = entry
        blankName.meal.name = " "
        var emptyRecipe = entry
        emptyRecipe.meal.ingredients = []
        var emptyUnit = entry
        emptyUnit.meal.ingredients[0].unit = ""
        var past = entry
        past.scheduledDate = now.addingTimeInterval(-1)

        for invalid in [blankName, emptyRecipe, emptyUnit, past] {
            let saved = await model.save(invalid)
            #expect(!saved)
            #expect(model.errorMessage != nil)
            #expect(!model.isBusy)
        }
        #expect(model.days.isEmpty)
        let writes = await repository.writeCount
        #expect(writes == 0)
    }

    @Test("A failed save retains the draft and retries the original plan ID")
    func failedSaveCanRetry() async throws {
        let repository = InMemoryMealRepository()
        let model = makeModel(repository)
        let draft = makeDraft()
        await repository.fail(.write, with: .writeFailed)

        let failed = await model.save(try draft.makeEntry(locale: locale))
        #expect(!failed)
        #expect(model.days.isEmpty)
        #expect(!model.isBusy)
        #expect(draft.name == "Rice bowl")
        #expect(draft.ingredients[0].quantityText == "100")

        await repository.clearFailures()
        let saved = await model.save(try draft.makeEntry(locale: locale))
        #expect(saved)
        #expect(model.days.flatMap(\.entries).map(\.id) == [draft.id])
        #expect(model.errorMessage == nil)
        let writes = await repository.writeCount
        #expect(writes == 1)
    }

    @Test("Refresh failure after a successful save returns success and retries only the read")
    func successfulSaveWithFailedRefresh() async throws {
        let repository = InMemoryMealRepository()
        let model = makeModel(repository)
        let entry = try makeDraft().makeEntry(locale: locale)
        await repository.fail(.read, with: .readFailed)

        let saved = await model.save(entry)
        #expect(saved)
        #expect(model.errorMessage?.contains("Meal saved.") == true)
        #expect(!model.isBusy)

        await repository.clearFailures()
        await model.load()
        #expect(model.days.flatMap(\.entries) == [entry])
        #expect(model.errorMessage == nil)
        let writes = await repository.writeCount
        #expect(writes == 1)
    }

    @Test("New drafts use a future time even while browsing past plans")
    func draftStartsInFuture() async {
        let model = makeModel(InMemoryMealRepository())
        await model.showRange(starting: now.addingTimeInterval(-10 * 86_400))
        #expect(model.makeDraft().scheduledDate > now)
    }

    private func makeModel(_ repository: InMemoryMealRepository) -> MealPlanViewModel {
        let fixedNow = now
        return MealPlanViewModel(repository: repository, calendar: calendar, now: { fixedNow })
    }

    private func makeDraft() -> MealEntryDraft {
        var draft = MealEntryDraft(scheduledDate: now.addingTimeInterval(3_600))
        draft.name = "Rice bowl"
        draft.ingredients[0].name = "Rice"
        draft.ingredients[0].quantityText = "100"
        draft.ingredients[0].unit = "g"
        return draft
    }
}
