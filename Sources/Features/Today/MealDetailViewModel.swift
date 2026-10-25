import Foundation
import Observation

@MainActor
@Observable
final class MealDetailViewModel {
    private(set) var entry: MealPlanEntry?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    /// Information about a successful change, such as stock the pantry could not cover.
    private(set) var notice: String?
    private let id: UUID
    private let useCase: MarkMealPreparedUseCase
    private let deleteUseCase: DeleteMealPlanEntryUseCase?

    init(id: UUID, useCase: MarkMealPreparedUseCase, deleteUseCase: DeleteMealPlanEntryUseCase? = nil) {
        self.id = id
        self.useCase = useCase
        self.deleteUseCase = deleteUseCase
    }

    var canDelete: Bool { deleteUseCase != nil }

    func load() async {
        guard !isLoading && !isSaving else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await useCase.load(id: id)
            try Task.checkCancellation()
            entry = result
        } catch is CancellationError {
        } catch {
            errorMessage = "Unable to load this meal. Please try again."
        }
    }

    func markPrepared() async -> Bool {
        guard let entry, !entry.isPrepared, !isSaving, !isLoading else { return false }
        isSaving = true
        errorMessage = nil
        notice = nil
        defer { isSaving = false }
        do {
            let result = try await useCase.prepare(id: id)
            self.entry = result.entry
            notice = Self.shortfallNotice(result.shortfalls)
            return true
        } catch MealPreparationError.pantryNotUpdated {
            self.entry?.isPrepared = true
            errorMessage = "Meal marked as prepared, but the pantry could not be updated. Check your stock."
            return true
        } catch {
            errorMessage = "Unable to mark this meal as prepared. Please try again."
            return false
        }
    }

    func undoPrepared(returningIngredients: Bool) async -> Bool {
        guard let entry, entry.isPrepared, !isSaving, !isLoading else { return false }
        isSaving = true
        errorMessage = nil
        notice = nil
        defer { isSaving = false }
        do {
            self.entry = try await useCase.undo(id: id, returningIngredients: returningIngredients)
            notice = returningIngredients ? "Ingredients were added back to your pantry." : nil
            return true
        } catch MealPreparationError.pantryNotUpdated {
            self.entry?.isPrepared = false
            errorMessage = "Meal marked as not prepared, but the ingredients could not be added back. Check your stock."
            return true
        } catch {
            errorMessage = "Unable to undo this meal. Please try again."
            return false
        }
    }

    func delete() async -> Bool {
        guard let deleteUseCase, entry != nil, !isSaving, !isLoading else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await deleteUseCase.execute(entryID: id)
            return true
        } catch {
            errorMessage = "Unable to delete this meal. Please try again."
            return false
        }
    }

    private static func shortfallNotice(_ shortfalls: [AdjustPantryForMealUseCase.Shortfall]) -> String? {
        guard !shortfalls.isEmpty else { return nil }
        let items = shortfalls.map { "\($0.quantity.formatted()) \($0.unit) \($0.name)" }
        return "Your pantry was short of \(items.formatted(.list(type: .and))). The rest was taken from stock."
    }
}
