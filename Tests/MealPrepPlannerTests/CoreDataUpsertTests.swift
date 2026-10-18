//  Created by Junhao Huang on 2026/10/18.

import CoreData
import Foundation
import Testing
@testable import MealPrepPlanner

/// T22: saving the same ID again updates the stored row instead of adding another one.
@Suite("Core Data upsert")
struct CoreDataUpsertTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("T22 saving the same planned meal twice keeps one row per object")
    func plannedMealUpsertKeepsOneRow() async throws {
        let (repository, container) = try await makeRepository()
        let pasta = MealIngredient(name: "Pasta", quantity: 120, unit: "g")
        let tomato = MealIngredient(name: "Tomato", quantity: 2, unit: "count")
        var entry = MealPlanEntry(
            meal: Meal(name: "Pasta", ingredients: [pasta, tomato]),
            scheduledDate: now.addingTimeInterval(3_600),
            mealType: .lunch
        )

        try await repository.savePlannedMeal(entry)
        entry.mealType = .dinner
        entry.meal.name = "Tomato pasta"
        entry.meal.ingredients[0].quantity = 150
        try await repository.savePlannedMeal(entry)

        #expect(try await count(MealPlanEntryEntity.self, in: container) == 1)
        #expect(try await count(MealEntity.self, in: container) == 1)
        #expect(try await count(MealIngredientEntity.self, in: container) == 2)
        let upcoming = try await repository.fetchUpcomingMeals()
        #expect(upcoming == [entry])
    }

    @Test("T22 saving the same pantry batch twice keeps one row with the latest quantity")
    func ingredientUpsertKeepsOneRow() async throws {
        let (repository, container) = try await makeRepository()
        var rice = Ingredient(name: "Rice", quantity: 2, unit: "kg")

        try await repository.saveIngredient(rice)
        rice.quantity = 1
        try await repository.saveIngredient(rice)

        #expect(try await count(IngredientEntity.self, in: container) == 1)
        let available = try await repository.fetchAvailableIngredients()
        #expect(available == [rice])
    }

    @Test("T22 removing an ingredient line from a meal deletes its row")
    func removedIngredientLineIsDeleted() async throws {
        let (repository, container) = try await makeRepository()
        var meal = Meal(
            name: "Salad",
            ingredients: [
                MealIngredient(name: "Lettuce", quantity: 1, unit: "count"),
                MealIngredient(name: "Feta", quantity: 50, unit: "g")
            ]
        )

        try await repository.saveMeal(meal)
        meal.ingredients.removeLast()
        try await repository.saveMeal(meal)

        #expect(try await count(MealEntity.self, in: container) == 1)
        #expect(try await count(MealIngredientEntity.self, in: container) == 1)
    }

    private func makeRepository() async throws -> (CoreDataMealRepository, NSPersistentContainer) {
        let controller = try await PersistenceController.makeInMemory()
        let now = now
        let repository = CoreDataMealRepository(container: controller.container, now: { now })
        return (repository, controller.container)
    }

    private func count<Entity: NSManagedObject & ManagedEntity>(
        _ entityType: Entity.Type,
        in container: NSPersistentContainer
    ) async throws -> Int {
        let context = container.newBackgroundContext()
        return try await context.perform {
            try context.count(for: NSFetchRequest<Entity>(entityName: entityType.entityName))
        }
    }
}
