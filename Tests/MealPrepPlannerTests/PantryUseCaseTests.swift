//  Created by Mingchen Liang on 2026/10/19.

import Foundation
import Testing
@testable import MealPrepPlanner

@Suite("Pantry validation and stock usage")
struct PantryUseCaseTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Saving trims surrounding whitespace while preserving batch details")
    func saveTrimsInputAndPreservesDetails() async throws {
        let repository = makeRepository()
        var ingredient = makeIngredient(quantity: Decimal(1255) / 10)
        ingredient.name = " \nTomato\t "
        ingredient.unit = " g\n "
        var expected = ingredient
        expected.name = "Tomato"
        expected.unit = "g"

        try await SavePantryIngredientUseCase(repository: repository).execute(ingredient)

        let available = try await repository.fetchAvailableIngredients()
        let writeCount = await repository.writeCount
        #expect(available == [expected])
        #expect(writeCount == 1)
    }

    @Test("Saving an existing ID updates one batch and accepts no expiry")
    func saveUpdatesExistingBatch() async throws {
        let original = makeIngredient()
        let repository = makeRepository(ingredients: [original])
        var updated = original
        updated.quantity = 350
        updated.expiryDate = nil

        try await SavePantryIngredientUseCase(repository: repository).execute(updated)

        let available = try await repository.fetchAvailableIngredients()
        let writeCount = await repository.writeCount
        #expect(available == [updated])
        #expect(writeCount == 1)
    }

    @Test("Invalid pantry input never overwrites existing stock")
    func invalidSaveDoesNotWrite() async throws {
        let original = makeIngredient()
        let repository = makeRepository(ingredients: [original])
        let useCase = SavePantryIngredientUseCase(repository: repository)
        var emptyName = original
        emptyName.name = " \n\t "
        var emptyUnit = original
        emptyUnit.unit = " \n\t "
        var zeroQuantity = original
        zeroQuantity.quantity = 0
        var negativeQuantity = original
        negativeQuantity.quantity = -1
        var notANumber = original
        notANumber.quantity = .nan
        let invalidCases: [(Ingredient, PantryError)] = [
            (emptyName, .emptyIngredientName),
            (emptyUnit, .emptyUnit),
            (zeroQuantity, .invalidQuantity),
            (negativeQuantity, .invalidQuantity),
            (notANumber, .invalidQuantity)
        ]

        for (ingredient, expectedError) in invalidCases {
            await expectError(expectedError) {
                try await useCase.execute(ingredient)
            }
            try await expectStock(repository, equals: [original], writeCount: 0)
        }
    }

    @Test("Partial usage subtracts decimal quantities from only the selected batch")
    func partialUsagePreservesBatchIdentity() async throws {
        let original = makeIngredient(quantity: Decimal(1255) / 10)
        let otherBatch = makeIngredient(quantity: 80)
        let repository = makeRepository(ingredients: [original, otherBatch])
        var expected = original
        expected.quantity = Decimal(10025) / 100

        let updated = try await MarkIngredientUsedUseCase(repository: repository).execute(
            ingredientID: original.id,
            quantity: Decimal(2525) / 100
        )

        #expect(updated == expected)
        try await expectStock(repository, equals: [expected, otherBatch], writeCount: 1)
    }

    @Test("Using all stock saves zero and prevents further use of the depleted batch")
    func fullUsageDepletesBatch() async throws {
        let original = makeIngredient()
        let repository = makeRepository(ingredients: [original])
        let useCase = MarkIngredientUsedUseCase(repository: repository)
        var expected = original
        expected.quantity = 0

        let updated = try await useCase.execute(
            ingredientID: original.id,
            quantity: original.quantity
        )

        #expect(updated == expected)
        try await expectStock(repository, equals: [], writeCount: 1)
        await expectError(PantryError.ingredientNotFound) {
            try await useCase.execute(ingredientID: original.id, quantity: 1)
        }
        try await expectStock(repository, equals: [], writeCount: 1)
    }

    @Test("Invalid usage quantities are rejected before reading or writing stock")
    func invalidUsageDoesNotAccessStock() async throws {
        let original = makeIngredient()
        let repository = makeRepository(ingredients: [original])
        let useCase = MarkIngredientUsedUseCase(repository: repository)
        await repository.fail(.read, with: .readFailed)

        for quantity in [Decimal.zero, Decimal(-1), Decimal.nan] {
            await expectError(PantryError.invalidQuantity) {
                try await useCase.execute(ingredientID: original.id, quantity: quantity)
            }
        }

        await repository.clearFailures()
        try await expectStock(repository, equals: [original], writeCount: 0)
    }

    @Test("T20 excessive usage throws insufficientIngredient and leaves stock unchanged")
    func excessiveUsageDoesNotWrite() async throws {
        let original = makeIngredient()
        let repository = makeRepository(ingredients: [original])
        let useCase = MarkIngredientUsedUseCase(repository: repository)

        await expectError(PantryError.insufficientIngredient) {
            try await useCase.execute(ingredientID: original.id, quantity: original.quantity + 1)
        }

        try await expectStock(repository, equals: [original], writeCount: 0)
    }

    @Test("Missing and initially depleted batches cannot consume another batch")
    func unavailableBatchDoesNotWrite() async throws {
        let available = makeIngredient()
        let depleted = makeIngredient(quantity: 0)
        let repository = makeRepository(ingredients: [available, depleted])
        let useCase = MarkIngredientUsedUseCase(repository: repository)

        for id in [UUID(), depleted.id] {
            await expectError(PantryError.ingredientNotFound) {
                try await useCase.execute(ingredientID: id, quantity: 1)
            }
            try await expectStock(repository, equals: [available], writeCount: 0)
        }
    }

    @Test("Sequential usage reads the remaining quantity from the repository")
    func sequentialUsageReadsCurrentStock() async throws {
        let original = makeIngredient()
        let repository = makeRepository(ingredients: [original])
        let useCase = MarkIngredientUsedUseCase(repository: repository)

        try await useCase.execute(ingredientID: original.id, quantity: 50)
        let updated = try await useCase.execute(ingredientID: original.id, quantity: 25)

        var expected = original
        expected.quantity = 125
        #expect(updated == expected)
        try await expectStock(repository, equals: [expected], writeCount: 2)
    }

    @Test("A failed pantry save propagates the repository error without replacing stock")
    func saveFailurePreservesStock() async throws {
        let original = makeIngredient()
        let repository = makeRepository(ingredients: [original])
        var updated = original
        updated.quantity = 500
        await repository.fail(.write, with: .writeFailed)

        await expectError(RepositoryError.writeFailed) {
            try await SavePantryIngredientUseCase(repository: repository).execute(updated)
        }

        await repository.clearFailures()
        try await expectStock(repository, equals: [original], writeCount: 0)
    }

    @Test("A failed stock read propagates the repository error without writing")
    func usageReadFailurePreservesStock() async throws {
        let original = makeIngredient()
        let repository = makeRepository(ingredients: [original])
        await repository.fail(.read, with: .readFailed)

        await expectError(RepositoryError.readFailed) {
            try await MarkIngredientUsedUseCase(repository: repository).execute(
                ingredientID: original.id, quantity: 50
            )
        }

        await repository.clearFailures()
        try await expectStock(repository, equals: [original], writeCount: 0)
    }

    @Test("A failed stock write propagates the repository error without reducing stock")
    func usageWriteFailurePreservesStock() async throws {
        let original = makeIngredient()
        let repository = makeRepository(ingredients: [original])
        await repository.fail(.write, with: .writeFailed)

        await expectError(RepositoryError.writeFailed) {
            try await MarkIngredientUsedUseCase(repository: repository).execute(
                ingredientID: original.id, quantity: 50
            )
        }

        await repository.clearFailures()
        try await expectStock(repository, equals: [original], writeCount: 0)
    }

    private func makeRepository(ingredients: [Ingredient] = []) -> InMemoryMealRepository {
        let date = now
        return InMemoryMealRepository(ingredients: ingredients, now: { date })
    }

    private func makeIngredient(quantity: Decimal = 200) -> Ingredient {
        Ingredient(name: "Tomato", quantity: quantity, unit: "g", expiryDate: now)
    }

    private func expectError<Expected: Error & Equatable>(
        _ expected: Expected,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected), but the operation succeeded")
        } catch let error as Expected {
            #expect(error == expected)
        } catch {
            Issue.record("Expected \(expected), received \(error)")
        }
    }

    private func expectStock(
        _ repository: InMemoryMealRepository,
        equals expected: [Ingredient],
        writeCount expectedWriteCount: Int
    ) async throws {
        let available = try await repository.fetchAvailableIngredients()
        let writeCount = await repository.writeCount
        let actualByID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        let expectedByID = Dictionary(uniqueKeysWithValues: expected.map { ($0.id, $0) })
        #expect(actualByID == expectedByID)
        #expect(writeCount == expectedWriteCount)
    }
}
