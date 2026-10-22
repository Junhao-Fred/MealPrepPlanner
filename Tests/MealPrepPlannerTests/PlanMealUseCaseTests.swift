//  Created by Junhao Huang on 2026/9/27.

import Foundation
import Testing
@testable import MealPrepPlanner

struct PlanMealUseCaseTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A valid plan is saved with one atomic repository call")
    func validPlanUsesAtomicWrite() async throws {
        let repository = RecordingMealRepository()
        let entry = makeEntry()
        let useCase = PlanMealUseCase(repository: repository, now: { now })

        try await useCase.execute(entry)

        let savedEntries = await repository.plannedEntries
        #expect(savedEntries == [entry])
    }

    @Test("T16 blank names and other invalid plans never reach storage")
    func invalidPlansDoNotWrite() async {
        let repository = RecordingMealRepository()
        let useCase = PlanMealUseCase(repository: repository, now: { now })
        // T16: a whitespace-only name must throw emptyMealName before saving.
        var emptyName = makeEntry()
        emptyName.meal.name = " \n "
        var emptyRecipe = makeEntry()
        emptyRecipe.meal.ingredients = []
        var invalidIngredient = makeEntry()
        invalidIngredient.meal.ingredients[0].quantity = 0
        var pastSchedule = makeEntry()
        pastSchedule.scheduledDate = now.addingTimeInterval(-1)

        let invalidCases: [(MealPlanEntry, MealPlanningValidationError)] = [
            (emptyName, .emptyMealName),
            (emptyRecipe, .emptyIngredients),
            (invalidIngredient, .invalidIngredient),
            (pastSchedule, .scheduledInThePast)
        ]

        for (entry, expectedError) in invalidCases {
            do {
                try await useCase.execute(entry)
                Issue.record("Expected \(expectedError) for \(entry.id)")
            } catch let error as MealPlanningValidationError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }

        let savedEntries = await repository.plannedEntries
        #expect(savedEntries.isEmpty)
    }

    private func makeEntry() -> MealPlanEntry {
        let ingredient = MealIngredient(name: "Oats", quantity: 100, unit: "g")
        let meal = Meal(name: "Breakfast", ingredients: [ingredient])
        return MealPlanEntry(
            meal: meal,
            scheduledDate: now.addingTimeInterval(3_600),
            mealType: .breakfast
        )
    }
}

private actor RecordingMealRepository: MealPlanningRepository {
    private(set) var plannedEntries: [MealPlanEntry] = []

    func savePlannedMeal(_ entry: MealPlanEntry) async throws {
        plannedEntries.append(entry)
    }

    func saveMeal(_ meal: Meal) async throws { throw UnexpectedCall() }
    func saveIngredient(_ ingredient: Ingredient) async throws { throw UnexpectedCall() }
    func saveMealPlanEntry(_ entry: MealPlanEntry) async throws { throw UnexpectedCall() }
    func fetchUpcomingMeals() async throws -> [MealPlanEntry] { throw UnexpectedCall() }
    func fetchMealPlanEntries(
        from start: Date,
        to end: Date,
        includingPrepared includePrepared: Bool
    ) async throws -> [MealPlanEntry] { throw UnexpectedCall() }
    func fetchAvailableIngredients() async throws -> [Ingredient] { throw UnexpectedCall() }
    func fetchIngredientsExpiring(before date: Date) async throws -> [Ingredient] {
        throw UnexpectedCall()
    }
    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws { throw UnexpectedCall() }
    func deleteIngredient(id: UUID) async throws { throw UnexpectedCall() }
}

private struct UnexpectedCall: Error {}
