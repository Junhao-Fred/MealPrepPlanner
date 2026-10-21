import Foundation
import Testing
@testable import MealPrepPlanner

struct ExpiryRulesTests {
    @Test("T18 expiry window includes today and excludes day three", arguments: [1, 4, 10])
    func expiryWindow(month: Int) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let day = month == 4 ? 3 : month == 10 ? 2 : 1
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day + 3)))
        let today = Ingredient(name: "Milk", quantity: 100, unit: "ml", expiryDate: start)
        let last = Ingredient(name: "Tomato", quantity: 200, unit: "g", expiryDate: end.addingTimeInterval(-1))
        let expired = Ingredient(name: "Expired", quantity: 1, unit: "g", expiryDate: start.addingTimeInterval(-1))
        let outside = Ingredient(name: "Later", quantity: 1, unit: "g", expiryDate: end)
        let undated = Ingredient(name: "Salt", quantity: 1, unit: "g")
        let empty = Ingredient(name: "Empty", quantity: 0, unit: "g", expiryDate: start)
        let negative = Ingredient(name: "Negative", quantity: -1, unit: "g", expiryDate: start)
        let repository = InMemoryMealRepository(
            ingredients: [outside, last, expired, undated, empty, negative, today],
            now: { now }
        )
        let useCase = FindIngredientsToUseSoonUseCase(repository: repository, calendar: calendar, now: { now })

        let result = try await useCase.execute()

        #expect(result == [today, last])
        #expect(ExpiryRules.isExpired(expired.expiryDate, now: now, calendar: calendar))
        #expect(!ExpiryRules.isExpired(today.expiryDate, now: now, calendar: calendar))
        #expect(!ExpiryRules.isExpired(outside.expiryDate, now: now, calendar: calendar))
        #expect(!ExpiryRules.isExpired(nil, now: now, calendar: calendar))
        #expect(!ExpiryRules.isExpiringSoon(nil, now: now, calendar: calendar))
        let writes = await repository.writeCount
        #expect(writes == 0)
    }

    @Test("T18 empty inventory returns no expiring ingredients")
    func emptyInventory() async throws {
        let now = Date(timeIntervalSince1970: 1_704_110_400)
        let repository = InMemoryMealRepository(now: { now })
        let result = try await FindIngredientsToUseSoonUseCase(repository: repository, now: { now }).execute()
        #expect(result.isEmpty)
    }

    @Test("T18 read failures reach the caller")
    func readFailure() async {
        let now = Date(timeIntervalSince1970: 1_704_110_400)
        let repository = InMemoryMealRepository(now: { now })
        await repository.fail(.read, with: .readFailed)
        let useCase = FindIngredientsToUseSoonUseCase(repository: repository, now: { now })

        do {
            _ = try await useCase.execute()
            Issue.record("Expected RepositoryError.readFailed")
        } catch let error as RepositoryError {
            #expect(error == .readFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
