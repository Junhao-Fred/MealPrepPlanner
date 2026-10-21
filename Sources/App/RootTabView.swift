import SwiftUI

@MainActor
struct RootTabView: View {
    @State private var selection: AppTab = .today
    var repository: (any MealPlanningRepository)? = nil

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    switch (tab, repository) {
                    case (.today, let repository?):
                        TodayView(repository: repository) { selection = .plan }
                    case (.plan, let repository?):
                        MealPlanTab(repository: repository)
                    case (.pantry, let repository?):
                        PantryTab(repository: repository)
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

    init(repository: any MealPlanningRepository) {
        _model = State(initialValue: MealPlanViewModel(repository: repository))
    }

    var body: some View {
        MealPlanView(model: model)
    }
}

private struct PantryTab: View {
    @State private var model: PantryViewModel

    init(repository: any MealPlanningRepository) {
        _model = State(initialValue: PantryViewModel(repository: repository))
    }

    var body: some View {
        PantryView(model: model)
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
    RootTabView(repository: InMemoryMealRepository.preview())
}

#Preview("Empty") {
    RootTabView(repository: InMemoryMealRepository())
}
#endif
