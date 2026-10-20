import Foundation

enum MealPreparationError: Error, Equatable {
    case entryNotFound
}

struct MarkMealPreparedUseCase: Sendable {
    let repository: any MealPlanningRepository

    func load(id: UUID) async throws -> MealPlanEntry {
        let entries = try await repository.fetchMealPlanEntries(
            from: .distantPast, to: .distantFuture, includingPrepared: true
        )
        guard let entry = entries.first(where: { $0.id == id }) else {
            throw MealPreparationError.entryNotFound
        }
        return entry
    }

    func execute(id: UUID) async throws -> MealPlanEntry {
        var entry = try await load(id: id)
        guard !entry.isPrepared else { return entry }
        entry.isPrepared = true
        do {
            try await repository.updateMealPlanEntry(entry)
        } catch RepositoryError.notFound {
            throw MealPreparationError.entryNotFound
        }
        return entry
    }
}
