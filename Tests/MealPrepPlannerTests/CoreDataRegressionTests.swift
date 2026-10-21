//  Created by Junhao Huang on 2026/10/20.

import Foundation
import Testing
@testable import MealPrepPlanner

/// Regression checks for T02, T06 and T09 against a real SQLite file.
/// Each `open` builds a new Core Data stack on the same file, like relaunching the app after it was killed.
@Suite("Core Data regression")
struct CoreDataRegressionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MealPrepPlannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("MealPrepPlanner.sqlite")
    }

    private func removeStore(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func open(_ url: URL) async throws -> CoreDataMealRepository {
        let persistence = try await PersistenceController.makePersistent(storeURL: url)
        return CoreDataMealRepository(container: persistence.container, now: { now })
    }

    private func makeEntry() -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(name: "Tomato Pasta", ingredients: [
                MealIngredient(name: "Tomato", quantity: 300, unit: "g"),
                MealIngredient(name: "Pasta", quantity: 200, unit: "g")
            ]),
            scheduledDate: now.addingTimeInterval(3_600),
            mealType: .dinner
        )
    }

    @Test("T09 plans and pantry stock survive a cold start and stay editable")
    func coldStartKeepsDataEditable() async throws {
        let url = try makeStoreURL()
        defer { removeStore(at: url) }
        var entry = makeEntry()
        var rice = Ingredient(name: "Rice", quantity: 500, unit: "g", expiryDate: now.addingTimeInterval(86_400))

        do {
            let repository = try await open(url)
            try await repository.savePlannedMeal(entry)
            try await repository.saveIngredient(rice)
        }

        do {
            let repository = try await open(url)
            #expect(try await repository.fetchUpcomingMeals() == [entry])
            #expect(try await repository.fetchAvailableIngredients() == [rice])
            entry.isPrepared = true
            rice.quantity = 300
            try await repository.updateMealPlanEntry(entry)
            try await repository.saveIngredient(rice)
        }

        let repository = try await open(url)
        let stored = try await repository.fetchMealPlanEntries(
            from: .distantPast, to: .distantFuture, includingPrepared: true
        )
        #expect(stored == [entry])
        #expect(try await repository.fetchUpcomingMeals().isEmpty)
        #expect(try await repository.fetchAvailableIngredients() == [rice])
    }

    @Test("T02 pantry updates survive restarts without duplicates, and used-up stock is no longer available")
    func pantryUpdatesSurviveRestarts() async throws {
        let url = try makeStoreURL()
        defer { removeStore(at: url) }
        var milk = Ingredient(name: "Milk", quantity: 1_000, unit: "ml")

        do {
            let repository = try await open(url)
            try await repository.saveIngredient(milk)
            milk.quantity = 400
            try await repository.saveIngredient(milk)
        }

        do {
            let repository = try await open(url)
            #expect(try await repository.fetchAvailableIngredients() == [milk])
            milk.quantity = 0
            try await repository.saveIngredient(milk)
        }

        let repository = try await open(url)
        #expect(try await repository.fetchAvailableIngredients().isEmpty)
    }

    @Test("T06 marking the same entry prepared twice keeps one prepared entry")
    func repeatedCompletionHasNoSideEffects() async throws {
        let url = try makeStoreURL()
        defer { removeStore(at: url) }
        let repository = try await open(url)
        var entry = makeEntry()
        try await repository.savePlannedMeal(entry)

        entry.isPrepared = true
        try await repository.updateMealPlanEntry(entry)
        try await repository.updateMealPlanEntry(entry)

        let stored = try await repository.fetchMealPlanEntries(
            from: .distantPast, to: .distantFuture, includingPrepared: true
        )
        #expect(stored == [entry])
    }
}
