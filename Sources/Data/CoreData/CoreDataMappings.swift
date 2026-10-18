//  Created by Junhao Huang on 2026/9/27.

import CoreData

enum CoreDataMappingError: Error, Equatable, Sendable {
    case missingRequiredValue(entity: String, property: String)
    case invalidMealType(rawValue: String)
}

private extension ManagedEntity where Self: NSManagedObject {
    func required<Value>(_ value: Value?, property: String) throws -> Value {
        guard let value else {
            throw CoreDataMappingError.missingRequiredValue(
                entity: Self.entityName,
                property: property
            )
        }
        return value
    }
}

extension IngredientEntity {
    func apply(_ ingredient: Ingredient) {
        id = ingredient.id
        name = ingredient.name
        quantity = NSDecimalNumber(decimal: ingredient.quantity)
        unit = ingredient.unit
        expiryDate = ingredient.expiryDate
    }

    func makeDomainModel() throws -> Ingredient {
        let id = try required(id, property: "id")
        let name = try required(name, property: "name")
        let quantity = try required(quantity, property: "quantity")
        let unit = try required(unit, property: "unit")

        return Ingredient(
            id: id,
            name: name,
            quantity: quantity.decimalValue,
            unit: unit,
            expiryDate: expiryDate
        )
    }
}

extension MealIngredientEntity {
    func apply(_ ingredient: MealIngredient) {
        id = ingredient.id
        name = ingredient.name
        quantity = NSDecimalNumber(decimal: ingredient.quantity)
        unit = ingredient.unit
    }

    func makeDomainModel() throws -> MealIngredient {
        let id = try required(id, property: "id")
        let name = try required(name, property: "name")
        let quantity = try required(quantity, property: "quantity")
        let unit = try required(unit, property: "unit")

        return MealIngredient(
            id: id,
            name: name,
            quantity: quantity.decimalValue,
            unit: unit
        )
    }
}

extension MealEntity {
    func apply(_ meal: Meal, in context: NSManagedObjectContext) throws {
        id = meal.id
        name = meal.name

        let existingIngredients = ingredients?.array as? [MealIngredientEntity] ?? []
        var existingByID: [UUID: MealIngredientEntity] = [:]
        for entity in existingIngredients {
            if let id = entity.id {
                existingByID[id] = entity
            }
        }

        let mappedIngredients = try meal.ingredients.map { ingredient in
            let entity = try existingByID[ingredient.id]
                ?? context.insert(MealIngredientEntity.self)
            entity.apply(ingredient)
            entity.meal = self
            return entity
        }

        let retainedIDs = Set(meal.ingredients.map(\.id))
        for entity in existingIngredients where entity.id.map({ !retainedIDs.contains($0) }) ?? true {
            context.delete(entity)
        }
        ingredients = NSOrderedSet(array: mappedIngredients)
    }

    func makeDomainModel() throws -> Meal {
        let id = try required(id, property: "id")
        let name = try required(name, property: "name")

        let ingredientEntities = ingredients?.array as? [MealIngredientEntity] ?? []
        return try Meal(
            id: id,
            name: name,
            ingredients: ingredientEntities.map { try $0.makeDomainModel() }
        )
    }
}

extension MealPlanEntryEntity {
    func apply(_ entry: MealPlanEntry, meal mealEntity: MealEntity) {
        id = entry.id
        scheduledDate = entry.scheduledDate
        mealType = entry.mealType.rawValue
        isPrepared = entry.isPrepared
        meal = mealEntity
    }

    func makeDomainModel() throws -> MealPlanEntry {
        let id = try required(id, property: "id")
        let scheduledDate = try required(scheduledDate, property: "scheduledDate")
        let mealType = try required(mealType, property: "mealType")
        guard let domainMealType = MealType(rawValue: mealType) else {
            throw CoreDataMappingError.invalidMealType(rawValue: mealType)
        }
        let meal = try required(meal, property: "meal")

        return try MealPlanEntry(
            id: id,
            meal: meal.makeDomainModel(),
            scheduledDate: scheduledDate,
            mealType: domainMealType,
            isPrepared: isPrepared
        )
    }
}
