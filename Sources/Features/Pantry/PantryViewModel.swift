//  Created by Mingchen Liang on 2026/10/20.

import Foundation
import Observation

@MainActor
@Observable
final class PantryViewModel {
    private(set) var ingredients: [Ingredient] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var usingIngredientID: UUID?
    private(set) var deletingIngredientID: UUID?
    private(set) var errorMessage: String?
    private(set) var needsReload = true

    @ObservationIgnored private var refreshRequested = false

    private let loadUseCase: LoadPantryUseCase
    private let saveUseCase: SavePantryIngredientUseCase
    private let useIngredientUseCase: MarkIngredientUsedUseCase
    private let deleteUseCase: DeletePantryIngredientUseCase

    /// Views use this flag to disable conflicting actions while an operation is suspended.
    var isBusy: Bool { isLoading || isSaving || usingIngredientID != nil || deletingIngredientID != nil }

    /// Supply the same repository used by the rest of the app.
    init(repository: any MealPlanningRepository) {
        loadUseCase = LoadPantryUseCase(repository: repository)
        saveUseCase = SavePantryIngredientUseCase(repository: repository)
        useIngredientUseCase = MarkIngredientUsedUseCase(repository: repository)
        deleteUseCase = DeletePantryIngredientUseCase(repository: repository)
    }

    /// Retains the last list on failure so the user can retry without losing context.
    func load() async {
        guard !isBusy else { return }
        isLoading = true
        defer {
            isLoading = false
            schedulePendingRefresh()
        }

        repeat {
            refreshRequested = false
            await loadSnapshot()
        } while refreshRequested && !Task.isCancelled
    }

    private func loadSnapshot() async {
        needsReload = true
        errorMessage = nil
        do {
            try Task.checkCancellation()
            let result = try await loadUseCase.execute()
            try Task.checkCancellation()
            ingredients = result
            needsReload = false
        } catch is CancellationError {
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Returns true once storage accepts the save, even if the following refresh fails.
    /// A form should dismiss only on true; a failed refresh is retried via load(), not save().
    func save(_ ingredient: Ingredient) async -> Bool {
        guard !isBusy else { return false }
        isSaving = true
        errorMessage = nil
        defer {
            isSaving = false
            schedulePendingRefresh()
        }

        do {
            try Task.checkCancellation()
            try await saveUseCase.execute(ingredient)
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = message(for: error)
            return false
        }

        await refreshAfterWrite(successMessage: "Ingredient saved.")
        return true
    }

    /// Serializes mutations within this ViewModel; repository read/save is not atomic.
    /// All pantry views should share this instance to prevent overlapping stock deductions.
    func useIngredient(id: UUID, quantity: Decimal) async -> Bool {
        guard !isBusy else { return false }
        usingIngredientID = id
        errorMessage = nil
        defer {
            usingIngredientID = nil
            schedulePendingRefresh()
        }

        do {
            try Task.checkCancellation()
            let updated = try await useIngredientUseCase.execute(ingredientID: id, quantity: quantity)
            // Reflect the confirmed deduction even if the subsequent full refresh fails.
            ingredients.removeAll { $0.id == id }
            if updated.isAvailable {
                ingredients.append(updated)
                ingredients.sort { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
            }
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = message(for: error)
            return false
        }

        await refreshAfterWrite(successMessage: "Stock updated.")
        return true
    }

    /// Removes the batch from storage; the list drops it right away so a failed refresh cannot bring it back.
    func deleteIngredient(id: UUID) async -> Bool {
        guard !isBusy else { return false }
        deletingIngredientID = id
        errorMessage = nil
        defer {
            deletingIngredientID = nil
            schedulePendingRefresh()
        }

        do {
            try Task.checkCancellation()
            try await deleteUseCase.execute(ingredientID: id)
            ingredients.removeAll { $0.id == id }
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = message(for: error)
            return false
        }

        await refreshAfterWrite(successMessage: "Ingredient deleted.")
        return true
    }

    func clearError() {
        errorMessage = nil
    }

    private func refreshAfterWrite(successMessage: String) async {
        needsReload = true
        do {
            ingredients = try await loadUseCase.execute()
            needsReload = false
        } catch {
            // Do not report a successful write as failed and invite a duplicate submission.
            errorMessage = "\(successMessage) Unable to refresh the pantry. Refresh the list to try again."
        }
    }

    private func message(for error: any Error) -> String {
        if let pantryError = error as? PantryError {
            switch pantryError {
            case .emptyIngredientName: return "Enter an ingredient name."
            case .emptyUnit: return "Enter a unit."
            case .invalidQuantity: return "Enter a quantity greater than zero."
            case .ingredientNotFound: return "This ingredient is no longer available. Refresh the pantry."
            case .insufficientIngredient: return "The amount exceeds the available stock."
            }
        }
        if let repositoryError = error as? RepositoryError {
            switch repositoryError {
            case .notFound: return "This ingredient could not be found. Refresh the pantry."
            case .readFailed: return "Unable to load your pantry. Please try again."
            case .writeFailed: return "Unable to save your pantry changes. Please try again."
            case .storeUnavailable: return "Pantry storage is unavailable. Please try again later."
            }
        }
        return "Unable to update your pantry. Please try again."
    }

    /// Coalesces notifications while a read or write is in flight.
    func refreshAfterDataChange() async {
        refreshRequested = true
        guard !isBusy else { return }
        await load()
    }

    private func schedulePendingRefresh() {
        guard refreshRequested, !isBusy else { return }
        refreshRequested = false
        // An independent task also survives cancellation of the previous view load.
        Task { await refreshAfterDataChange() }
    }
}
