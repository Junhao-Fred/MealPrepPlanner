//  Created by Mingchen Liang on 2026/10/20.

import Foundation

/// Loads positive pantry batches, including expired stock for the UI to identify.
struct LoadPantryUseCase: Sendable {
    private let repository: any MealPlanningRepository

    init(repository: any MealPlanningRepository) {
        self.repository = repository
    }

    /// Keeps separate batches and orders them by name, then ID for stable display.
    /// Repository failures propagate unchanged to the caller.
    func execute() async throws -> [Ingredient] {
        try await repository.fetchAvailableIngredients().sorted {
            ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString)
        }
    }
}
