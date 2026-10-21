//  Created by Mingchen Liang on 2026/10/20.

import Foundation
import Testing
@testable import MealPrepPlanner

@Suite("Meal plan save and query")
struct MealPlanQueryTests {
    // Deliberately not midnight: queries must preserve the caller's exact boundaries.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("T15 a saved meal plan can be queried with its original ID and recipe")
    func savedPlanCanBeReadBack() async throws {
        let fixedNow = now
        let repository = InMemoryMealRepository(now: { fixedNow })
        let entry = makeEntry(offset: 3_600)
        let save = PlanMealUseCase(repository: repository, now: { fixedNow })
        let query = GetMealPlanUseCase(repository: repository)

        try await save.execute(entry)
        let result = try await query.execute(from: now, to: now.addingTimeInterval(7_200))

        #expect(result == [entry])
        #expect(result.first?.id == entry.id)
        let writes = await repository.writeCount
        #expect(writes == 1)
    }

    @Test("Queries include the start, exclude the end and return plans oldest first")
    func respectsExactRangeAndOrdering() async throws {
        let beforeStart = makeEntry(offset: -1)
        let atStart = makeEntry(offset: 0)
        let middle = makeEntry(offset: 1_800)
        let beforeEnd = makeEntry(offset: 3_599)
        let atEnd = makeEntry(offset: 3_600)
        let afterEnd = makeEntry(offset: 3_601)
        let repository = InMemoryMealRepository(entries: [
            atEnd, beforeEnd, beforeStart, middle, afterEnd, atStart
        ])

        let result = try await GetMealPlanUseCase(repository: repository).execute(
            from: now, to: now.addingTimeInterval(3_600)
        )

        #expect(result == [atStart, middle, beforeEnd])
    }

    @Test("Prepared plans are included by default")
    func includesPreparedPlansByDefault() async throws {
        let prepared = makeEntry(offset: 600, prepared: true)
        let unfinished = makeEntry(offset: 1_200)
        let repository = InMemoryMealRepository(entries: [unfinished, prepared])

        let result = try await GetMealPlanUseCase(repository: repository).execute(
            from: now, to: now.addingTimeInterval(3_600)
        )

        #expect(result == [prepared, unfinished])
    }

    @Test("The completion flag controls whether prepared plans appear", arguments: [true, false])
    func filtersCompletionStatus(includePrepared: Bool) async throws {
        let prepared = makeEntry(offset: 600, prepared: true)
        let unfinished = makeEntry(offset: 1_200)
        let repository = InMemoryMealRepository(entries: [prepared, unfinished])

        let result = try await GetMealPlanUseCase(repository: repository).execute(
            from: now,
            to: now.addingTimeInterval(3_600),
            includingPrepared: includePrepared
        )

        let expected = includePrepared ? [prepared, unfinished] : [unfinished]
        #expect(result == expected)
    }

    @Test("Queries return an empty list when no plans match")
    func returnsEmptyWithoutMatches() async throws {
        let emptyRepository = InMemoryMealRepository()
        let emptyResult = try await GetMealPlanUseCase(repository: emptyRepository).execute(
            from: now, to: now.addingTimeInterval(3_600)
        )
        let filteredRepository = InMemoryMealRepository(entries: [
            makeEntry(offset: -1),
            makeEntry(offset: 600, prepared: true),
            makeEntry(offset: 3_600)
        ])
        let filteredResult = try await GetMealPlanUseCase(repository: filteredRepository).execute(
            from: now, to: now.addingTimeInterval(3_600), includingPrepared: false
        )

        #expect(emptyResult.isEmpty)
        #expect(filteredResult.isEmpty)
    }

    @Test("Equal or reversed boundaries are rejected before any read", arguments: [0, -1])
    func rejectsInvalidRanges(endOffset: Int) async throws {
        let entry = makeEntry(offset: 600)
        let repository = InMemoryMealRepository(entries: [entry])
        // A read would throw readFailed instead of the expected validation error.
        await repository.fail(.read, with: .readFailed)
        let query = GetMealPlanUseCase(repository: repository)

        do {
            _ = try await query.execute(from: now, to: now.addingTimeInterval(Double(endOffset)))
            Issue.record("Expected MealPlanQueryError.invalidDateRange")
        } catch let error as MealPlanQueryError {
            #expect(error == .invalidDateRange)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        await repository.clearFailures()
        let remaining = try await query.execute(from: now, to: now.addingTimeInterval(3_600))
        let writes = await repository.writeCount
        #expect(remaining == [entry])
        #expect(writes == 0)
    }

    @Test("Read failures propagate unchanged rather than returning an empty list",
          arguments: [RepositoryError.readFailed, RepositoryError.storeUnavailable])
    func propagatesReadFailures(expectedError: RepositoryError) async throws {
        let entry = makeEntry(offset: 600)
        let repository = InMemoryMealRepository(entries: [entry])
        await repository.fail(.read, with: expectedError)
        let query = GetMealPlanUseCase(repository: repository)

        do {
            _ = try await query.execute(from: now, to: now.addingTimeInterval(3_600))
            Issue.record("Expected \(expectedError)")
        } catch let error as RepositoryError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        await repository.clearFailures()
        let recovered = try await query.execute(from: now, to: now.addingTimeInterval(3_600))
        #expect(recovered == [entry])
    }

    @Test("Repeated queries do not change meal plans or pantry stock")
    func queriesAreReadOnly() async throws {
        let entry = makeEntry(offset: 600)
        let stock = Ingredient(name: "Oats", quantity: 300, unit: "g")
        let repository = InMemoryMealRepository(entries: [entry], ingredients: [stock])
        let query = GetMealPlanUseCase(repository: repository)

        let first = try await query.execute(from: now, to: now.addingTimeInterval(3_600))
        let second = try await query.execute(from: now, to: now.addingTimeInterval(3_600))
        let storedPlans = try await repository.fetchMealPlanEntries(
            from: now, to: now.addingTimeInterval(3_600), includingPrepared: true
        )
        let storedStock = try await repository.fetchAvailableIngredients()
        let writes = await repository.writeCount

        #expect(first == [entry])
        #expect(second == first)
        #expect(storedPlans == [entry])
        #expect(storedStock == [stock])
        #expect(writes == 0)
    }

    @Test("A failed save leaves no new plan to query and preserves existing plans")
    func failedSaveDoesNotAppearInQueries() async throws {
        let fixedNow = now
        let existing = makeEntry(offset: 600)
        let repository = InMemoryMealRepository(entries: [existing], now: { fixedNow })
        let save = PlanMealUseCase(repository: repository, now: { fixedNow })
        await repository.fail(.write, with: .writeFailed)

        do {
            try await save.execute(makeEntry(offset: 1_200))
            Issue.record("Expected RepositoryError.writeFailed")
        } catch let error as RepositoryError {
            #expect(error == .writeFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        await repository.clearFailures()
        let result = try await GetMealPlanUseCase(repository: repository).execute(
            from: now, to: now.addingTimeInterval(3_600)
        )
        let writes = await repository.writeCount
        #expect(result == [existing])
        #expect(writes == 0)
    }

    private func makeEntry(offset: TimeInterval, prepared: Bool = false) -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(name: "Breakfast", ingredients: [
                MealIngredient(name: "Oats", quantity: 100, unit: "g")
            ]),
            scheduledDate: now.addingTimeInterval(offset),
            mealType: .breakfast,
            isPrepared: prepared
        )
    }
}
