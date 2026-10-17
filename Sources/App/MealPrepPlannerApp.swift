//  Created by Junhao Huang on 2026/9/27.

import SwiftUI

@main
struct MealPrepPlannerApp: App {
    var body: some Scene {
        WindowGroup {
            DayOnePlaceholderView()
        }
    }
}

/// Shows the application shell until the four feature tabs are integrated.
private struct DayOnePlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 52))
                .accessibilityHidden(true)
            Text("MealPrepPlanner")
                .font(.title.bold())
            Text("Day 1 foundation is ready")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
