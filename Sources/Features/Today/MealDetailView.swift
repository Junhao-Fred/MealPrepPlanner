import SwiftUI

@MainActor
struct MealDetailView: View {
    @State private var model: MealDetailViewModel
    let onPrepared: () async -> Void

    init(
        id: UUID,
        repository: any MealPlanningRepository,
        onPrepared: @escaping () async -> Void
    ) {
        _model = State(initialValue: MealDetailViewModel(
            id: id, useCase: MealDetailsUseCase(repository: repository)
        ))
        self.onPrepared = onPrepared
    }

    var body: some View {
        Group {
            if model.entry == nil && model.errorMessage == nil {
                ProgressView("Loading meal…")
            } else if let entry = model.entry {
                List {
                    Section("Meal") {
                        Text(entry.meal.name).font(.title2.bold())
                        Text(entry.mealType.displayName)
                        Text(entry.scheduledDate, format: .dateTime.month().day().year().hour().minute())
                    }
                    Section("Ingredients") {
                        if entry.meal.ingredients.isEmpty {
                            Text("No ingredients listed.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(entry.meal.ingredients) { ingredient in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ingredient.name)
                                    Text("\(ingredient.quantity.formatted()) \(ingredient.unit)")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    Section {
                        if let message = model.errorMessage {
                            Text(message)
                                .accessibilityLabel("Error: \(message)")
                        }
                        if entry.isPrepared {
                            Label("Prepared", systemImage: "checkmark.circle.fill")
                        } else {
                            Button {
                                Task {
                                    if await model.markPrepared() { await onPrepared() }
                                }
                            } label: {
                                if model.isSaving {
                                    ProgressView("Saving…")
                                } else {
                                    Text("Mark as Prepared")
                                }
                            }
                            .disabled(model.isSaving || model.isLoading)
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Meal Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(model.errorMessage ?? "This meal could not be found.")
                } actions: {
                    Button("Retry") { Task { await model.load() } }
                }
            }
        }
        .navigationTitle("Meal Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }
}
