import Foundation

enum MealPreparationError: Error, Equatable {
    case entryNotFound
    /// The meal's prepared state was saved, but pantry stock could not be adjusted.
    case pantryNotUpdated
}

struct MarkMealPreparedUseCase: Sendable {
    struct Result: Equatable, Sendable {
        let entry: MealPlanEntry
        let shortfalls: [AdjustPantryForMealUseCase.Shortfall]
    }

    let repository: any MealPlanningRepository
    var calendar: Calendar = .current
    var now: @Sendable () -> Date = { Date() }

    private var pantry: AdjustPantryForMealUseCase {
        AdjustPantryForMealUseCase(repository: repository, calendar: calendar, now: now)
    }

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
        try await prepare(id: id).entry
    }

    /// Marks the meal prepared, then deducts its recipe from the pantry. Preparing twice changes nothing.
    func prepare(id: UUID) async throws -> Result {
        var entry = try await load(id: id)
        guard !entry.isPrepared else { return Result(entry: entry, shortfalls: []) }
        entry.isPrepared = true
        try await save(entry)
        do {
            return Result(entry: entry, shortfalls: try await pantry.deduct(entry.meal))
        } catch {
            throw MealPreparationError.pantryNotUpdated
        }
    }

    /// Marks the meal as not prepared; with `returningIngredients`, adds its recipe back to the pantry.
    func undo(id: UUID, returningIngredients: Bool) async throws -> MealPlanEntry {
        var entry = try await load(id: id)
        guard entry.isPrepared else { return entry }
        entry.isPrepared = false
        try await save(entry)
        guard returningIngredients else { return entry }
        do {
            try await pantry.restore(entry.meal)
        } catch {
            throw MealPreparationError.pantryNotUpdated
        }
        return entry
    }

    private func save(_ entry: MealPlanEntry) async throws {
        do {
            try await repository.updateMealPlanEntry(entry)
        } catch RepositoryError.notFound {
            throw MealPreparationError.entryNotFound
        }
    }
}
