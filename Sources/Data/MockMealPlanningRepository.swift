import Foundation

actor MockMealPlanningRepository: MealPlanningRepository {
    enum Failure: Error {
        case simulated
        case entryNotFound
    }

    private var meals: [UUID: Meal] = [:]
    private var entries: [UUID: MealPlanEntry] = [:]
    private var ingredients: [UUID: Ingredient] = [:]
    private let now: @Sendable () -> Date
    private var shouldFail = false
    private var shouldFailWrites = false
    private(set) var updateCount = 0

    init(
        entries: [MealPlanEntry] = [],
        ingredients: [Ingredient] = [],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        for entry in entries {
            self.entries[entry.id] = entry
            self.meals[entry.meal.id] = entry.meal
        }
        for ingredient in ingredients {
            self.ingredients[ingredient.id] = ingredient
        }
        self.now = now
    }

    func setFailure(_ enabled: Bool) {
        shouldFail = enabled
    }

    func setWriteFailure(_ enabled: Bool) {
        shouldFailWrites = enabled
    }

    func saveMeal(_ meal: Meal) async throws {
        try checkWriteFailure()
        meals[meal.id] = meal
        for id in Array(entries.keys) where entries[id]?.meal.id == meal.id {
            entries[id]?.meal = meal
        }
    }

    func saveIngredient(_ ingredient: Ingredient) async throws {
        try checkWriteFailure()
        ingredients[ingredient.id] = ingredient
    }

    func saveMealPlanEntry(_ entry: MealPlanEntry) async throws {
        try await savePlannedMeal(entry)
    }

    func savePlannedMeal(_ entry: MealPlanEntry) async throws {
        try checkWriteFailure()
        meals[entry.meal.id] = entry.meal
        entries[entry.id] = entry
        for id in Array(entries.keys) where entries[id]?.meal.id == entry.meal.id {
            entries[id]?.meal = entry.meal
        }
    }

    func fetchUpcomingMeals() async throws -> [MealPlanEntry] {
        try checkFailure()
        let date = now()
        return sorted(entries.values.filter { !$0.isPrepared && $0.scheduledDate >= date })
    }

    func fetchMealPlanEntries(
        from start: Date,
        to end: Date,
        includingPrepared includePrepared: Bool
    ) async throws -> [MealPlanEntry] {
        try checkFailure()
        return sorted(entries.values.filter {
            $0.scheduledDate >= start && $0.scheduledDate < end &&
            (includePrepared || !$0.isPrepared)
        })
    }

    func fetchAvailableIngredients() async throws -> [Ingredient] {
        try checkFailure()
        return ingredients.values.filter { $0.quantity > 0 }.sorted {
            if $0.name == $1.name { return $0.id.uuidString < $1.id.uuidString }
            return $0.name < $1.name
        }
    }

    func fetchIngredientsExpiring(before date: Date) async throws -> [Ingredient] {
        try await fetchAvailableIngredients().filter {
            guard let expiry = $0.expiryDate else { return false }
            return expiry < date
        }
    }

    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws {
        try checkWriteFailure()
        guard entries[entry.id] != nil else { throw Failure.entryNotFound }
        entries[entry.id] = entry
        updateCount += 1
    }

    private func checkFailure() throws {
        if shouldFail { throw Failure.simulated }
    }

    private func checkWriteFailure() throws {
        try checkFailure()
        if shouldFailWrites { throw Failure.simulated }
    }

    private func sorted(_ values: [MealPlanEntry]) -> [MealPlanEntry] {
        values.sorted {
            if $0.scheduledDate == $1.scheduledDate {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.scheduledDate < $1.scheduledDate
        }
    }

    static func demo(now: Date = Date(), calendar: Calendar = .current) -> MockMealPlanningRepository {
        let start = calendar.startOfDay(for: now)
        let oats = Meal(name: "Berry Oats", ingredients: [
            MealIngredient(name: "Oats", quantity: 80, unit: "g"),
            MealIngredient(name: "Milk", quantity: 200, unit: "ml")
        ])
        let pasta = Meal(name: "Tomato Pasta", ingredients: [
            MealIngredient(name: "Pasta", quantity: 150, unit: "g"),
            MealIngredient(name: "Tomato", quantity: 200, unit: "g")
        ])
        return MockMealPlanningRepository(
            entries: [
                MealPlanEntry(meal: oats, scheduledDate: start, mealType: .breakfast),
                MealPlanEntry(
                    meal: pasta,
                    scheduledDate: now.addingTimeInterval(3_600),
                    mealType: .dinner
                )
            ],
            ingredients: [Ingredient(name: "Milk", quantity: 500, unit: "ml", expiryDate: start)]
        )
    }
}
