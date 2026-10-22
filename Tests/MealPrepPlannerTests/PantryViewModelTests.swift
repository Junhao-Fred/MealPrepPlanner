//  Created by Mingchen Liang on 2026/10/20.

import Foundation
import Testing
@testable import MealPrepPlanner

@MainActor
@Suite("Pantry loading and view model")
struct PantryViewModelTests {
    @Test("Loading keeps expired positive batches, omits depleted stock and sorts by name")
    func loadUseCaseKeepsVisibleStock() async throws {
        let expired = Ingredient(name: "Apple", quantity: 2, unit: "piece",
                                 expiryDate: Date(timeIntervalSince1970: 0))
        let fresh = Ingredient(name: "Rice", quantity: 100, unit: "g")
        let depleted = Ingredient(name: "Oats", quantity: 0, unit: "g")
        let repository = InMemoryMealRepository(ingredients: [fresh, depleted, expired])

        let result = try await LoadPantryUseCase(repository: repository).execute()

        #expect(result == [expired, fresh])
        let writes = await repository.writeCount
        #expect(writes == 0)
    }

    @Test("A failed initial load can be retried and later failures preserve the displayed list")
    func loadFailureAndRetry() async {
        let stock = makeIngredient()
        let repository = InMemoryMealRepository(ingredients: [stock])
        let model = PantryViewModel(repository: repository)
        await repository.fail(.read, with: .readFailed)

        await model.load()
        #expect(model.ingredients.isEmpty)
        #expect(model.needsReload)
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)

        await repository.clearFailures()
        await model.load()
        #expect(model.ingredients == [stock])
        #expect(!model.needsReload)
        #expect(model.errorMessage == nil)

        await repository.fail(.read, with: .storeUnavailable)
        await model.load()
        #expect(model.ingredients == [stock])
        #expect(model.needsReload)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
        model.clearError()
        #expect(model.errorMessage == nil)
    }

    @Test("An empty pantry finishes loading without an error")
    func emptyPantryIsLoaded() async {
        let model = PantryViewModel(repository: InMemoryMealRepository())

        await model.load()

        #expect(model.ingredients.isEmpty)
        #expect(!model.needsReload)
        #expect(!model.isBusy)
        #expect(model.errorMessage == nil)
    }

    @Test("Saving uses domain validation and refreshes the normalized ingredient")
    func savesAndRefreshes() async {
        let repository = InMemoryMealRepository()
        let model = PantryViewModel(repository: repository)
        var input = makeIngredient()
        input.name = " Rice "
        input.unit = " g\n"
        var expected = input
        expected.name = "Rice"
        expected.unit = "g"

        let saved = await model.save(input)

        #expect(saved)
        #expect(model.ingredients == [expected])
        #expect(!model.needsReload)
        #expect(!model.isSaving)
        #expect(model.errorMessage == nil)
        let writes = await repository.writeCount
        #expect(writes == 1)
    }

    @Test("Invalid input and failed saves return false without replacing the list")
    func failedSavePreservesList() async {
        let stock = makeIngredient()
        let repository = InMemoryMealRepository(ingredients: [stock])
        let model = PantryViewModel(repository: repository)
        await model.load()
        var invalid = stock
        invalid.name = " \n"

        let invalidSaved = await model.save(invalid)
        #expect(!invalidSaved)
        #expect(model.errorMessage == "Enter an ingredient name.")

        await repository.fail(.write, with: .writeFailed)
        var changed = stock
        changed.quantity = 200
        let saved = await model.save(changed)
        #expect(!saved)
        #expect(model.ingredients == [stock])
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)
        let writes = await repository.writeCount
        #expect(writes == 0)
    }

    @Test("Explicit use refreshes remaining stock and removes a depleted batch")
    func usesAndDepletesStock() async {
        let stock = makeIngredient()
        let repository = InMemoryMealRepository(ingredients: [stock])
        let model = PantryViewModel(repository: repository)
        await model.load()

        let used = await model.useIngredient(id: stock.id, quantity: 25)
        var remaining = stock
        remaining.quantity = 75
        #expect(used)
        #expect(model.ingredients == [remaining])

        let depleted = await model.useIngredient(id: stock.id, quantity: 75)
        #expect(depleted)
        #expect(model.ingredients.isEmpty)
        #expect(model.usingIngredientID == nil)
        #expect(!model.needsReload)
        #expect(model.errorMessage == nil)
        let writes = await repository.writeCount
        #expect(writes == 2)
    }

    @Test("Excessive use and storage failures preserve stock and release busy state")
    func failedUsagePreservesStock() async throws {
        let stock = makeIngredient()
        let repository = InMemoryMealRepository(ingredients: [stock])
        let model = PantryViewModel(repository: repository)
        await model.load()

        let excessive = await model.useIngredient(id: stock.id, quantity: 101)
        #expect(!excessive)
        #expect(model.errorMessage == "The amount exceeds the available stock.")

        await repository.fail(.write, with: .writeFailed)
        let failed = await model.useIngredient(id: stock.id, quantity: 25)
        #expect(!failed)
        #expect(model.ingredients == [stock])
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)
        await repository.clearFailures()
        let stored = try await repository.fetchAvailableIngredients()
        let writes = await repository.writeCount
        #expect(stored == [stock])
        #expect(writes == 0)
    }

    @Test("A successful write followed by a failed refresh is retried as a read",
          arguments: [true, false])
    func refreshFailureDoesNotRepeatWrite(saving: Bool) async {
        let stock = makeIngredient()
        let base = InMemoryMealRepository(ingredients: [stock])
        let repository = ControlledPantryRepository(base: base, failReadsAfterWrite: true)
        let model = PantryViewModel(repository: repository)
        await model.load()
        var changed = stock
        changed.quantity = 75

        let succeeded: Bool
        if saving {
            succeeded = await model.save(changed)
        } else {
            succeeded = await model.useIngredient(id: stock.id, quantity: 25)
            #expect(model.ingredients == [changed])
        }

        #expect(succeeded)
        #expect(model.needsReload)
        #expect(model.errorMessage?.contains("Unable to refresh") == true)
        #expect(!model.isBusy)
        await base.clearFailures()
        await model.load()
        #expect(model.ingredients == [changed])
        #expect(!model.needsReload)
        #expect(model.errorMessage == nil)
        let writes = await base.writeCount
        #expect(writes == 1)
    }

    @Test("While a write is suspended, duplicate writes and competing loads are rejected",
          arguments: [true, false])
    func serializesOperations(saving: Bool) async {
        let stock = makeIngredient()
        let base = InMemoryMealRepository(ingredients: [stock])
        let repository = ControlledPantryRepository(base: base, pauseWrite: true)
        let model = PantryViewModel(repository: repository)
        await model.load()
        var changed = stock
        changed.quantity = 75
        let input = changed
        let operation = Task {
            if saving { return await model.save(input) }
            return await model.useIngredient(id: stock.id, quantity: 25)
        }
        await repository.waitForPausedWrite()

        #expect(model.isBusy)
        #expect(model.isSaving == saving)
        #expect(model.usingIngredientID == (saving ? nil : stock.id))
        let duplicateSave = await model.save(input)
        let duplicateUse = await model.useIngredient(id: stock.id, quantity: 25)
        await model.load()
        #expect(!duplicateSave)
        #expect(!duplicateUse)
        #expect(model.isBusy)
        await repository.resumeWrite()
        let succeeded = await operation.value

        #expect(succeeded)
        #expect(!model.isBusy)
        #expect(model.ingredients == [changed])
        let writes = await base.writeCount
        #expect(writes == 1)
    }

    private func makeIngredient() -> Ingredient {
        Ingredient(name: "Rice", quantity: 100, unit: "g")
    }
}

/// Adds deterministic suspension and refresh failure to the shared in-memory repository.
private actor ControlledPantryRepository: MealPlanningRepository {
    private let base: InMemoryMealRepository
    private var shouldPauseWrite: Bool
    private let failReadsAfterWrite: Bool
    private var pendingWrite: CheckedContinuation<Void, Never>?
    private var writeObservers: [CheckedContinuation<Void, Never>] = []

    init(base: InMemoryMealRepository, pauseWrite: Bool = false, failReadsAfterWrite: Bool = false) {
        self.base = base
        shouldPauseWrite = pauseWrite
        self.failReadsAfterWrite = failReadsAfterWrite
    }

    func waitForPausedWrite() async {
        if pendingWrite != nil { return }
        await withCheckedContinuation { writeObservers.append($0) }
    }

    func resumeWrite() {
        pendingWrite?.resume()
        pendingWrite = nil
    }

    func saveIngredient(_ ingredient: Ingredient) async throws {
        if shouldPauseWrite {
            // Only pause the first write: a duplicate must fail assertions, not deadlock the test.
            shouldPauseWrite = false
            await withCheckedContinuation { continuation in
                pendingWrite = continuation
                for observer in writeObservers { observer.resume() }
                writeObservers.removeAll()
            }
        }
        try await base.saveIngredient(ingredient)
        if failReadsAfterWrite { await base.fail(.read, with: .readFailed) }
    }

    func fetchAvailableIngredients() async throws -> [Ingredient] {
        try await base.fetchAvailableIngredients()
    }

    func saveMeal(_ meal: Meal) async throws { try await base.saveMeal(meal) }
    func saveMealPlanEntry(_ entry: MealPlanEntry) async throws { try await base.saveMealPlanEntry(entry) }
    func savePlannedMeal(_ entry: MealPlanEntry) async throws { try await base.savePlannedMeal(entry) }
    func fetchUpcomingMeals() async throws -> [MealPlanEntry] { try await base.fetchUpcomingMeals() }
    func fetchMealPlanEntries(from start: Date, to end: Date, includingPrepared includePrepared: Bool) async throws -> [MealPlanEntry] {
        try await base.fetchMealPlanEntries(from: start, to: end, includingPrepared: includePrepared)
    }
    func fetchIngredientsExpiring(before date: Date) async throws -> [Ingredient] {
        try await base.fetchIngredientsExpiring(before: date)
    }
    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws { try await base.updateMealPlanEntry(entry) }
    func deleteIngredient(id: UUID) async throws { try await base.deleteIngredient(id: id) }
}
