//  Created by Junhao Huang on 2026/10/22.

import Foundation

/// Removes a planned meal, whether or not it was prepared.
struct DeleteMealPlanEntryUseCase: Sendable {
    private let repository: any MealPlanningRepository

    init(repository: any MealPlanningRepository) {
        self.repository = repository
    }

    /// An entry that is already gone reports `entryNotFound`, matching meal preparation.
    func execute(entryID: UUID) async throws {
        do {
            try await repository.deleteMealPlanEntry(id: entryID)
        } catch RepositoryError.notFound {
            throw MealPreparationError.entryNotFound
        }
    }
}
