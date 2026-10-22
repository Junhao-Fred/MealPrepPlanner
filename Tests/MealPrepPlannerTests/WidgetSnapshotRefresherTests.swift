//  Created by Junhao Huang on 2026/10/19.

import Foundation
import os
import Testing
@testable import MealPrepPlanner

struct WidgetSnapshotRefresherTests {
    private func entry(_ name: String, at date: Date, prepared: Bool = false) -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(name: name, ingredients: [MealIngredient(name: "Rice", quantity: 100, unit: "g")]),
            scheduledDate: date,
            mealType: .dinner,
            isPrepared: prepared
        )
    }

    private func makeRefresher(
        _ repository: any MealPlanningRepository,
        _ store: WidgetSnapshotStore,
        reloads: OSAllocatedUnfairLock<Int> = OSAllocatedUnfairLock(initialState: 0)
    ) -> WidgetSnapshotRefresher {
        WidgetSnapshotRefresher(
            repository: repository,
            store: store,
            calendar: WidgetFixtures.calendar,
            now: { WidgetFixtures.now },
            reloadTimelines: { reloads.withLock { $0 += 1 } }
        )
    }

    @Test("A refresh saves upcoming unfinished meals and dated stock, then reloads the widget once")
    func refreshBuildsSnapshot() async throws {
        let temporary = TemporaryDefaults()
        defer { temporary.remove() }
        let dinner = entry("Pasta", at: WidgetFixtures.date(day: 0, hour: 19))
        let milk = Ingredient(name: "Milk", quantity: 1, unit: "L", expiryDate: WidgetFixtures.date(day: 1))
        let repository = InMemoryMealRepository(
            entries: [
                dinner,
                entry("Breakfast", at: WidgetFixtures.date(day: 0, hour: 8)),
                entry("Done", at: WidgetFixtures.date(day: 0, hour: 20), prepared: true)
            ],
            ingredients: [
                milk,
                Ingredient(name: "Rice", quantity: 1, unit: "kg"),
                Ingredient(name: "Old yoghurt", quantity: 1, unit: "cup", expiryDate: WidgetFixtures.date(day: -1))
            ],
            now: { WidgetFixtures.now }
        )
        let reloads = OSAllocatedUnfairLock(initialState: 0)

        let saved = await makeRefresher(repository, temporary.store, reloads: reloads).refresh()

        let snapshot = try #require(temporary.store.load())
        #expect(saved)
        #expect(snapshot.meals.map(\.id) == [dinner.id])
        #expect(snapshot.meals.first?.mealType == "Dinner")
        #expect(snapshot.ingredients.map(\.id) == [milk.id])
        #expect(reloads.withLock { $0 } == 1)
    }

    @Test("Refreshing unchanged data neither saves nor reloads the widget again")
    func unchangedContentSkipsReload() async {
        let temporary = TemporaryDefaults()
        defer { temporary.remove() }
        let repository = InMemoryMealRepository(
            entries: [entry("Soup", at: WidgetFixtures.date(day: 0, hour: 18))],
            now: { WidgetFixtures.now }
        )
        let reloads = OSAllocatedUnfairLock(initialState: 0)
        let refresher = makeRefresher(repository, temporary.store, reloads: reloads)

        #expect(await refresher.refresh())
        #expect(await refresher.refresh() == false)
        #expect(reloads.withLock { $0 } == 1)
    }

    @Test("A failed read keeps the last snapshot and does not reload the widget")
    func readFailureKeepsLastSnapshot() async throws {
        let temporary = TemporaryDefaults()
        defer { temporary.remove() }
        let repository = InMemoryMealRepository(
            entries: [entry("Soup", at: WidgetFixtures.date(day: 0, hour: 18))],
            now: { WidgetFixtures.now }
        )
        let reloads = OSAllocatedUnfairLock(initialState: 0)
        let refresher = makeRefresher(repository, temporary.store, reloads: reloads)
        #expect(await refresher.refresh())
        let before = temporary.store.load()

        await repository.fail(.read, with: .readFailed)

        #expect(await refresher.refresh() == false)
        #expect(temporary.store.load() == before)
        #expect(reloads.withLock { $0 } == 1)
    }

    @Test("T13: a slow older refresh never overwrites the snapshot from a newer one")
    func staleRefreshIsDropped() async throws {
        let temporary = TemporaryDefaults()
        defer { temporary.remove() }
        let base = InMemoryMealRepository(now: { WidgetFixtures.now })
        let gated = HoldFirstUpcomingReadRepository(base: base)
        let refresher = makeRefresher(gated, temporary.store)
        let added = entry("Curry", at: WidgetFixtures.date(day: 0, hour: 19))

        let older = Task { await refresher.refresh() }
        while !(await gated.isHolding) { await Task.yield() }
        try await base.savePlannedMeal(added)
        let newerSaved = await refresher.refresh()
        await gated.release()
        let olderSaved = await older.value

        #expect(newerSaved)
        #expect(olderSaved == false)
        #expect(temporary.store.load()?.meals.map(\.id) == [added.id])
    }

    @Test("Only successful writes report a change; reads and failed writes do not")
    func refreshingRepositoryReportsWrites() async throws {
        let base = InMemoryMealRepository(now: { WidgetFixtures.now })
        let writes = OSAllocatedUnfairLock(initialState: 0)
        let repository = WidgetRefreshingRepository(wrapping: base) { writes.withLock { $0 += 1 } }
        let rice = Ingredient(name: "Rice", quantity: 1, unit: "kg")

        try await repository.saveIngredient(rice)
        _ = try await repository.fetchAvailableIngredients()
        _ = try await repository.fetchUpcomingMeals()
        #expect(writes.withLock { $0 } == 1)

        await base.fail(.write, with: .writeFailed)
        await #expect(throws: RepositoryError.writeFailed) {
            try await repository.saveIngredient(rice)
        }
        #expect(writes.withLock { $0 } == 1)
    }

    @Test("Writes through the app dependencies bump the change version and reach the widget snapshot")
    @MainActor
    func dependenciesConnectWritesToScreensAndWidget() async throws {
        let temporary = TemporaryDefaults()
        defer { temporary.remove() }
        let store = temporary.store
        let dependencies = AppDependencies(repository: InMemoryMealRepository(now: { WidgetFixtures.now })) {
            WidgetSnapshotRefresher(
                repository: $0,
                store: store,
                calendar: WidgetFixtures.calendar,
                now: { WidgetFixtures.now },
                reloadTimelines: {}
            )
        }
        let milk = Ingredient(name: "Milk", quantity: 1, unit: "L", expiryDate: WidgetFixtures.date(day: 1))

        try await dependencies.repository.saveIngredient(milk)
        #expect(dependencies.changes.version == 1)

        // The write starts the widget refresh in the background; give it up to a second to land.
        for _ in 0..<100 where store.load() == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.load()?.ingredients.map(\.id) == [milk.id])
    }
}

/// Holds the first `fetchUpcomingMeals()` until `release()`, so a test can finish an older refresh after a newer one.
private actor HoldFirstUpcomingReadRepository: MealPlanningRepository {
    private let base: InMemoryMealRepository
    private var shouldHold = true
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var isHolding = false

    init(base: InMemoryMealRepository) {
        self.base = base
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }

    func fetchUpcomingMeals() async throws -> [MealPlanEntry] {
        let entries = try await base.fetchUpcomingMeals()
        if shouldHold {
            shouldHold = false
            isHolding = true
            await withCheckedContinuation { waiter = $0 }
            isHolding = false
        }
        return entries
    }

    func saveMeal(_ meal: Meal) async throws { try await base.saveMeal(meal) }
    func saveIngredient(_ ingredient: Ingredient) async throws { try await base.saveIngredient(ingredient) }
    func saveMealPlanEntry(_ entry: MealPlanEntry) async throws { try await base.saveMealPlanEntry(entry) }
    func savePlannedMeal(_ entry: MealPlanEntry) async throws { try await base.savePlannedMeal(entry) }
    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws { try await base.updateMealPlanEntry(entry) }
    func deleteIngredient(id: UUID) async throws { try await base.deleteIngredient(id: id) }

    func fetchMealPlanEntries(
        from start: Date,
        to end: Date,
        includingPrepared includePrepared: Bool
    ) async throws -> [MealPlanEntry] {
        try await base.fetchMealPlanEntries(from: start, to: end, includingPrepared: includePrepared)
    }

    func fetchAvailableIngredients() async throws -> [Ingredient] {
        try await base.fetchAvailableIngredients()
    }

    func fetchIngredientsExpiring(before date: Date) async throws -> [Ingredient] {
        try await base.fetchIngredientsExpiring(before: date)
    }
}
