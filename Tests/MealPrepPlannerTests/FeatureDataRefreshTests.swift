//  Created by Mingchen Liang on 2026/10/21.

import Foundation
import Testing
@testable import MealPrepPlanner

@MainActor
@Suite("Shared feature data refresh")
struct FeatureDataRefreshTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
    }

    private func entry() -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(name: "Rice bowl", ingredients: [MealIngredient(name: "Rice", quantity: 100, unit: "g")]),
            scheduledDate: now.addingTimeInterval(3_600), mealType: .lunch
        )
    }

    @Test("Plans, stock changes and prepared meals refresh all consumers of the shared repository")
    func sharedWrites() async throws {
        let base = InMemoryMealRepository()
        let changes = DataChangeTracker()
        let repository = WidgetRefreshingRepository(wrapping: base) { await changes.recordChange() }
        let date = now
        let plan = MealPlanViewModel(repository: repository, calendar: calendar, now: { date })
        let pantry = PantryViewModel(repository: repository)
        let shopping = ShoppingListViewModel(repository: repository, calendar: calendar, now: { date })
        let today = TodayViewModel(useCase: LoadTodayOverviewUseCase(repository: repository, calendar: calendar, now: { date }))

        // Mirrors the views reacting to the shared version, without invoking WidgetKit.
        func refreshViews() async {
            await plan.refreshAfterDataChange()
            await pantry.refreshAfterDataChange()
            await shopping.refreshAfterDataChange()
            await today.load()
        }
        await refreshViews()
        #expect(changes.version == 0)
        #expect(shopping.snapshot?.plannedMealCount == 0)

        let meal = entry()
        let savedMeal = await plan.save(meal)
        #expect(savedMeal)
        #expect(changes.version == 1)
        await refreshViews()
        #expect(today.snapshot?.nextMeal?.id == meal.id)
        #expect(plan.days.first?.entries.first?.id == meal.id)
        #expect(shopping.snapshot?.items.first?.quantity == 100)

        let rice = Ingredient(name: "Rice", quantity: 40, unit: "g", expiryDate: date)
        let savedRice = await pantry.save(rice)
        #expect(savedRice)
        #expect(changes.version == 2)
        await refreshViews()
        #expect(shopping.snapshot?.items.first?.quantity == 60)
        #expect(today.snapshot?.expiringIngredients.first?.quantity == 40)

        let usedRice = await pantry.useIngredient(id: rice.id, quantity: 10)
        #expect(usedRice)
        #expect(changes.version == 3)
        await refreshViews()
        #expect(pantry.ingredients.first?.quantity == 30)
        #expect(shopping.snapshot?.items.first?.quantity == 70)
        #expect(today.snapshot?.expiringIngredients.first?.quantity == 30)

        _ = try await MarkMealPreparedUseCase(repository: repository).execute(id: meal.id)
        #expect(changes.version == 4)
        await refreshViews()
        #expect(plan.days.first?.entries.first?.isPrepared == true)
        #expect(today.snapshot?.meals.isEmpty == true)
        #expect(shopping.snapshot?.plannedMealCount == 0)
        #expect(shopping.snapshot?.items.isEmpty == true)
        #expect(pantry.ingredients.first?.quantity == 30)
        #expect(await base.writeCount == 4)

        await base.fail(.write, with: .writeFailed)
        let failedSave = await pantry.save(Ingredient(name: "Beans", quantity: 1, unit: "can"))
        #expect(!failedSave)
        #expect(changes.version == 4)
        #expect(await base.writeCount == 4)
    }

    enum Feature: CaseIterable, Sendable { case plan, pantry, shopping }

    @Test("Changes during loading are coalesced into a fresh read", arguments: Feature.allCases)
    func changesDuringLoad(feature: Feature) async throws {
        var meal = entry()
        var rice = Ingredient(name: "Rice", quantity: 20, unit: "g")
        let base = InMemoryMealRepository(entries: [meal], ingredients: [rice])
        let gate = ReadGate()
        let repository = PausingFeatureRepository(base: base, gate: gate, pausePantry: feature == .pantry)
        let date = now
        let plan = MealPlanViewModel(repository: repository, calendar: calendar, now: { date })
        let pantry = PantryViewModel(repository: repository)
        let shopping = ShoppingListViewModel(repository: repository, calendar: calendar, now: { date })
        let refresh: @MainActor () async -> Void = {
            switch feature {
            case .plan: await plan.refreshAfterDataChange()
            case .pantry: await pantry.refreshAfterDataChange()
            case .shopping: await shopping.refreshAfterDataChange()
            }
        }
        let initial = Task { await refresh() }
        await gate.waitUntilPaused()

        // The first read has captured old data. Notifications arrive before it finishes.
        meal.isPrepared = true
        rice.quantity = 50
        try await base.updateMealPlanEntry(meal)
        try await base.saveIngredient(rice)
        await refresh()
        await refresh()
        await gate.release()
        await initial.value

        switch feature {
        case .plan:
            #expect(plan.days.first?.entries.first?.isPrepared == true)
            #expect(!plan.isBusy)
        case .pantry:
            #expect(pantry.ingredients.first?.quantity == 50)
            #expect(!pantry.isBusy)
        case .shopping:
            #expect(shopping.snapshot?.plannedMealCount == 0)
            #expect(shopping.snapshot?.items.isEmpty == true)
            #expect(!shopping.isLoading)
        }
        #expect(await gate.readCount == 2)
    }
}

/// Suspends exactly one read after its snapshot is captured, without timing-based sleeps.
private actor ReadGate {
    private var paused = false
    private var started: CheckedContinuation<Void, Never>?
    private var suspended: CheckedContinuation<Void, Never>?
    private(set) var readCount = 0

    func pauseFirstRead() async {
        readCount += 1
        guard !paused else { return }
        paused = true
        await withCheckedContinuation { continuation in
            suspended = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilPaused() async {
        guard !paused else { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        suspended?.resume()
        suspended = nil
    }
}

private struct PausingFeatureRepository: MealPlanningRepository {
    let base: InMemoryMealRepository
    let gate: ReadGate
    let pausePantry: Bool

    func saveMeal(_ meal: Meal) async throws { try await base.saveMeal(meal) }
    func saveIngredient(_ ingredient: Ingredient) async throws { try await base.saveIngredient(ingredient) }
    func saveMealPlanEntry(_ entry: MealPlanEntry) async throws { try await base.saveMealPlanEntry(entry) }
    func savePlannedMeal(_ entry: MealPlanEntry) async throws { try await base.savePlannedMeal(entry) }
    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws { try await base.updateMealPlanEntry(entry) }
    func fetchUpcomingMeals() async throws -> [MealPlanEntry] { try await base.fetchUpcomingMeals() }
    func fetchIngredientsExpiring(before date: Date) async throws -> [Ingredient] {
        try await base.fetchIngredientsExpiring(before: date)
    }
    func fetchAvailableIngredients() async throws -> [Ingredient] {
        let result = try await base.fetchAvailableIngredients()
        if pausePantry { await gate.pauseFirstRead() }
        return result
    }
    func fetchMealPlanEntries(from start: Date, to end: Date, includingPrepared includePrepared: Bool) async throws -> [MealPlanEntry] {
        let result = try await base.fetchMealPlanEntries(from: start, to: end, includingPrepared: includePrepared)
        if !pausePantry { await gate.pauseFirstRead() }
        return result
    }
}
