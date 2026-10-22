//  Created by Junhao Huang on 2026/10/19.

import Foundation
import Observation

/// Composition root. Builds the live repository once and hands it to every screen through the environment:
/// `@Environment(AppDependencies.self) private var dependencies`.
@MainActor @Observable
final class AppDependencies {
    /// Use this for all reads and writes; each successful write refreshes the widget and bumps `changes`.
    let repository: any MealPlanningRepository
    let changes: DataChangeTracker

    @ObservationIgnored private let snapshotRefresher: WidgetSnapshotRefresher
    @ObservationIgnored private let reminderRefresher: ExpiryReminderRefresher?

    /// Pass `reminderScheduler` to schedule expiry notifications; previews and tests leave it out.
    init(
        repository base: any MealPlanningRepository,
        makeSnapshotRefresher: (any MealPlanningRepository) -> WidgetSnapshotRefresher = {
            WidgetSnapshotRefresher(repository: $0)
        },
        reminderScheduler: (any ExpiryReminderScheduling)? = nil
    ) {
        let changes = DataChangeTracker()
        let refresher = makeSnapshotRefresher(base)
        let reminders = reminderScheduler.map { ExpiryReminderRefresher(repository: base, scheduler: $0) }
        self.changes = changes
        self.snapshotRefresher = refresher
        self.reminderRefresher = reminders
        self.repository = WidgetRefreshingRepository(wrapping: base) {
            await changes.recordChange()
            Task { await refresher.refresh() }
            if let reminders { Task { await reminders.refresh() } }
        }
    }

    /// Opens the on-disk Core Data store. Throws when the store cannot be loaded, so the app can offer a retry.
    static func live() async throws -> AppDependencies {
        let persistence = try await PersistenceController.makePersistent()
        return AppDependencies(
            repository: CoreDataMealRepository(container: persistence.container),
            reminderScheduler: NotificationExpiryReminderScheduler()
        )
    }

    func refreshWidgetSnapshot() async {
        await snapshotRefresher.refresh()
    }

    /// Reschedules expiry notifications, for example when the app opens on a new day.
    func refreshExpiryReminders() async {
        await reminderRefresher?.refresh()
    }
}
