//  Created by Junhao Huang on 2026/9/27.

import Foundation

/// Storage contract for meal plans and pantry batches. Save methods upsert by ID.
/// Storage failures are reported as `RepositoryError`.
protocol MealPlanningRepository: Sendable {
    func saveMeal(_ meal: Meal) async throws

    func saveIngredient(_ ingredient: Ingredient) async throws

    func saveMealPlanEntry(_ entry: MealPlanEntry) async throws

    /// Atomically saves the recipe and entry; leaves neither on failure.
    func savePlannedMeal(_ entry: MealPlanEntry) async throws

    /// Returns future, unfinished entries in date order.
    func fetchUpcomingMeals() async throws -> [MealPlanEntry]

    /// Returns entries in `[start, end)`, oldest first.
    func fetchMealPlanEntries(
        from start: Date,
        to end: Date,
        includingPrepared includePrepared: Bool
    ) async throws -> [MealPlanEntry]

    /// Returns pantry batches with positive quantity.
    func fetchAvailableIngredients() async throws -> [Ingredient]

    /// Returns available batches expiring before `date`.
    func fetchIngredientsExpiring(before date: Date) async throws -> [Ingredient]

    /// Updates an existing entry; throws `RepositoryError.notFound` if its ID is missing.
    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws

    /// Removes a pantry batch; throws `RepositoryError.notFound` if its ID is missing.
    func deleteIngredient(id: UUID) async throws
}
