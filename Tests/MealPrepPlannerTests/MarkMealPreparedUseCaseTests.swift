import Foundation
import Testing
@testable import MealPrepPlanner

struct MarkMealPreparedUseCaseTests {
    private let now = Date(timeIntervalSince1970: 1_704_110_400)

    @Test("T19 missing plan throws entryNotFound")
    func missingEntry() async {
        let repository = InMemoryMealRepository()
        let useCase = MarkMealPreparedUseCase(repository: repository)

        do {
            _ = try await useCase.execute(id: UUID())
            Issue.record("Expected entryNotFound")
        } catch let error as MealPreparationError {
            #expect(error == .entryNotFound)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let writes = await repository.writeCount
        #expect(writes == 0)
    }

    @Test("Preparing a meal returns the saved entry without using pantry stock")
    func prepareMeal() async throws {
        let entry = makeEntry()
        let stock = Ingredient(name: "Oats", quantity: 500, unit: "g")
        let repository = InMemoryMealRepository(entries: [entry], ingredients: [stock])
        let useCase = MarkMealPreparedUseCase(repository: repository)

        let result = try await useCase.execute(id: entry.id)
        var expected = entry
        expected.isPrepared = true
        #expect(result == expected)
        let stored = try await useCase.load(id: entry.id)
        #expect(stored == expected)
        let remainingStock = try await repository.fetchAvailableIngredients()
        #expect(remainingStock == [stock])

        let repeated = try await useCase.execute(id: entry.id)
        #expect(repeated == expected)
        let writes = await repository.writeCount
        #expect(writes == 1)
    }

    @Test("Failed completion preserves the stored plan")
    func failedWrite() async throws {
        let entry = makeEntry()
        let repository = InMemoryMealRepository(entries: [entry])
        await repository.fail(.write, with: .writeFailed)
        let useCase = MarkMealPreparedUseCase(repository: repository)

        do {
            _ = try await useCase.execute(id: entry.id)
            Issue.record("Expected writeFailed")
        } catch let error as RepositoryError {
            #expect(error == .writeFailed)
        }
        let stored = try await useCase.load(id: entry.id)
        #expect(stored == entry)
        let writes = await repository.writeCount
        #expect(writes == 0)
    }

    private func makeEntry() -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(name: "Oats", ingredients: [MealIngredient(name: "Oats", quantity: 80, unit: "g")]),
            scheduledDate: now,
            mealType: .breakfast
        )
    }
}
