//  Created by Junhao Huang on 2026/10/19.

import Foundation

/// Forwards every call to the wrapped repository and calls `didWrite` after each successful write.
/// Failed writes and reads never call it.
struct WidgetRefreshingRepository: MealPlanningRepository {
    private let base: any MealPlanningRepository
    private let didWrite: @Sendable () async -> Void

    init(
        wrapping base: any MealPlanningRepository,
        didWrite: @escaping @Sendable () async -> Void
    ) {
        self.base = base
        self.didWrite = didWrite
    }

    // MARK: Writes

    func saveMeal(_ meal: Meal) async throws {
        try await base.saveMeal(meal)
        await didWrite()
    }

    func saveIngredient(_ ingredient: Ingredient) async throws {
        try await base.saveIngredient(ingredient)
        await didWrite()
    }

    func saveMealPlanEntry(_ entry: MealPlanEntry) async throws {
        try await base.saveMealPlanEntry(entry)
        await didWrite()
    }

    func savePlannedMeal(_ entry: MealPlanEntry) async throws {
        try await base.savePlannedMeal(entry)
        await didWrite()
    }

    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws {
        try await base.updateMealPlanEntry(entry)
        await didWrite()
    }

    // MARK: Reads

    func fetchUpcomingMeals() async throws -> [MealPlanEntry] {
        try await base.fetchUpcomingMeals()
    }

    func fetchMealPlanEntries(
        from start: Date,
        to end: Date,
        includingPrepared includePrepared: Bool
    ) async throws -> [MealPlanEntry] {
        try await base.fetchMealPlanEntries(from: start, to: end, includingPrepared: includePrepared)
    }

    func fetchAvailableIngredients() async throws -> [Ingredient] {
        try await base.fetchAvailableIngredients()
    }

    func fetchIngredientsExpiring(before date: Date) async throws -> [Ingredient] {
        try await base.fetchIngredientsExpiring(before: date)
    }
}
