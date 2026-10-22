//  Created by Junhao Huang on 2026/10/17.

import Foundation
import Testing
@testable import MealPrepPlanner

struct InMemoryMealRepositoryTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    @Test("Saving the same entry twice keeps one copy")
    func saveUpsertsByID() async throws {
        let repository = makeRepository()
        var entry = makeEntry(at: now.addingTimeInterval(3_600))

        try await repository.saveMealPlanEntry(entry)
        entry.mealType = .dinner
        try await repository.saveMealPlanEntry(entry)

        let upcoming = try await repository.fetchUpcomingMeals()
        #expect(upcoming == [entry])
    }

    @Test("Upcoming meals exclude prepared and past entries, oldest first")
    func upcomingFiltersAndSorts() async throws {
        let later = makeEntry(at: now.addingTimeInterval(2 * day))
        let sooner = makeEntry(at: now.addingTimeInterval(day))
        let past = makeEntry(at: now.addingTimeInterval(-day))
        var prepared = makeEntry(at: now.addingTimeInterval(day))
        prepared.isPrepared = true
        let repository = makeRepository(entries: [later, sooner, past, prepared])

        let upcoming = try await repository.fetchUpcomingMeals()

        #expect(upcoming == [sooner, later])
    }

    @Test("Date range is half-open and can hide prepared entries")
    func rangeIsHalfOpen() async throws {
        let start = now
        let end = now.addingTimeInterval(day)
        let atStart = makeEntry(at: start)
        let atEnd = makeEntry(at: end)
        var prepared = makeEntry(at: start.addingTimeInterval(60))
        prepared.isPrepared = true
        let repository = makeRepository(entries: [atStart, atEnd, prepared])

        let all = try await repository.fetchMealPlanEntries(from: start, to: end, includingPrepared: true)
        let open = try await repository.fetchMealPlanEntries(from: start, to: end, includingPrepared: false)

        #expect(all == [atStart, prepared])
        #expect(open == [atStart])
    }

    @Test("Pantry queries skip empty batches and batches without expiry")
    func pantryFilters() async throws {
        let soon = Ingredient(name: "Spinach", quantity: 200, unit: "g", expiryDate: now.addingTimeInterval(day))
        let later = Ingredient(name: "Rice", quantity: 1, unit: "kg", expiryDate: now.addingTimeInterval(10 * day))
        let empty = Ingredient(name: "Milk", quantity: 0, unit: "ml", expiryDate: now.addingTimeInterval(day))
        let noExpiry = Ingredient(name: "Salt", quantity: 500, unit: "g")
        let repository = makeRepository(ingredients: [soon, later, empty, noExpiry])

        let available = try await repository.fetchAvailableIngredients()
        let expiring = try await repository.fetchIngredientsExpiring(before: now.addingTimeInterval(3 * day))

        #expect(Set(available.map(\.id)) == [soon.id, later.id, noExpiry.id])
        #expect(expiring == [soon])
    }

    @Test("Updating a missing entry throws notFound")
    func updateMissingEntryThrows() async {
        let repository = makeRepository()

        do {
            try await repository.updateMealPlanEntry(makeEntry(at: now))
            Issue.record("Expected RepositoryError.notFound")
        } catch let error as RepositoryError {
            #expect(error == .notFound)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let writeCount = await repository.writeCount
        #expect(writeCount == 0)
    }

    @Test("Deleting an ingredient removes that batch; a missing ID throws notFound")
    func deletesIngredient() async throws {
        let rice = Ingredient(name: "Rice", quantity: 1, unit: "kg")
        let salt = Ingredient(name: "Salt", quantity: 500, unit: "g")
        let repository = makeRepository(ingredients: [rice, salt])

        try await repository.deleteIngredient(id: rice.id)
        await #expect(throws: RepositoryError.notFound) {
            try await repository.deleteIngredient(id: rice.id)
        }

        let available = try await repository.fetchAvailableIngredients()
        let writeCount = await repository.writeCount
        #expect(available == [salt])
        #expect(writeCount == 1)
    }

    @Test("Injected failures surface as RepositoryError and a failed write stores nothing")
    func injectedFailures() async throws {
        let repository = makeRepository()
        await repository.fail(.write, with: .writeFailed)
        await repository.fail(.read, with: .storeUnavailable)

        do {
            try await repository.savePlannedMeal(makeEntry(at: now.addingTimeInterval(3_600)))
            Issue.record("Expected RepositoryError.writeFailed")
        } catch let error as RepositoryError {
            #expect(error == .writeFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try await repository.fetchUpcomingMeals()
            Issue.record("Expected RepositoryError.storeUnavailable")
        } catch let error as RepositoryError {
            #expect(error == .storeUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        await repository.clearFailures()
        let upcoming = try await repository.fetchUpcomingMeals()
        let writeCount = await repository.writeCount
        #expect(upcoming.isEmpty)
        #expect(writeCount == 0)
    }

    private func makeRepository(
        entries: [MealPlanEntry] = [],
        ingredients: [Ingredient] = []
    ) -> InMemoryMealRepository {
        let now = now
        return InMemoryMealRepository(entries: entries, ingredients: ingredients, now: { now })
    }

    private func makeEntry(at date: Date) -> MealPlanEntry {
        let ingredient = MealIngredient(name: "Oats", quantity: 100, unit: "g")
        let meal = Meal(name: "Porridge", ingredients: [ingredient])
        return MealPlanEntry(meal: meal, scheduledDate: date, mealType: .breakfast)
    }
}
