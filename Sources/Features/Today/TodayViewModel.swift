import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {
    private(set) var snapshot: TodayOverview?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let useCase: LoadTodayOverviewUseCase
    private var loadVersion = 0

    init(useCase: LoadTodayOverviewUseCase) {
        self.useCase = useCase
    }

    func load() async {
        loadVersion += 1
        let version = loadVersion
        isLoading = true
        errorMessage = nil
        defer {
            if version == loadVersion { isLoading = false }
        }
        do {
            let result = try await useCase.execute()
            try Task.checkCancellation()
            guard version == loadVersion else { return }
            snapshot = result
        } catch is CancellationError {
        } catch {
            if version == loadVersion {
                errorMessage = "Unable to load your meals. Please try again."
            }
        }
    }
}
