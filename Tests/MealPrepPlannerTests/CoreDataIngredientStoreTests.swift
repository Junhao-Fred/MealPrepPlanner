import CoreData
import Foundation
import Testing
@testable import MealPrepPlanner

@Suite("Core Data ingredient store")
struct CoreDataIngredientStoreTests {
    @Test("Saves and reads an available ingredient")
    func savesAndReadsIngredient() async throws {
        let store = try await makeStore()
        let ingredient = Ingredient(
            name: "Spinach",
            quantity: 250,
            unit: "g",
            expiryDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try await store.save(ingredient)

        let ingredients = try await store.fetchAvailableIngredients()
        #expect(ingredients == [ingredient])
    }

    @Test("Saving the same identifier updates one stored ingredient")
    func updatesIngredientByIdentifier() async throws {
        let store = try await makeStore()
        let id = UUID()

        try await store.save(Ingredient(id: id, name: "Rice", quantity: 2, unit: "kg"))
        try await store.save(Ingredient(id: id, name: "Rice", quantity: 1, unit: "kg"))

        let ingredients = try await store.fetchAvailableIngredients()
        #expect(ingredients.count == 1)
        #expect(ingredients.first?.quantity == 1)
    }

    @Test("Excludes depleted ingredient batches")
    func excludesDepletedIngredients() async throws {
        let store = try await makeStore()

        try await store.save(Ingredient(name: "Beans", quantity: 0, unit: "g"))
        try await store.save(Ingredient(name: "Tomatoes", quantity: 4, unit: "count"))

        let ingredients = try await store.fetchAvailableIngredients()
        #expect(ingredients.map(\.name) == ["Tomatoes"])
    }

    private func makeStore() async throws -> CoreDataIngredientStore {
        let controller = try await PersistenceController.makeInMemory()
        return CoreDataIngredientStore(container: controller.container)
    }
}

@Suite("Core Data mappings")
struct CoreDataMappingTests {
    @Test("Maps a complete meal plan entry without losing values")
    func mapsMealPlanEntryRoundTrip() async throws {
        let controller = try await PersistenceController.makeInMemory()
        let context = controller.container.viewContext
        let plannedMeal = MealPlanEntry(
            meal: Meal(
                name: "Pasta",
                ingredients: [
                    MealIngredient(name: "Pasta", quantity: 120, unit: "g"),
                    MealIngredient(name: "Tomato", quantity: 2, unit: "count")
                ]
            ),
            scheduledDate: Date(timeIntervalSince1970: 1_800_003_600),
            mealType: .dinner
        )

        let mappedEntry = try await context.perform {
            let mealEntity = try context.insert(MealEntity.self)
            try mealEntity.apply(plannedMeal.meal, in: context)
            let entryEntity = try context.insert(MealPlanEntryEntity.self)
            entryEntity.apply(plannedMeal, meal: mealEntity)
            try context.save()
            context.reset()

            let request = MealPlanEntryEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "%K == %@",
                #keyPath(MealPlanEntryEntity.id),
                plannedMeal.id as CVarArg
            )
            request.fetchLimit = 1
            return try context.fetch(request).first?.makeDomainModel()
        }

        let entry = try #require(mappedEntry)
        #expect(entry == plannedMeal)
    }
}
