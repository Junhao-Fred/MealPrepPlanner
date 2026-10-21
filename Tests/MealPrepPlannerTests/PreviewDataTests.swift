//  Created by Junhao Huang on 2026/10/19.

import Foundation
import Testing
@testable import MealPrepPlanner

struct PreviewDataTests {
    private let now = WidgetFixtures.now
    private let calendar = WidgetFixtures.calendar

    private var repository: InMemoryMealRepository {
        .preview(now: now, calendar: calendar)
    }

    @Test("Preview meals include prepared, upcoming and later-day meals")
    func mealsCoverEveryState() async throws {
        let today = try await repository.fetchMealPlanEntries(
            from: WidgetFixtures.date(day: 0),
            to: WidgetFixtures.date(day: 1),
            includingPrepared: true
        )
        let upcoming = try await repository.fetchUpcomingMeals()

        #expect(today.contains { $0.isPrepared })
        #expect(today.contains { !$0.isPrepared && $0.scheduledDate > now })
        #expect(upcoming.first?.meal.name == "Chicken Rice Bowl")
        #expect(upcoming.contains { $0.scheduledDate >= WidgetFixtures.date(day: 1) })
    }

    @Test("Preview stock includes items expiring today, within three days, expired and undated")
    func stockCoversEveryExpiryState() async throws {
        let stock = try await repository.fetchAvailableIngredients()
        let today = calendar.startOfDay(for: now)
        let days = stock.compactMap { ingredient in
            ingredient.expiryDate.map { calendar.dateComponents([.day], from: today, to: $0).day! }
        }

        #expect(days.contains(0))
        #expect(days.contains { $0 > 0 && $0 < 3 })
        #expect(days.contains { $0 >= 3 })
        #expect(days.contains { $0 < 0 })
        #expect(stock.contains { $0.expiryDate == nil })
    }

    @Test("Preview tomatoes match the demo: 300 g + 250 g needed, 200 g in stock")
    func tomatoesMatchTheDemo() async throws {
        let needed = try await repository
            .fetchMealPlanEntries(from: WidgetFixtures.date(day: 0), to: WidgetFixtures.date(day: 7), includingPrepared: false)
            .flatMap(\.meal.ingredients)
            .filter { $0.name == "Tomato" && $0.unit == "g" }
            .map(\.quantity)
        let stock = try await repository.fetchAvailableIngredients()
            .filter { $0.name == "Tomato" && $0.unit == "g" }
            .reduce(Decimal(0)) { $0 + $1.quantity }

        #expect(needed == [300, 250])
        #expect(stock == 200)
    }

    @Test("Preview dependencies write the widget snapshot to their own suite, not the App Group")
    @MainActor
    func previewDependenciesStayOutOfTheAppGroup() async throws {
        let previewStore = WidgetSnapshotStore(suiteName: AppDependencies.previewSnapshotSuite)
        UserDefaults().removePersistentDomain(forName: AppDependencies.previewSnapshotSuite)
        defer { UserDefaults().removePersistentDomain(forName: AppDependencies.previewSnapshotSuite) }
        let dependencies = AppDependencies.preview(repository: InMemoryMealRepository(now: { WidgetFixtures.now }))
        // Preview dependencies use the real clock, so the expiry must be relative to today.
        let milk = Ingredient(name: "Milk", quantity: 1, unit: "L", expiryDate: Date().addingTimeInterval(2 * 86_400))

        try await dependencies.repository.saveIngredient(milk)
        for _ in 0..<300 where previewStore.load()?.ingredients.map(\.id) != [milk.id] {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(previewStore.load()?.ingredients.map(\.id) == [milk.id])
        #expect(WidgetSnapshotStore().load()?.ingredients.contains { $0.id == milk.id } != true)
    }
}
