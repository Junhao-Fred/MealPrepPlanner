import SwiftUI

@MainActor
struct RootTabView: View {
    @State private var selection: AppTab = .today
    var repository: (any MealPlanningRepository)? = nil
    var changes: DataChangeTracker? = nil

    private var dataVersion: Int { changes?.version ?? 0 }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    switch (tab, repository) {
                    case (.today, let repository?):
                        TodayView(repository: repository, dataVersion: dataVersion) { selection = .plan }
                    case (.plan, let repository?):
                        MealPlanTab(repository: repository, dataVersion: dataVersion)
                    case (.pantry, let repository?):
                        PantryTab(repository: repository, dataVersion: dataVersion)
                    case (.shopping, let repository?):
                        ShoppingListTab(repository: repository, dataVersion: dataVersion)
                    default:
                        FeaturePlaceholderView(tab: tab)
                            .navigationTitle(tab.title)
                    }
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case plan
    case pantry
    case shopping

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .plan: "Meal Plan"
        case .pantry: "Pantry"
        case .shopping: "Shopping List"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .plan: "calendar"
        case .pantry: "cabinet"
        case .shopping: "cart"
        }
    }

    var placeholderMessage: String {
        switch self {
        case .today: "Your next meal will appear here."
        case .plan: "Your meal schedule will appear here."
        case .pantry: "Your available ingredients will appear here."
        case .shopping: "Ingredients you need to buy will appear here."
        }
    }
}

/// Owns the view model so switching tabs keeps it instead of creating a new one on every redraw.
private struct MealPlanTab: View {
    @State private var model: MealPlanViewModel

    let dataVersion: Int

    init(repository: any MealPlanningRepository, dataVersion: Int) {
        self.dataVersion = dataVersion
        _model = State(initialValue: MealPlanViewModel(repository: repository))
    }

    var body: some View {
        MealPlanView(model: model, dataVersion: dataVersion)
    }
}

private struct PantryTab: View {
    @State private var model: PantryViewModel

    let dataVersion: Int

    init(repository: any MealPlanningRepository, dataVersion: Int) {
        self.dataVersion = dataVersion
        _model = State(initialValue: PantryViewModel(repository: repository))
    }

    var body: some View {
        PantryView(model: model, dataVersion: dataVersion)
    }
}

private struct ShoppingListTab: View {
    @State private var model: ShoppingListViewModel
    let dataVersion: Int

    init(repository: any MealPlanningRepository, dataVersion: Int) {
        self.dataVersion = dataVersion
        _model = State(initialValue: ShoppingListViewModel(repository: repository))
    }

    var body: some View {
        ShoppingListView(model: model, dataVersion: dataVersion)
    }
}

private struct FeaturePlaceholderView: View {
    let tab: AppTab

    var body: some View {
        ContentUnavailableView(
            tab.title,
            systemImage: tab.systemImage,
            description: Text(tab.placeholderMessage)
        )
    }
}

#if DEBUG
#Preview("Today") {
    let dependencies = AppDependencies.preview()
    RootTabView(repository: dependencies.repository, changes: dependencies.changes)
}

#Preview("Empty") {
    let dependencies = AppDependencies.preview(repository: InMemoryMealRepository())
    RootTabView(repository: dependencies.repository, changes: dependencies.changes)
}
#endif
