//  Created by Junhao Huang on 2026/10/22.

import CoreData
import Foundation
import os
import Testing
@testable import MealPrepPlanner

@MainActor
@Suite("Meal plan entry deletion")
struct MealPlanDeleteTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
    }

    // MARK: Use case

    @Test("Deleting removes only the selected entry")
    func deleteRemovesSelectedEntry() async throws {
        let pasta = entry("Pasta", at: today.addingTimeInterval(12 * 3_600))
        let salad = entry("Salad", at: today.addingTimeInterval(18 * 3_600))
        let repository = InMemoryMealRepository(entries: [pasta, salad])

        try await DeleteMealPlanEntryUseCase(repository: repository).execute(entryID: pasta.id)

        let remaining = try await repository.fetchMealPlanEntries(
            from: today, to: today.addingTimeInterval(86_400), includingPrepared: true
        )
        let writeCount = await repository.writeCount
        #expect(remaining == [salad])
        #expect(writeCount == 1)
    }

    @Test("Deleting a missing entry reports entryNotFound without writing")
    func deleteMissingEntry() async {
        let repository = InMemoryMealRepository(entries: [entry("Pasta", at: today)])

        await #expect(throws: MealPreparationError.entryNotFound) {
            try await DeleteMealPlanEntryUseCase(repository: repository).execute(entryID: UUID())
        }
        let writeCount = await repository.writeCount
        #expect(writeCount == 0)
    }

    // MARK: View model

    @Test("Deleting the last meal of a day removes that day and releases busy state")
    func viewModelDelete() async {
        let pasta = entry("Pasta", at: today.addingTimeInterval(12 * 3_600))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let salad = entry("Salad", at: tomorrow.addingTimeInterval(12 * 3_600))
        let model = makeModel(InMemoryMealRepository(entries: [pasta, salad]))
        await model.load()

        let deleted = await model.deleteEntry(id: pasta.id)

        #expect(deleted)
        #expect(model.days == [MealPlanDay(date: tomorrow, entries: [salad])])
        #expect(model.errorMessage == nil)
        #expect(model.deletingEntryID == nil)
        #expect(!model.isBusy)
    }

    @Test("A failed delete returns false and keeps the displayed plan")
    func viewModelDeleteFailure() async {
        let pasta = entry("Pasta", at: today.addingTimeInterval(12 * 3_600))
        let repository = InMemoryMealRepository(entries: [pasta])
        let model = makeModel(repository)
        await model.load()
        await repository.fail(.write, with: .writeFailed)

        let deleted = await model.deleteEntry(id: pasta.id)

        #expect(!deleted)
        #expect(model.days == [MealPlanDay(date: today, entries: [pasta])])
        #expect(model.errorMessage == "Unable to delete your meal. Please try again.")
        #expect(!model.isBusy)
    }

    @Test("A delete followed by a failed refresh still hides the meal")
    func viewModelDeleteThenRefreshFailure() async {
        let pasta = entry("Pasta", at: today.addingTimeInterval(12 * 3_600))
        let repository = InMemoryMealRepository(entries: [pasta])
        let model = makeModel(repository)
        await model.load()
        await repository.fail(.read, with: .readFailed)

        let deleted = await model.deleteEntry(id: pasta.id)

        #expect(deleted)
        #expect(model.days.isEmpty)
        #expect(model.errorMessage?.hasPrefix("Meal deleted.") == true)
    }

    // MARK: Core Data

    @Test("Core Data removes the recipe with its last entry but keeps a recipe still in use")
    func coreDataRemovesUnusedRecipe() async throws {
        let controller = try await PersistenceController.makeInMemory()
        let repository = CoreDataMealRepository(container: controller.container)
        let pasta = entry("Pasta", at: today.addingTimeInterval(12 * 3_600))
        let repeatPasta = MealPlanEntry(meal: pasta.meal, scheduledDate: today.addingTimeInterval(36 * 3_600), mealType: .lunch)
        let salad = entry("Salad", at: today.addingTimeInterval(18 * 3_600))
        try await repository.savePlannedMeal(pasta)
        try await repository.saveMealPlanEntry(repeatPasta)
        try await repository.savePlannedMeal(salad)

        try await repository.deleteMealPlanEntry(id: salad.id)
        try await repository.deleteMealPlanEntry(id: pasta.id)
        #expect(try count(MealEntity.self, in: controller) == 1)

        try await repository.deleteMealPlanEntry(id: repeatPasta.id)
        #expect(try count(MealEntity.self, in: controller) == 0)
        #expect(try count(MealIngredientEntity.self, in: controller) == 0)
        await #expect(throws: RepositoryError.notFound) {
            try await repository.deleteMealPlanEntry(id: pasta.id)
        }
    }

    // MARK: Other features

    @Test("A successful delete reaches the widget refresh; a failed one does not")
    func deleteReportsWrite() async throws {
        let pasta = entry("Pasta", at: today)
        let base = InMemoryMealRepository(entries: [pasta])
        let writes = OSAllocatedUnfairLock(initialState: 0)
        let repository = WidgetRefreshingRepository(wrapping: base) { writes.withLock { $0 += 1 } }

        await #expect(throws: RepositoryError.notFound) {
            try await repository.deleteMealPlanEntry(id: UUID())
        }
        #expect(writes.withLock { $0 } == 0)

        try await repository.deleteMealPlanEntry(id: pasta.id)
        #expect(writes.withLock { $0 } == 1)
    }

    @Test("A deleted meal no longer adds demand to the shopping list")
    func deleteUpdatesShoppingList() async throws {
        let date = today
        let pasta = entry("Pasta", at: date.addingTimeInterval(12 * 3_600))
        let salad = entry("Salad", at: date.addingTimeInterval(18 * 3_600))
        let repository = InMemoryMealRepository(entries: [pasta, salad], now: { date })
        let shopping = GenerateShoppingListUseCase(repository: repository, calendar: calendar, now: { date })

        let before = try await shopping.execute()
        try await DeleteMealPlanEntryUseCase(repository: repository).execute(entryID: pasta.id)
        let after = try await shopping.execute()

        #expect(before.map(\.quantity) == [400])
        #expect(after.map(\.quantity) == [200])
    }

    private func makeModel(_ repository: InMemoryMealRepository) -> MealPlanViewModel {
        let date = today
        return MealPlanViewModel(repository: repository, calendar: calendar, now: { date })
    }

    private func entry(_ name: String, at date: Date) -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(name: name, ingredients: [MealIngredient(name: "Tomato", quantity: 200, unit: "g")]),
            scheduledDate: date,
            mealType: .dinner
        )
    }

    private func count<Entity: NSManagedObject & ManagedEntity>(
        _ type: Entity.Type,
        in controller: PersistenceController
    ) throws -> Int {
        let context = controller.container.newBackgroundContext()
        return try context.performAndWait {
            try context.count(for: NSFetchRequest<Entity>(entityName: type.entityName))
        }
    }
}
