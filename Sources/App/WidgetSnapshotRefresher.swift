//  Created by Junhao Huang on 2026/10/19.

import Foundation
import OSLog
import WidgetKit

/// Rebuilds the widget snapshot from the repository and reloads the widget only when its content changed.
/// Refresh failures are logged and never fail the write that triggered them.
actor WidgetSnapshotRefresher {
    /// Keeps the snapshot small while still covering several days without the app running.
    static let mealLimit = 30
    static let ingredientLimit = 30

    private static let logger = Logger(subsystem: "com.manbo.MealPrepPlanner", category: "WidgetSnapshot")

    private let repository: any MealPlanningRepository
    private let store: WidgetSnapshotStore
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let reloadTimelines: @Sendable () -> Void
    private var generation = 0

    init(
        repository: any MealPlanningRepository,
        store: WidgetSnapshotStore = WidgetSnapshotStore(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        reloadTimelines: @escaping @Sendable () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: AppGroupConfiguration.widgetKind)
        }
    ) {
        self.repository = repository
        self.store = store
        self.calendar = calendar
        self.now = now
        self.reloadTimelines = reloadTimelines
    }

    /// Returns true when a new snapshot was saved.
    /// A refresh that finishes reading after a newer refresh started is dropped, so stale data never overwrites newer data.
    @discardableResult
    func refresh() async -> Bool {
        generation += 1
        let current = generation
        let snapshot: MealWidgetSnapshot
        do {
            snapshot = try await makeSnapshot()
        } catch {
            Self.logger.error("Reading data for the widget failed: \(String(describing: error), privacy: .public)")
            return false
        }
        guard current == generation else { return false }
        if let saved = store.load(), saved.hasSameContent(as: snapshot) { return false }
        do {
            try store.save(snapshot)
        } catch {
            Self.logger.error("Saving the widget snapshot failed: \(String(describing: error), privacy: .public)")
            return false
        }
        reloadTimelines()
        return true
    }

    private func makeSnapshot() async throws -> MealWidgetSnapshot {
        let date = now()
        let today = calendar.startOfDay(for: date)
        async let upcoming = repository.fetchUpcomingMeals()
        async let available = repository.fetchAvailableIngredients()

        let meals = try await upcoming
            .prefix(Self.mealLimit)
            .map {
                MealWidgetSnapshot.Meal(
                    id: $0.id,
                    name: $0.meal.name,
                    mealType: $0.mealType.displayName,
                    scheduledDate: $0.scheduledDate
                )
            }
        let ingredients = try await available
            .compactMap { ingredient -> MealWidgetSnapshot.ExpiringIngredient? in
                guard let expiry = ingredient.expiryDate,
                      calendar.startOfDay(for: expiry) >= today else { return nil }
                return MealWidgetSnapshot.ExpiringIngredient(
                    id: ingredient.id,
                    name: ingredient.name,
                    expiryDate: expiry
                )
            }
            .sorted { ($0.expiryDate, $0.id.uuidString) < ($1.expiryDate, $1.id.uuidString) }
            .prefix(Self.ingredientLimit)

        return MealWidgetSnapshot(generatedAt: date, meals: Array(meals), ingredients: Array(ingredients))
    }
}
