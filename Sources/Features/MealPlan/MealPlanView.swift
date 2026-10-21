//  Created by Mingchen Liang on 2026/10/21.

import SwiftUI

/// Embed in the Meal Plan tab's NavigationStack using the app's shared repository.
@MainActor
struct MealPlanView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: MealPlanViewModel
    @State private var showingAddMeal = false

    init(model: MealPlanViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            Section {
                DatePicker("Starting date", selection: startDate, displayedComponents: .date)
                    .disabled(model.isBusy)
                Button("Start from Today") { Task { await model.showToday() } }
                    .disabled(model.isBusy)
            } footer: {
                Text("Seven days through \(model.lastDay.formatted(date: .abbreviated, time: .omitted)), including prepared meals.")
            }

            if model.isLoading {
                Section {
                    ProgressView(model.hasLoaded ? "Refreshing meal plan…" : "Loading meal plan…")
                }
            }

            if let message = model.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Retry") { Task { await model.load() } }
                        .disabled(model.isBusy)
                }
            }

            if model.days.isEmpty && !model.isLoading && model.errorMessage == nil {
                Section {
                    if model.hasLoaded {
                        ContentUnavailableView(
                            "No Meals Planned",
                            systemImage: "calendar",
                            description: Text("There are no meals in this date range. Choose another starting date to browse your plans.")
                        )
                        Button("Add Meal", action: addMeal)
                            .disabled(model.isBusy)
                    } else {
                        Button("Load Meal Plan") { Task { await model.load() } }
                    }
                }
            }

            ForEach(model.days) { day in
                Section {
                    ForEach(day.entries) { entry in
                        mealRow(entry)
                    }
                } header: {
                    Text(day.date, format: .dateTime.weekday(.wide).day().month().year())
                }
            }
        }
        .navigationTitle("Meal Plan")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Refresh meal plan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
                Button(action: addMeal) {
                    Label("Add meal", systemImage: "plus")
                }
                .disabled(model.isBusy)
            }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !showingAddMeal { Task { await model.load() } }
        }
        .sheet(isPresented: $showingAddMeal) { AddMealView(model: model) }
    }

    private func addMeal() {
        guard !model.isBusy else { return }
        model.clearError()
        showingAddMeal = true
    }

    private var startDate: Binding<Date> {
        Binding(
            get: { model.rangeStart },
            set: { date in Task { await model.showRange(starting: date) } }
        )
    }

    private func mealRow(_ entry: MealPlanEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.meal.name)
                .font(.headline)
            Text("\(entry.mealType.displayName) · \(entry.scheduledDate.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(
                entry.isPrepared ? "Prepared" : "Planned",
                systemImage: entry.isPrepared ? "checkmark.circle.fill" : "clock"
            )
            .font(.subheadline)
            .foregroundStyle(entry.isPrepared ? Color.green : Color.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
