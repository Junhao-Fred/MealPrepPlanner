//  Created by Junhao Huang on 2026/9/27.

import CoreData

enum ManagedObjectCreationError: Error, Equatable, Sendable {
    case entityNotFound(named: String)
}

protocol ManagedEntity where Self: NSManagedObject {
    static var entityName: String { get }
}

extension NSManagedObjectContext {
    func insert<Entity: NSManagedObject & ManagedEntity>(
        _ entityType: Entity.Type
    ) throws -> Entity {
        guard let description = NSEntityDescription.entity(
            forEntityName: entityType.entityName,
            in: self
        ) else {
            throw ManagedObjectCreationError.entityNotFound(named: entityType.entityName)
        }
        return Entity(entity: description, insertInto: self)
    }
}

@objc(IngredientEntity)
final class IngredientEntity: NSManagedObject, ManagedEntity {
    static let entityName = "IngredientEntity"

    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var quantity: NSDecimalNumber?
    @NSManaged var unit: String?
    @NSManaged var expiryDate: Date?
}

@objc(MealEntity)
final class MealEntity: NSManagedObject, ManagedEntity {
    static let entityName = "MealEntity"

    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var ingredients: NSOrderedSet?
    @NSManaged var planEntries: NSSet?
}

@objc(MealIngredientEntity)
final class MealIngredientEntity: NSManagedObject, ManagedEntity {
    static let entityName = "MealIngredientEntity"

    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var quantity: NSDecimalNumber?
    @NSManaged var unit: String?
    @NSManaged var meal: MealEntity?
}

@objc(MealPlanEntryEntity)
final class MealPlanEntryEntity: NSManagedObject, ManagedEntity {
    static let entityName = "MealPlanEntryEntity"

    @NSManaged var id: UUID?
    @NSManaged var scheduledDate: Date?
    @NSManaged var mealType: String?
    @NSManaged var isPrepared: Bool
    @NSManaged var meal: MealEntity?
}
