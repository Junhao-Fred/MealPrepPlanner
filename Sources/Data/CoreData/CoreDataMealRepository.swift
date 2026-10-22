//  Created by Junhao Huang on 2026/10/18.

import CoreData

/// Core Data implementation of `MealPlanningRepository`.
/// Works on one background context; saves upsert by ID and failures surface as `RepositoryError`.
actor CoreDataMealRepository: MealPlanningRepository {
    private let context: NSManagedObjectContext
    private let now: @Sendable () -> Date

    init(
        container: NSPersistentContainer,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.context = context
        self.now = now
    }

    // MARK: Writes

    func saveMeal(_ meal: Meal) async throws {
        try await write { context in
            _ = try Self.upsertMeal(meal, in: context)
        }
    }

    func saveIngredient(_ ingredient: Ingredient) async throws {
        try await write { context in
            let entity = try Self.existing(IngredientEntity.self, id: ingredient.id, in: context)
                ?? context.insert(IngredientEntity.self)
            entity.apply(ingredient)
        }
    }

    func saveMealPlanEntry(_ entry: MealPlanEntry) async throws {
        try await write { context in
            let meal = try Self.mealEntity(for: entry.meal, in: context)
            try Self.upsertEntry(entry, meal: meal, in: context)
        }
    }

    func savePlannedMeal(_ entry: MealPlanEntry) async throws {
        try await write { context in
            let meal = try Self.upsertMeal(entry.meal, in: context)
            try Self.upsertEntry(entry, meal: meal, in: context)
        }
    }

    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws {
        try await write { context in
            guard let entity = try Self.existing(MealPlanEntryEntity.self, id: entry.id, in: context) else {
                throw RepositoryError.notFound
            }
            let meal = try Self.mealEntity(for: entry.meal, in: context)
            entity.apply(entry, meal: meal)
        }
    }

    func deleteIngredient(id: UUID) async throws {
        try await write { context in
            guard let entity = try Self.existing(IngredientEntity.self, id: id, in: context) else {
                throw RepositoryError.notFound
            }
            context.delete(entity)
        }
    }

    // MARK: Reads

    func fetchUpcomingMeals() async throws -> [MealPlanEntry] {
        let current = now()
        return try await read { context in
            let request = NSFetchRequest<MealPlanEntryEntity>(entityName: MealPlanEntryEntity.entityName)
            request.predicate = NSPredicate(
                format: "%K == NO AND %K >= %@",
                #keyPath(MealPlanEntryEntity.isPrepared),
                #keyPath(MealPlanEntryEntity.scheduledDate),
                current as NSDate
            )
            request.sortDescriptors = Self.entryOrder
            return try context.fetch(request).map { try $0.makeDomainModel() }
        }
    }

    func fetchMealPlanEntries(
        from start: Date,
        to end: Date,
        includingPrepared includePrepared: Bool
    ) async throws -> [MealPlanEntry] {
        try await read { context in
            var predicates = [
                NSPredicate(
                    format: "%K >= %@ AND %K < %@",
                    #keyPath(MealPlanEntryEntity.scheduledDate),
                    start as NSDate,
                    #keyPath(MealPlanEntryEntity.scheduledDate),
                    end as NSDate
                )
            ]
            if !includePrepared {
                predicates.append(NSPredicate(
                    format: "%K == NO",
                    #keyPath(MealPlanEntryEntity.isPrepared)
                ))
            }
            let request = NSFetchRequest<MealPlanEntryEntity>(entityName: MealPlanEntryEntity.entityName)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = Self.entryOrder
            return try context.fetch(request).map { try $0.makeDomainModel() }
        }
    }

    func fetchAvailableIngredients() async throws -> [Ingredient] {
        try await read { context in
            let request = NSFetchRequest<IngredientEntity>(entityName: IngredientEntity.entityName)
            request.predicate = NSPredicate(
                format: "%K > 0",
                #keyPath(IngredientEntity.quantity)
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(IngredientEntity.name), ascending: true),
                NSSortDescriptor(key: #keyPath(IngredientEntity.id), ascending: true)
            ]
            return try context.fetch(request).map { try $0.makeDomainModel() }
        }
    }

    func fetchIngredientsExpiring(before date: Date) async throws -> [Ingredient] {
        try await read { context in
            let request = NSFetchRequest<IngredientEntity>(entityName: IngredientEntity.entityName)
            request.predicate = NSPredicate(
                format: "%K > 0 AND %K != nil AND %K < %@",
                #keyPath(IngredientEntity.quantity),
                #keyPath(IngredientEntity.expiryDate),
                #keyPath(IngredientEntity.expiryDate),
                date as NSDate
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(IngredientEntity.expiryDate), ascending: true),
                NSSortDescriptor(key: #keyPath(IngredientEntity.id), ascending: true)
            ]
            return try context.fetch(request).map { try $0.makeDomainModel() }
        }
    }

    // MARK: Context access

    /// Runs `body` and saves; on any failure rolls back so nothing partial is stored.
    private func write(
        _ body: @escaping (NSManagedObjectContext) throws -> Void
    ) async throws {
        let context = context
        try await context.perform {
            defer { context.reset() }
            do {
                try body(context)
                try context.save()
            } catch {
                context.rollback()
                throw RepositoryError(coreDataError: error, during: .write)
            }
        }
    }

    private func read<Result: Sendable>(
        _ body: @escaping (NSManagedObjectContext) throws -> Result
    ) async throws -> Result {
        let context = context
        return try await context.perform {
            defer { context.reset() }
            do {
                return try body(context)
            } catch {
                throw RepositoryError(coreDataError: error, during: .read)
            }
        }
    }

    // MARK: Upsert helpers

    private static let entryOrder = [
        NSSortDescriptor(key: #keyPath(MealPlanEntryEntity.scheduledDate), ascending: true),
        NSSortDescriptor(key: #keyPath(MealPlanEntryEntity.id), ascending: true)
    ]

    private static func existing<Entity: NSManagedObject & ManagedEntity>(
        _ entityType: Entity.Type,
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> Entity? {
        let request = NSFetchRequest<Entity>(entityName: entityType.entityName)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Inserts or updates the recipe and its ingredient lines.
    @discardableResult
    private static func upsertMeal(
        _ meal: Meal,
        in context: NSManagedObjectContext
    ) throws -> MealEntity {
        let entity = try existing(MealEntity.self, id: meal.id, in: context)
            ?? context.insert(MealEntity.self)
        try entity.apply(meal, in: context)
        return entity
    }

    /// Links to the stored recipe, creating it only when it is missing.
    private static func mealEntity(
        for meal: Meal,
        in context: NSManagedObjectContext
    ) throws -> MealEntity {
        if let entity = try existing(MealEntity.self, id: meal.id, in: context) {
            return entity
        }
        return try upsertMeal(meal, in: context)
    }

    private static func upsertEntry(
        _ entry: MealPlanEntry,
        meal: MealEntity,
        in context: NSManagedObjectContext
    ) throws {
        let entity = try existing(MealPlanEntryEntity.self, id: entry.id, in: context)
            ?? context.insert(MealPlanEntryEntity.self)
        entity.apply(entry, meal: meal)
    }
}
