import SwiftUI

@MainActor
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TodayViewModel
    private let repository: any MealPlanningRepository
    private let dataVersion: Int
    let openPlan: () -> Void

    init(repository: any MealPlanningRepository, dataVersion: Int = 0, openPlan: @escaping () -> Void) {
        self.dataVersion = dataVersion
        self.repository = repository
        self.openPlan = openPlan
        _model = State(initialValue: TodayViewModel(useCase: LoadTodayOverviewUseCase(repository: repository)))
    }

    var body: some View {
        Group {
            if model.snapshot == nil && model.errorMessage == nil {
                ProgressView("Loading meals…")
            } else if let snapshot = model.snapshot {
                List {
                    if let message = model.errorMessage {
                        Section {
                            Text(message)
                            Button("Retry") { Task { await model.load() } }
                                .frame(minHeight: 44)
                        }
                    }
                    Section {
                        Text(snapshot.date, format: .dateTime.weekday(.wide).month().day())
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Section("Next Meal") {
                        if let meal = snapshot.nextMeal {
                            mealLink(meal, date: snapshot.date)
                        } else {
                            Text("No upcoming meals planned.")
                                .foregroundStyle(.secondary)
                            Button("Open Meal Plan", action: openPlan)
                                .frame(minHeight: 44)
                        }
                    }
                    Section("Today's Meals") {
                        if snapshot.meals.isEmpty {
                            Text("No unfinished meals today.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(snapshot.meals) { meal in
                                mealLink(meal, date: snapshot.date)
                            }
                        }
                    }
                    Section("Use Soon") {
                        if snapshot.expiringIngredients.isEmpty {
                            Text("No ingredients expiring in the next three days.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(snapshot.expiringIngredients) { ingredient in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ingredient.name).font(.headline)
                                    Text("\(ingredient.quantity.formatted()) \(ingredient.unit)")
                                    if let expiry = ingredient.expiryDate {
                                        Text("Expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(ingredientAccessibilityLabel(ingredient))
                            }
                        }
                    }
                }
                .refreshable { await model.load() }
            } else {
                ContentUnavailableView {
                    Label("Unable to Load Meals", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(model.errorMessage ?? "Please try again.")
                } actions: {
                    Button("Retry") { Task { await model.load() } }
                        .frame(minHeight: 44)
                }
            }
        }
        .navigationTitle("Today")
        .navigationDestination(for: MealDetailsRoute.self) { route in
            MealDetailView(id: route.id, repository: repository) {
                await model.load()
            }
        }
        .task(id: dataVersion) { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }

    private func mealLink(_ entry: MealPlanEntry, date: Date) -> some View {
        NavigationLink(value: MealDetailsRoute(id: entry.id)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.meal.name).font(.headline)
                Text(entry.mealType.displayName)
                    .font(.subheadline)
                Text(entry.scheduledDate, format: .dateTime.month().day().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if entry.scheduledDate < date {
                    Label("Past scheduled time", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel(mealAccessibilityLabel(entry, date: date))
        .accessibilityHint("View meal details")
    }

    private func mealAccessibilityLabel(_ entry: MealPlanEntry, date: Date) -> String {
        let time = entry.scheduledDate.formatted(date: .abbreviated, time: .shortened)
        let status = entry.scheduledDate < date ? ", past scheduled time" : ""
        return "\(entry.meal.name), \(entry.mealType.displayName), \(time)\(status)"
    }

    private func ingredientAccessibilityLabel(_ ingredient: Ingredient) -> String {
        let amount = "\(ingredient.quantity.formatted()) \(ingredient.unit)"
        guard let expiry = ingredient.expiryDate else { return "\(ingredient.name), \(amount)" }
        let date = expiry.formatted(date: .abbreviated, time: .omitted)
        return "\(ingredient.name), \(amount), expires \(date)"
    }
}
