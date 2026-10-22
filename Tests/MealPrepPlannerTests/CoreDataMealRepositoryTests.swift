//  Created by Junhao Huang on 2026/10/18.

import CoreData
import Foundation
import Testing
@testable import MealPrepPlanner

@Suite("Core Data meal repository")
struct CoreDataMealRepositoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    @Test("Saves and reads a planned meal with its ingredients in order")
    func savesPlannedMeal() async throws {
        let repository = try await makeRepository()
        let entry = makeEntry(at: now.addingTimeInterval(3_600))

        try await repository.savePlannedMeal(entry)

        let upcoming = try await repository.fetchUpcomingMeals()
        #expect(upcoming == [entry])
    }

    @Test("Upcoming meals exclude prepared and past entries, oldest first")
    func upcomingFiltersAndSorts() async throws {
        let repository = try await makeRepository()
        let later = makeEntry(at: now.addingTimeInterval(2 * day))
        let sooner = makeEntry(at: now.addingTimeInterval(day))
        let past = makeEntry(at: now.addingTimeInterval(-day))
        var prepared = makeEntry(at: now.addingTimeInterval(day))
        prepared.isPrepared = true
        for entry in [later, sooner, past, prepared] {
            try await repository.savePlannedMeal(entry)
        }

        let upcoming = try await repository.fetchUpcomingMeals()

        #expect(upcoming == [sooner, later])
    }

    @Test("Date range is half-open and can hide prepared entries")
    func rangeIsHalfOpen() async throws {
        let repository = try await makeRepository()
        let atStart = makeEntry(at: now)
        let atEnd = makeEntry(at: now.addingTimeInterval(day))
        var prepared = makeEntry(at: now.addingTimeInterval(3_600))
        prepared.isPrepared = true
        for entry in [atStart, atEnd, prepared] {
            try await repository.savePlannedMeal(entry)
        }

        let all = try await repository.fetchMealPlanEntries(
            from: now,
            to: now.addingTimeInterval(day),
            includingPrepared: true
        )
        let unfinished = try await repository.fetchMealPlanEntries(
            from: now,
            to: now.addingTimeInterval(day),
            includingPrepared: false
        )

        #expect(all == [atStart, prepared])
        #expect(unfinished == [atStart])
    }

    @Test("Pantry queries skip empty batches and batches without expiry")
    func pantryQueries() async throws {
        let repository = try await makeRepository()
        let soon = Ingredient(name: "Spinach", quantity: 250, unit: "g", expiryDate: now.addingTimeInterval(day))
        let later = Ingredient(name: "Rice", quantity: 2, unit: "kg", expiryDate: now.addingTimeInterval(10 * day))
        let noExpiry = Ingredient(name: "Salt", quantity: 1, unit: "kg")
        let empty = Ingredient(name: "Beans", quantity: 0, unit: "g", expiryDate: now)
        for ingredient in [soon, later, noExpiry, empty] {
            try await repository.saveIngredient(ingredient)
        }

        let available = try await repository.fetchAvailableIngredients()
        let expiring = try await repository.fetchIngredientsExpiring(before: now.addingTimeInterval(3 * day))

        #expect(available.map(\.name) == ["Rice", "Salt", "Spinach"])
        #expect(expiring == [soon])
    }

    @Test("Updating an entry marks it prepared")
    func updatesEntry() async throws {
        let repository = try await makeRepository()
        var entry = makeEntry(at: now.addingTimeInterval(3_600))
        try await repository.savePlannedMeal(entry)

        entry.isPrepared = true
        try await repository.updateMealPlanEntry(entry)

        let stored = try await repository.fetchMealPlanEntries(
            from: now,
            to: now.addingTimeInterval(day),
            includingPrepared: true
        )
        #expect(stored == [entry])
    }

    @Test("Updating a missing entry throws notFound")
    func updateMissingEntryThrows() async throws {
        let repository = try await makeRepository()

        do {
            try await repository.updateMealPlanEntry(makeEntry(at: now))
            Issue.record("Expected RepositoryError.notFound")
        } catch let error as RepositoryError {
            #expect(error == .notFound)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let upcoming = try await repository.fetchUpcomingMeals()
        #expect(upcoming.isEmpty)
    }

    @Test("Deleting an ingredient removes that batch; a missing ID throws notFound")
    func deletesIngredient() async throws {
        let repository = try await makeRepository()
        let rice = Ingredient(name: "Rice", quantity: 2, unit: "kg")
        let salt = Ingredient(name: "Salt", quantity: 1, unit: "kg")
        try await repository.saveIngredient(rice)
        try await repository.saveIngredient(salt)

        try await repository.deleteIngredient(id: rice.id)
        await #expect(throws: RepositoryError.notFound) {
            try await repository.deleteIngredient(id: rice.id)
        }

        let available = try await repository.fetchAvailableIngredients()
        #expect(available == [salt])
    }

    private func makeRepository() async throws -> CoreDataMealRepository {
        let controller = try await PersistenceController.makeInMemory()
        let now = now
        return CoreDataMealRepository(container: controller.container, now: { now })
    }

    private func makeEntry(at date: Date) -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(
                name: "Pasta",
                ingredients: [
                    MealIngredient(name: "Pasta", quantity: 120, unit: "g"),
                    MealIngredient(name: "Tomato", quantity: 2, unit: "count")
                ]
            ),
            scheduledDate: date,
            mealType: .dinner
        )
    }
}
