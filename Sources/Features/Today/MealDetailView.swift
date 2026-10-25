import SwiftUI

struct MealDetailsRoute: Hashable {
    let id: UUID
}

@MainActor
struct MealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: MealDetailViewModel
    @State private var confirmingUndo = false
    @State private var confirmingDelete = false
    /// Called after the meal is prepared, un-prepared or deleted.
    let onChange: () async -> Void

    init(
        id: UUID,
        repository: any MealPlanningRepository,
        onChange: @escaping () async -> Void
    ) {
        _model = State(initialValue: MealDetailViewModel(
            id: id,
            useCase: MarkMealPreparedUseCase(repository: repository),
            deleteUseCase: DeleteMealPlanEntryUseCase(repository: repository)
        ))
        self.onChange = onChange
    }

    var body: some View {
        Group {
            if model.entry == nil && model.errorMessage == nil {
                ProgressView("Loading meal…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let entry = model.entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(entry)
                        ingredients(entry)
                        preparation(entry)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                    .animation(Theme.spring, value: entry.isPrepared)
                }
                .sensoryFeedback(.success, trigger: entry.isPrepared)
            } else {
                ContentUnavailableView {
                    Label("Meal Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(model.errorMessage ?? "This meal could not be found.")
                } actions: {
                    Button("Retry") { Task { await model.load() } }
                        .buttonStyle(PillButtonStyle(systemImage: "arrow.clockwise"))
                }
            }
        }
        .plannerCanvas()
        .navigationTitle("Meal Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private func header(_ entry: MealPlanEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                MealTypeIcon(type: entry.mealType)
                Spacer()
                if entry.isPrepared {
                    StatusBadge(text: "Prepared", systemImage: "checkmark.circle.fill", tint: Palette.sage)
                } else {
                    StatusBadge(text: "Planned", systemImage: "clock")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.meal.name)
                    .font(.rounded(.title, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(entry.mealType.displayName)
                    .font(.rounded(.headline, weight: .medium))
                    .foregroundStyle(Palette.sage)
                Label(
                    entry.scheduledDate.formatted(.dateTime.weekday(.wide).month().day().year().hour().minute()),
                    systemImage: "calendar"
                )
                .font(.rounded(.subheadline))
                .foregroundStyle(.secondary)
            }
        }
        .bezelCard(padding: 22)
        .revealOnScroll()
    }

    private func ingredients(_ entry: MealPlanEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(eyebrow: "Recipe", title: "Ingredients", systemImage: "basket")
            VStack(spacing: 0) {
                if entry.meal.ingredients.isEmpty {
                    Text("No ingredients listed.")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(entry.meal.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        if index > 0 { Divider().overlay(Palette.hairline) }
                        HStack {
                            Text(ingredient.name)
                                .font(.rounded(.body, weight: .medium))
                            Spacer(minLength: 12)
                            Text("\(ingredient.quantity.formatted()) \(ingredient.unit)")
                                .font(.rounded(.body, weight: .semibold))
                                .foregroundStyle(Palette.sage)
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(ingredient.name), \(ingredient.quantity.formatted()) \(ingredient.unit)")
                    }
                }
            }
            .bezelCard(padding: 18)
        }
        .revealOnScroll()
    }

    @ViewBuilder
    private func preparation(_ entry: MealPlanEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(Palette.amber)
                    .accessibilityLabel("Error: \(message)")
            }
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle.fill")
                    .font(.rounded(.subheadline, weight: .medium))
                    .foregroundStyle(Palette.sage)
            }
            if entry.isPrepared {
                Label("Prepared", systemImage: "checkmark.circle.fill")
                    .font(.rounded(.headline, weight: .semibold))
                    .foregroundStyle(Palette.sage)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Palette.sageSoft, in: Capsule())
                    .accessibilityLabel("Meal prepared")
                Button("Mark as Not Prepared") { confirmingUndo = true }
                    .buttonStyle(PillButtonStyle(systemImage: "arrow.uturn.backward", prominent: false, fillsWidth: true))
                    .disabled(model.isSaving || model.isLoading)
            } else {
                Text("Marking it prepared takes the ingredients out of your pantry.")
                    .font(.rounded(.footnote))
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        if await model.markPrepared() { await onChange() }
                    }
                } label: {
                    if model.isSaving {
                        ProgressView("Saving…")
                    } else {
                        Text("Mark as Prepared")
                    }
                }
                .buttonStyle(PillButtonStyle(systemImage: "checkmark", fillsWidth: true))
                .disabled(model.isSaving || model.isLoading)
            }
            if model.canDelete {
                Button("Delete Meal", role: .destructive) { confirmingDelete = true }
                    .font(.rounded(.body, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(model.isSaving || model.isLoading)
            }
        }
        .confirmationDialog("Mark as not prepared?", isPresented: $confirmingUndo, titleVisibility: .visible) {
            Button("Add Ingredients Back to Pantry") {
                Task { if await model.undoPrepared(returningIngredients: true) { await onChange() } }
            }
            Button("Keep Pantry As Is") {
                Task { if await model.undoPrepared(returningIngredients: false) { await onChange() } }
            }
        } message: {
            Text("Choose whether the recipe's ingredients go back into your pantry.")
        }
        .confirmationDialog("Delete \(entry.meal.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    if await model.delete() {
                        await onChange()
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This removes the meal from your plan and shopping list. Pantry stock is not changed.")
        }
    }
}
