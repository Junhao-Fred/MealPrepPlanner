import SwiftUI

@MainActor
struct RootTabView: View {
    @State private var selection: AppTab = .today
    let repository: any MealPlanningRepository

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    if tab == .today {
                        TodayView(repository: repository) { selection = .plan }
                    } else {
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

#Preview {
    RootTabView(repository: MockMealPlanningRepository.demo())
}
