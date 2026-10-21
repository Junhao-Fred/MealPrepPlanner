//  Created by Mingchen Liang on 2026/10/20.

import Foundation

enum MealPlanQueryError: Error, Equatable, Sendable {
    case invalidDateRange
}

/// Reads scheduled meals for a date range without changing recipes or plans.
struct GetMealPlanUseCase: Sendable {
    private let repository: any MealPlanningRepository

    init(repository: any MealPlanningRepository) {
        self.repository = repository
    }

    /// Returns plans in `[start, end)`, oldest first, including prepared meals by default.
    /// Pass `false` to include only unfinished plans. Date boundaries are used as supplied;
    /// callers querying whole days should calculate local midnights with their calendar.
    /// Equal or reversed boundaries throw before accessing storage. An empty result means
    /// no matching plans; repository failures propagate unchanged to the caller.
    func execute(
        from start: Date,
        to end: Date,
        includingPrepared includePrepared: Bool = true
    ) async throws -> [MealPlanEntry] {
        guard start < end else {
            throw MealPlanQueryError.invalidDateRange
        }

        return try await repository.fetchMealPlanEntries(
            from: start,
            to: end,
            includingPrepared: includePrepared
        )
    }
}
