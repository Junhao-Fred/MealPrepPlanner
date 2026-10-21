import Foundation

struct FindIngredientsToUseSoonUseCase: Sendable {
    let repository: any MealPlanningRepository
    var calendar: Calendar = .current
    var now: @Sendable () -> Date = { Date() }

    func execute() async throws -> [Ingredient] {
        let date = now()
        let ingredients = try await repository.fetchAvailableIngredients()
        return ingredients.filter {
            $0.isAvailable && ExpiryRules.isExpiringSoon($0.expiryDate, now: date, calendar: calendar)
        }.sorted {
            if $0.expiryDate != $1.expiryDate {
                return ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture)
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
