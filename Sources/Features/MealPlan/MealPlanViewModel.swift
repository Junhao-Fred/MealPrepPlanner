//  Created by Mingchen Liang on 2026/10/21.

import Foundation
import Observation

struct MealPlanDay: Identifiable, Equatable {
    let date: Date
    let entries: [MealPlanEntry]

    var id: Date { date }
}

@MainActor
@Observable
final class MealPlanViewModel {
    private(set) var rangeStart: Date
    private(set) var days: [MealPlanDay] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?

    private let useCase: GetMealPlanUseCase
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        repository: any MealPlanningRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        useCase = GetMealPlanUseCase(repository: repository)
        self.calendar = calendar
        self.now = now
        rangeStart = calendar.startOfDay(for: now())
    }

    /// Last included calendar day, for display. Queries exclude midnight of the next day.
    var lastDay: Date {
        calendar.date(byAdding: .day, value: 6, to: rangeStart) ?? rangeStart
    }

    /// Refresh failure keeps the previous list for this range; errors remain visible for retry.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try Task.checkCancellation()
            guard let end = calendar.date(byAdding: .day, value: 7, to: rangeStart), end > rangeStart else {
                throw MealPlanQueryError.invalidDateRange
            }
            let entries = try await useCase.execute(from: rangeStart, to: end, includingPrepared: true)
            try Task.checkCancellation()
            let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.scheduledDate) }
            days = grouped.keys.sorted().map { date in
                MealPlanDay(date: date, entries: grouped[date] ?? [])
            }
            hasLoaded = true
        } catch is CancellationError {
        } catch let error as RepositoryError {
            errorMessage = error == .storeUnavailable
                ? "Meal plan storage is unavailable. Please try again later."
                : "Unable to load your meal plan. Please try again."
        } catch {
            errorMessage = "Unable to load this date range. Please try again."
        }
    }

    /// Clears old results when changing dates, so a failed query cannot show the wrong week's meals.
    func showRange(starting date: Date) async {
        guard !isLoading else { return }
        let start = calendar.startOfDay(for: date)
        if start != rangeStart {
            rangeStart = start
            days = []
            hasLoaded = false
        }
        await load()
    }

    func showToday() async {
        await showRange(starting: now())
    }
}
