import CoreData

actor CoreDataIngredientStore {
    private let context: NSManagedObjectContext

    init(container: NSPersistentContainer) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.context = context
    }

    func save(_ ingredient: Ingredient) async throws {
        let context = context
        try await context.perform {
            defer { context.reset() }
            do {
                let request = IngredientEntity.fetchRequest()
                request.predicate = NSPredicate(
                    format: "%K == %@",
                    #keyPath(IngredientEntity.id),
                    ingredient.id as CVarArg
                )
                request.fetchLimit = 1

                let entity = try context.fetch(request).first
                    ?? context.insert(IngredientEntity.self)
                entity.apply(ingredient)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    func fetchAvailableIngredients() async throws -> [Ingredient] {
        let context = context
        return try await context.perform {
            defer { context.reset() }
            let request = IngredientEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "%K > 0",
                #keyPath(IngredientEntity.quantity)
            )
            request.sortDescriptors = [
                NSSortDescriptor(
                    key: #keyPath(IngredientEntity.name),
                    ascending: true
                )
            ]
            return try context.fetch(request).map { try $0.makeDomainModel() }
        }
    }
}
