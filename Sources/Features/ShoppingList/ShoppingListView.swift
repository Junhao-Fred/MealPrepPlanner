//  Created by Mingchen Liang on 2026/10/21.

import SwiftUI

/// Embed in the Shopping List tab using a model backed by the shared app repository.
@MainActor
struct ShoppingListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ShoppingListViewModel

    private let dataVersion: Int

    init(model: ShoppingListViewModel, dataVersion: Int = 0) {
        self.dataVersion = dataVersion
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            if let snapshot = model.snapshot {
                Section {
                    Text("\(snapshot.startDate.formatted(date: .abbreviated, time: .omitted)) – \(snapshot.endDate.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                        .font(.headline)
                    Text("Unfinished meals: \(snapshot.plannedMealCount)")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Required ingredients minus valid pantry stock. Different units are listed separately.")
                }
            }

            if model.isLoading {
                Section {
                    ProgressView(model.snapshot == nil ? "Loading shopping list…" : "Refreshing shopping list…")
                }
            }

            if let message = model.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                    if model.snapshot != nil {
                        Text("Showing the last loaded result. It may be out of date.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Retry") { Task { await model.load() } }
                        .disabled(model.isLoading)
                }
            }

            if let snapshot = model.snapshot {
                if snapshot.items.isEmpty {
                    Section {
                        if snapshot.plannedMealCount == 0 {
                            ContentUnavailableView(
                                "No Meals to Shop For", systemImage: "calendar",
                                description: Text("There are no unfinished meals in this seven-day range. Add meals in Meal Plan to calculate what to buy.")
                            )
                        } else {
                            ContentUnavailableView(
                                "Nothing to Buy", systemImage: "checkmark.circle",
                                description: Text("Your pantry covers the ingredients needed for these meals.")
                            )
                        }
                    }
                } else {
                    Section("To Buy") {
                        ForEach(snapshot.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                Text("\(item.quantity.formatted()) \(item.unit)")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } else if !model.isLoading && model.errorMessage == nil {
                Button("Load Shopping List") { Task { await model.load() } }
            }
        }
        .navigationTitle("Shopping List")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Refresh shopping list", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .refreshable { await model.load() }
        .task { await model.refreshAfterDataChange() }
        .onChange(of: dataVersion) { _, _ in
            Task { await model.refreshAfterDataChange() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }
}
