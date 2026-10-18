//  Created by Junhao Huang on 2026/10/17.

import Foundation
@testable import MealPrepPlanner

/// Dictionary-backed repository for use case and ViewModel tests.
/// Follows the `MealPlanningRepository` contract and can inject storage failures.
actor InMemoryMealRepository: MealPlanningRepository {
    enum Operation: Sendable {
        case read
        case write
    }

    private var meals: [UUID: Meal]
    private var entries: [UUID: MealPlanEntry]
    private var ingredients: [UUID: Ingredient]
    private var failures: [Operation: RepositoryError] = [:]
    private let now: @Sendable () -> Date

    /// Number of successful writes, so tests can assert that invalid input never reached storage.
    private(set) var writeCount = 0

    init(
        meals: [Meal] = [],
        entries: [MealPlanEntry] = [],
        ingredients: [Ingredient] = [],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        var mealsByID: [UUID: Meal] = [:]
        var entriesByID: [UUID: MealPlanEntry] = [:]
        var ingredientsByID: [UUID: Ingredient] = [:]
        for meal in meals { mealsByID[meal.id] = meal }
        for entry in entries {
            entriesByID[entry.id] = entry
            mealsByID[entry.meal.id] = entry.meal
        }
        for ingredient in ingredients { ingredientsByID[ingredient.id] = ingredient }
        self.meals = mealsByID
        self.entries = entriesByID
        self.ingredients = ingredientsByID
        self.now = now
    }

    /// Makes every later call of `operation` throw `error` until `clearFailures()`.
    func fail(_ operation: Operation, with error: RepositoryError) {
        failures[operation] = error
    }

    func clearFailures() {
        failures.removeAll()
    }

    // MARK: Writes

    func saveMeal(_ meal: Meal) async throws {
        try check(.write)
        store(meal)
        writeCount += 1
    }

    func saveIngredient(_ ingredient: Ingredient) async throws {
        try check(.write)
        ingredients[ingredient.id] = ingredient
        writeCount += 1
    }

    func saveMealPlanEntry(_ entry: MealPlanEntry) async throws {
        try check(.write)
        entries[entry.id] = entry
        writeCount += 1
    }

    func savePlannedMeal(_ entry: MealPlanEntry) async throws {
        try check(.write)
        store(entry.meal)
        entries[entry.id] = entry
        writeCount += 1
    }

    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws {
        try check(.write)
        guard entries[entry.id] != nil else { throw RepositoryError.notFound }
        entries[entry.id] = entry
        writeCount += 1
    }

    // MARK: Reads

    func fetchUpcomingMeals() async throws -> [MealPlanEntry] {
        try check(.read)
        let current = now()
        return sorted(entries.values.filter { !$0.isPrepared && $0.scheduledDate >= current })
    }

    func fetchMealPlanEntries(
        from start: Date,
        to end: Date,
        includingPrepared includePrepared: Bool
    ) async throws -> [MealPlanEntry] {
        try check(.read)
        return sorted(entries.values.filter { entry in
            entry.scheduledDate >= start
                && entry.scheduledDate < end
                && (includePrepared || !entry.isPrepared)
        })
    }

    func fetchAvailableIngredients() async throws -> [Ingredient] {
        try check(.read)
        return ingredients.values
            .filter(\.isAvailable)
            .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
    }

    func fetchIngredientsExpiring(before date: Date) async throws -> [Ingredient] {
        try check(.read)
        return ingredients.values
            .filter { ingredient in
                guard ingredient.isAvailable, let expiry = ingredient.expiryDate else { return false }
                return expiry < date
            }
            .sorted { lhs, rhs in
                if lhs.expiryDate != rhs.expiryDate {
                    return lhs.expiryDate ?? .distantFuture < rhs.expiryDate ?? .distantFuture
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    // MARK: Helpers

    private func check(_ operation: Operation) throws {
        if let error = failures[operation] { throw error }
    }

    /// Upserts the recipe and refreshes every entry that schedules it.
    private func store(_ meal: Meal) {
        meals[meal.id] = meal
        for id in Array(entries.keys) where entries[id]?.meal.id == meal.id {
            entries[id]?.meal = meal
        }
    }

    private func sorted(_ items: some Sequence<MealPlanEntry>) -> [MealPlanEntry] {
        items.sorted { lhs, rhs in
            if lhs.scheduledDate != rhs.scheduledDate {
                return lhs.scheduledDate < rhs.scheduledDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
