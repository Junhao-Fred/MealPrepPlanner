//  Created by Mingchen Liang on 2026/10/21.

import SwiftUI

/// Embed in the Meal Plan tab's NavigationStack using the app's shared repository.
@MainActor
struct MealPlanView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: MealPlanViewModel
    @State private var showingAddMeal = false
    @State private var pendingDeletion: MealPlanEntry?
    @State private var editingEntry: MealPlanEntry?

    private let repository: any MealPlanningRepository
    private let dataVersion: Int

    /// `repository` opens meal details; pass the same one the model uses.
    init(model: MealPlanViewModel, repository: any MealPlanningRepository, dataVersion: Int = 0) {
        self.repository = repository
        self.dataVersion = dataVersion
        _model = State(initialValue: model)
    }

    /// A List rather than a ScrollView so each meal gets the system swipe-to-delete.
    var body: some View {
        List {
            rangeCard
                .canvasRow()

            if model.isLoading {
                ProgressView(model.hasLoaded ? "Refreshing meal plan…" : "Loading meal plan…")
                    .font(.rounded(.subheadline))
                    .frame(maxWidth: .infinity)
                    .canvasRow()
            }

            if let message = model.errorMessage {
                ErrorCard(message: message, retryDisabled: model.isBusy) { Task { await model.load() } }
                    .canvasRow()
            }

            if model.days.isEmpty && !model.isLoading && model.errorMessage == nil {
                Group {
                    if model.hasLoaded {
                        VStack(spacing: 4) {
                            ContentUnavailableView("No Meals Planned", systemImage: "calendar")
                            Button("Add Meal", action: addMeal)
                                .buttonStyle(PillButtonStyle(systemImage: "plus"))
                                .disabled(model.isBusy)
                        }
                        .bezelCard(padding: 20)
                    } else {
                        Button("Load Meal Plan") { Task { await model.load() } }
                            .buttonStyle(PillButtonStyle(systemImage: "arrow.clockwise"))
                    }
                }
                .canvasRow()
            }

            ForEach(model.days) { day in
                dayHeading(day.date)
                    .padding(.top, 14)
                    .canvasRow()
                ForEach(day.entries) { entry in
                    mealRow(entry)
                        .background {
                            // Hidden link: the row opens details without the list's own chevron.
                            NavigationLink(value: MealDetailsRoute(id: entry.id)) { EmptyView() }
                                .opacity(0)
                        }
                        .canvasRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                model.clearError()
                                pendingDeletion = entry
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                            .disabled(model.isBusy)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if !entry.isPrepared {
                                Button {
                                    model.clearError()
                                    editingEntry = entry
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Palette.sage)
                                .disabled(model.isBusy)
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(12)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
        .contentMargins(.bottom, 40, for: .scrollContent)
        .animation(Theme.spring, value: model.days)
        .plannerCanvas()
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
        .task { await model.refreshAfterDataChange() }
        .onChange(of: dataVersion) { _, _ in
            Task { await model.refreshAfterDataChange() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !showingAddMeal { Task { await model.load() } }
        }
        .sheet(isPresented: $showingAddMeal) { AddMealView(model: model) }
        .sheet(item: $editingEntry) { entry in AddMealView(model: model, editing: entry) }
        .navigationDestination(for: MealDetailsRoute.self) { route in
            MealDetailView(id: route.id, repository: repository) {
                await model.load()
            }
        }
        .confirmationDialog(
            "Delete \(pendingDeletion?.meal.name ?? "meal")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { entry in
            Button("Delete", role: .destructive) {
                Task { await model.deleteEntry(id: entry.id) }
            }
        } message: { entry in
            Text("This removes the \(entry.mealType.displayName.lowercased()) on \(entry.scheduledDate.formatted(date: .abbreviated, time: .shortened)) from your plan and shopping list.")
        }
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

    private var rangeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Seven-day view", systemImage: "calendar")
            WeekDotMatrix(days: weekDots)
                .padding(.vertical, 4)
            DatePicker("Starting date", selection: startDate, displayedComponents: .date)
                .font(.rounded(.body, weight: .medium))
                .disabled(model.isBusy)
            Text("Seven days through \(model.lastDay.formatted(date: .abbreviated, time: .omitted)), including prepared meals.")
                .font(.rounded(.footnote))
                .foregroundStyle(.secondary)
            Button("Start from Today") { Task { await model.showToday() } }
                .buttonStyle(PillButtonStyle(systemImage: "arrow.uturn.backward", prominent: false))
                .disabled(model.isBusy)
        }
        .bezelCard()
    }

    private var weekDots: [WeekDotMatrix.Day] {
        let calendar = Calendar.current
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: model.rangeStart) else { return nil }
            let entries = model.days.first { calendar.isDate($0.date, inSameDayAs: date) }?.entries ?? []
            let prepared = entries.filter(\.isPrepared).count
            return WeekDotMatrix.Day(date: date, prepared: prepared, planned: entries.count - prepared)
        }
    }

    private func dayHeading(_ date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(date, format: .dateTime.weekday(.wide))
                .font(.rounded(.title3, weight: .bold))
            Text(date, format: .dateTime.day().month().year())
                .font(.rounded(.subheadline))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if Calendar.current.isDateInToday(date) {
                StatusBadge(text: "Today", systemImage: "sun.max.fill", tint: Palette.sage)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func mealRow(_ entry: MealPlanEntry) -> some View {
        HStack(spacing: 14) {
            MealTypeIcon(type: entry.mealType)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.meal.name)
                    .font(.rounded(.headline, weight: .semibold))
                Text("\(entry.mealType.displayName) · \(entry.scheduledDate.formatted(date: .omitted, time: .shortened))")
                    .font(.rounded(.subheadline))
                    .foregroundStyle(.secondary)
                if entry.isPrepared {
                    StatusBadge(text: "Prepared", systemImage: "checkmark.circle.fill", tint: Palette.sage)
                } else {
                    StatusBadge(text: "Planned", systemImage: "clock")
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .bezelCard(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityHint("View meal details")
    }
}
