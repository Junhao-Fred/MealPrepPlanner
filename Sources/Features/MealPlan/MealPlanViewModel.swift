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
    private(set) var isSaving = false
    private(set) var deletingEntryID: UUID?
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var refreshRequested = false

    private let useCase: GetMealPlanUseCase
    private let saveUseCase: PlanMealUseCase
    private let deleteUseCase: DeleteMealPlanEntryUseCase
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        repository: any MealPlanningRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        useCase = GetMealPlanUseCase(repository: repository)
        saveUseCase = PlanMealUseCase(repository: repository, calendar: calendar, now: now)
        deleteUseCase = DeleteMealPlanEntryUseCase(repository: repository)
        self.calendar = calendar
        self.now = now
        rangeStart = calendar.startOfDay(for: now())
    }

    var isBusy: Bool { isLoading || isSaving || deletingEntryID != nil }

    func makeDraft() -> MealEntryDraft {
        MealEntryDraft(scheduledDate: max(rangeStart, now().addingTimeInterval(3_600)))
    }

    func clearError() {
        errorMessage = nil
    }

    /// Last included calendar day, for display. Queries exclude midnight of the next day.
    var lastDay: Date {
        calendar.date(byAdding: .day, value: 6, to: rangeStart) ?? rangeStart
    }

    /// Refresh failure keeps the previous list for this range; errors remain visible for retry.
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
        errorMessage = nil
        do {
            try Task.checkCancellation()
            let result = try await fetchDays()
            try Task.checkCancellation()
            days = result
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
        guard !isBusy else { return }
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

    /// True means the write succeeded. A later refresh failure must be retried as a read.
    func save(_ entry: MealPlanEntry) async -> Bool {
        guard !isBusy else { return false }
        isSaving = true
        errorMessage = nil
        defer {
            isSaving = false
            schedulePendingRefresh()
        }

        do {
            try Task.checkCancellation()
            try await saveUseCase.execute(entry)
        } catch is CancellationError {
            return false
        } catch let error as MealPlanningValidationError {
            switch error {
            case .emptyMealName: errorMessage = "Enter a meal name."
            case .emptyIngredients: errorMessage = "Add at least one ingredient."
            case .invalidIngredient: errorMessage = "Each ingredient needs a name, a positive quantity and a unit."
            case .scheduledInThePast: errorMessage = "Choose today or a later date."
            }
            return false
        } catch {
            errorMessage = "Unable to save your meal. Please try again."
            return false
        }

        // Make plans outside the currently displayed week visible after saving.
        let end = calendar.date(byAdding: .day, value: 7, to: rangeStart) ?? rangeStart
        if entry.scheduledDate < rangeStart || entry.scheduledDate >= end {
            rangeStart = calendar.startOfDay(for: entry.scheduledDate)
            days = []
            hasLoaded = false
        }
        do {
            days = try await fetchDays()
            hasLoaded = true
        } catch {
            errorMessage = "Meal saved. Unable to refresh the list. Refresh to try again."
        }
        return true
    }

    /// Removes the entry from storage; the list drops it right away so a failed refresh cannot bring it back.
    func deleteEntry(id: UUID) async -> Bool {
        guard !isBusy else { return false }
        deletingEntryID = id
        errorMessage = nil
        defer {
            deletingEntryID = nil
            schedulePendingRefresh()
        }

        do {
            try Task.checkCancellation()
            try await deleteUseCase.execute(entryID: id)
        } catch is CancellationError {
            return false
        } catch MealPreparationError.entryNotFound {
            errorMessage = "This meal is no longer in your plan. Refresh to see the latest."
            return false
        } catch {
            errorMessage = "Unable to delete your meal. Please try again."
            return false
        }

        days = days.compactMap { day in
            let entries = day.entries.filter { $0.id != id }
            return entries.isEmpty ? nil : MealPlanDay(date: day.date, entries: entries)
        }
        do {
            days = try await fetchDays()
        } catch {
            errorMessage = "Meal deleted. Unable to refresh the list. Refresh to try again."
        }
        return true
    }

    private func fetchDays() async throws -> [MealPlanDay] {
        guard let end = calendar.date(byAdding: .day, value: 7, to: rangeStart), end > rangeStart else {
            throw MealPlanQueryError.invalidDateRange
        }
        let entries = try await useCase.execute(from: rangeStart, to: end, includingPrepared: true)
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.scheduledDate) }
        return grouped.keys.sorted().map { date in
            MealPlanDay(date: date, entries: grouped[date] ?? [])
        }
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
