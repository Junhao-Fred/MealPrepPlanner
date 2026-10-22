//  Created by Mingchen Liang on 2026/10/21.

import Foundation
import Observation

@MainActor
@Observable
final class ShoppingListViewModel {
    private(set) var snapshot: ShoppingListSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// The item being added to the pantry, so its button can show progress.
    private(set) var addingItemID: ShoppingListItem.ID?

    @ObservationIgnored private var refreshRequested = false

    private let useCase: GenerateShoppingListUseCase
    private let saveUseCase: SavePantryIngredientUseCase

    init(
        repository: any MealPlanningRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        useCase = GenerateShoppingListUseCase(repository: repository, calendar: calendar, now: now)
        saveUseCase = SavePantryIngredientUseCase(repository: repository)
    }

    /// Records a bought item as a new undated pantry batch, which removes it from the list.
    func addToPantry(_ item: ShoppingListItem) async -> Bool {
        guard addingItemID == nil, !isLoading else { return false }
        addingItemID = item.id
        errorMessage = nil
        defer { addingItemID = nil }
        do {
            try await saveUseCase.execute(Ingredient(name: item.name, quantity: item.quantity, unit: item.unit))
        } catch {
            errorMessage = "Unable to add \(item.name) to your pantry. Please try again."
            return false
        }
        await load()
        return true
    }

    /// Recalculates from storage and retains the last successful snapshot on failure.
    func load() async {
        guard !isLoading else { return }
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
        errorMessage = nil
        do {
            try Task.checkCancellation()
            let result = try await useCase.executeSnapshot()
            try Task.checkCancellation()
            snapshot = result
        } catch is CancellationError {
        } catch let error as ShoppingListError {
            switch error {
            case .invalidDateRange:
                errorMessage = "Unable to calculate the shopping date range. Please try again."
            case .invalidIngredient:
                errorMessage = "Check ingredient names, units and quantities in your meal plans and pantry, then refresh."
            case .quantityOverflow:
                errorMessage = "The combined quantities are too large. Check your meal plans and pantry, then refresh."
            }
        } catch let error as RepositoryError {
            errorMessage = error == .storeUnavailable
                ? "Shopping data is unavailable. Please try again later."
                : "Unable to load your shopping list. Please try again."
        } catch {
            errorMessage = "Unable to calculate your shopping list. Please try again."
        }
    }

    /// Coalesces notifications while a read or write is in flight.
    func refreshAfterDataChange() async {
        refreshRequested = true
        guard !isLoading else { return }
        await load()
    }

    private func schedulePendingRefresh() {
        guard refreshRequested, !isLoading else { return }
        refreshRequested = false
        // An independent task also survives cancellation of the previous view load.
        Task { await refreshAfterDataChange() }
    }
}
