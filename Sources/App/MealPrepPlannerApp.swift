//  Created by Junhao Huang on 2026/9/27.

import SwiftUI

@main
struct MealPrepPlannerApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

private struct HomeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 52))
                .accessibilityHidden(true)
            Text("MealPrepPlanner")
                .font(.title.bold())
            Text("Plan meals for the week")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
