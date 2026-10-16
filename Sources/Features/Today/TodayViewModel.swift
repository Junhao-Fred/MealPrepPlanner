import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {
    private(set) var snapshot: TodayMealsSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let useCase: TodayMealsUseCase

    init(useCase: TodayMealsUseCase) {
        self.useCase = useCase
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await useCase.execute()
            try Task.checkCancellation()
            snapshot = result
        } catch is CancellationError {
        } catch {
            errorMessage = "Unable to load your meals. Please try again."
        }
    }
}
