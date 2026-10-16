import Foundation

struct TodayMealsSnapshot {
    let date: Date
    let nextMeal: MealPlanEntry?
    let meals: [MealPlanEntry]
    let expiringIngredients: [Ingredient]
}

struct TodayMealsUseCase {
    let repository: any MealPlanningRepository
    var calendar: Calendar = .current
    var now: @Sendable () -> Date = { Date() }

    func execute() async throws -> TodayMealsSnapshot {
        let date = now()
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start),
              let expiryEnd = calendar.date(byAdding: .day, value: 3, to: start) else {
            throw MealDetailsError.invalidDate
        }
        let meals = try await repository.fetchMealPlanEntries(
            from: start, to: end, includingPrepared: false
        )
        let upcoming = try await repository.fetchMealPlanEntries(
            from: date, to: .distantFuture, includingPrepared: false
        )
        let ingredients = try await repository.fetchIngredientsExpiring(before: expiryEnd)
        return TodayMealsSnapshot(
            date: date,
            nextMeal: upcoming.first,
            meals: meals,
            expiringIngredients: ingredients.filter {
                guard let expiry = $0.expiryDate else { return false }
                return $0.quantity > 0 && expiry >= start && expiry < expiryEnd
            }
        )
    }
}

struct MealDetailsRoute: Hashable {
    let id: UUID
}

enum MealDetailsError: LocalizedError {
    case notFound
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .notFound: "This meal plan is no longer available."
        case .invalidDate: "The current date could not be loaded."
        }
    }
}

struct MealDetailsUseCase {
    let repository: any MealPlanningRepository

    func fetch(id: UUID) async throws -> MealPlanEntry {
        let entries = try await repository.fetchMealPlanEntries(
            from: .distantPast, to: .distantFuture, includingPrepared: true
        )
        guard let entry = entries.first(where: { $0.id == id }) else {
            throw MealDetailsError.notFound
        }
        return entry
    }

    func markPrepared(id: UUID) async throws -> MealPlanEntry {
        var entry = try await fetch(id: id)
        if !entry.isPrepared {
            entry.isPrepared = true
            try await repository.updateMealPlanEntry(entry)
        }
        return entry
    }
}
