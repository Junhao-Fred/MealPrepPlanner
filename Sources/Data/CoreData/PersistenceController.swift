import CoreData

enum PersistenceControllerError: Error, Equatable, Sendable {
    case modelNotFound
    case modelUnreadable
}

final class PersistenceController {
    let container: NSPersistentContainer

    private init(container: NSPersistentContainer) {
        self.container = container
    }

    static func makeInMemory() async throws -> PersistenceController {
        try await makeController(storeDescription: inMemoryStoreDescription())
    }

    static func makePersistent() async throws -> PersistenceController {
        try await makeController()
    }

    private static func makeController(
        storeDescription: NSPersistentStoreDescription? = nil
    ) async throws -> PersistenceController {
        let model = try managedObjectModel()
        let container = NSPersistentContainer(
            name: "MealPrepPlanner",
            managedObjectModel: model
        )
        if let storeDescription {
            container.persistentStoreDescriptions = [storeDescription]
        }

        let controller = PersistenceController(container: container)
        try await controller.loadPersistentStore()
        await controller.configureViewContext()
        return controller
    }

    private static func inMemoryStoreDescription() -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        return description
    }

    private static func managedObjectModel() throws -> NSManagedObjectModel {
        let bundle = Bundle(for: IngredientEntity.self)
        guard let modelURL = bundle.url(
            forResource: "MealPrepPlanner",
            withExtension: "momd"
        ) else {
            throw PersistenceControllerError.modelNotFound
        }
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw PersistenceControllerError.modelUnreadable
        }
        return model
    }

    private func loadPersistentStore() async throws {
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func configureViewContext() async {
        let context = container.viewContext
        await context.perform {
            context.automaticallyMergesChangesFromParent = true
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        }
    }
}
