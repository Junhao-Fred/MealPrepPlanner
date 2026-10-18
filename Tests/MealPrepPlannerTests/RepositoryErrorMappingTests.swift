//  Created by Junhao Huang on 2026/10/18.

import CoreData
import Foundation
import Testing
@testable import MealPrepPlanner

/// T21: storage failures reach use cases as `RepositoryError`.
@Suite("Repository error mapping")
struct RepositoryErrorMappingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("T21 a failed repository write reaches the use case as RepositoryError")
    func useCasePropagatesRepositoryError() async throws {
        let now = now
        let repository = InMemoryMealRepository(now: { now })
        await repository.fail(.write, with: .writeFailed)
        let useCase = PlanMealUseCase(repository: repository, now: { now })
        let entry = MealPlanEntry(
            meal: Meal(
                name: "Pasta",
                ingredients: [MealIngredient(name: "Pasta", quantity: 120, unit: "g")]
            ),
            scheduledDate: now.addingTimeInterval(3_600),
            mealType: .dinner
        )

        do {
            try await useCase.execute(entry)
            Issue.record("Expected RepositoryError.writeFailed")
        } catch let error as RepositoryError {
            #expect(error == .writeFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("T21 store errors map to storeUnavailable")
    func storeErrorsMapToStoreUnavailable() {
        let openError = NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreOpenError)
        let migrationError = NSError(domain: NSCocoaErrorDomain, code: NSMigrationError)

        #expect(RepositoryError(coreDataError: openError, during: .read) == .storeUnavailable)
        #expect(RepositoryError(coreDataError: migrationError, during: .write) == .storeUnavailable)
        #expect(RepositoryError(coreDataError: PersistenceControllerError.modelNotFound, during: .read) == .storeUnavailable)
    }

    @Test("T21 other errors map by read or write")
    func otherErrorsMapByAccess() {
        let validationError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSValidationMissingMandatoryPropertyError
        )
        let mappingError = CoreDataMappingError.missingRequiredValue(entity: "MealEntity", property: "name")

        #expect(RepositoryError(coreDataError: validationError, during: .write) == .writeFailed)
        #expect(RepositoryError(coreDataError: validationError, during: .read) == .readFailed)
        #expect(RepositoryError(coreDataError: mappingError, during: .read) == .readFailed)
    }

    @Test("T21 repository errors pass through unchanged")
    func repositoryErrorsPassThrough() {
        #expect(RepositoryError(coreDataError: RepositoryError.notFound, during: .write) == .notFound)
    }
}
