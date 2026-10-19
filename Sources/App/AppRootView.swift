//  Created by Junhao Huang on 2026/10/19.

import SwiftUI

/// Opens the data store before showing the app and offers a retry instead of crashing when it cannot.
struct AppRootView<Content: View>: View {
    private enum LoadState {
        case loading
        case ready(AppDependencies)
        case failed
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var state = LoadState.loading
    private let makeDependencies: @MainActor () async throws -> AppDependencies
    private let content: () -> Content

    init(
        makeDependencies: @escaping @MainActor () async throws -> AppDependencies = { try await AppDependencies.live() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.makeDependencies = makeDependencies
        self.content = content
    }

    var body: some View {
        switch state {
        case .loading:
            ProgressView("Opening your meal plans…")
                .task { await load() }
        case .ready(let dependencies):
            content()
                .environment(dependencies)
                .task { await dependencies.refreshWidgetSnapshot() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await dependencies.refreshWidgetSnapshot() }
                }
        case .failed:
            ContentUnavailableView {
                Label("Can't Open Your Data", systemImage: "exclamationmark.triangle")
            } description: {
                Text("MealPrep Planner couldn't open its database. Try again, and restart the app if this keeps happening.")
            } actions: {
                Button("Try Again") { state = .loading }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func load() async {
        do {
            state = .ready(try await makeDependencies())
        } catch {
            state = .failed
        }
    }
}
