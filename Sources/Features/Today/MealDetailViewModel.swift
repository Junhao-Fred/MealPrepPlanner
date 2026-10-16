import Foundation
import Observation

@MainActor
@Observable
final class MealDetailViewModel {
    private(set) var entry: MealPlanEntry?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private let id: UUID
    private let useCase: MealDetailsUseCase

    init(id: UUID, useCase: MealDetailsUseCase) {
        self.id = id
        self.useCase = useCase
    }

    func load() async {
        guard !isLoading && !isSaving else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await useCase.fetch(id: id)
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
        defer { isSaving = false }
        do {
            self.entry = try await useCase.markPrepared(id: id)
            return true
        } catch {
            errorMessage = "Unable to mark this meal as prepared. Please try again."
            return false
        }
    }
}
