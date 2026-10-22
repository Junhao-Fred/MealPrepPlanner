//  Created by Mingchen Liang on 2026/10/21.

import SwiftUI

@MainActor
struct AddMealView: View {
    let model: MealPlanViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var draft: MealEntryDraft
    @State private var validationMessage: String?
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case mealName
        case ingredientName(UUID)
        case quantity(UUID)
        case unit(UUID)
    }

    init(model: MealPlanViewModel) {
        self.model = model
        _draft = State(initialValue: model.makeDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Meal name", text: $draft.name)
                        .focused($focusedField, equals: .mealName)
                        .accessibilityLabel("Meal name")
                    Picker("Meal type", selection: $draft.mealType) {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    DatePicker("Scheduled for", selection: $draft.scheduledDate,
                               in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
                .disabled(isSubmitting || model.isBusy)

                Section {
                    ForEach($draft.ingredients) { $row in
                        let rowNumber = ingredientNumber(for: row.id)
                        let rowLabel = ingredientLabel(for: row, number: rowNumber)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Ingredient \(rowNumber)")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            TextField("Ingredient name", text: $row.name)
                                .focused($focusedField, equals: .ingredientName(row.id))
                                .submitLabel(.next)
                                .onSubmit { focusedField = .quantity(row.id) }
                                .accessibilityLabel("Ingredient \(rowNumber) name")
                            TextField("Quantity", text: $row.quantityText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .quantity(row.id))
                                .accessibilityLabel("\(rowLabel) quantity")
                            TextField("Unit, e.g. g, ml, piece", text: $row.unit)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .unit(row.id))
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil }
                                .accessibilityLabel("\(rowLabel) unit")
                            Button(role: .destructive) {
                                focusedField = nil
                                let id = row.id
                                draft.ingredients.removeAll { $0.id == id }
                            } label: {
                                Label("Remove Ingredient", systemImage: "trash")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(rowLabel)")
                        }
                        .padding(.vertical, 4)
                    }
                    Button {
                        let row = MealIngredientDraft()
                        draft.ingredients.append(row)
                        focusedField = .ingredientName(row.id)
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Recipe Ingredients")
                } footer: {
                    Text("Add at least one ingredient. Quantities describe one preparation of this meal.")
                }
                .disabled(isSubmitting || model.isBusy)

                if let message = validationMessage ?? model.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                if isSubmitting { ProgressView("Saving meal…") }
            }
            .navigationTitle("Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .plannerCanvas()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
                        model.clearError()
                        dismiss()
                    }
                    .disabled(isSubmitting || model.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isSubmitting || model.isBusy)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .interactiveDismissDisabled(isSubmitting || model.isBusy)
            .onChange(of: draft) { _, _ in clearValidation() }
        }
    }

    private func ingredientNumber(for id: UUID) -> Int {
        (draft.ingredients.firstIndex { $0.id == id } ?? 0) + 1
    }

    private func ingredientLabel(for row: MealIngredientDraft, number: Int) -> String {
        let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Ingredient \(number)" : "Ingredient \(number), \(name)"
    }

    private func clearValidation() {
        validationMessage = nil
        model.clearError()
    }

    private func save() {
        guard !isSubmitting, !model.isBusy else { return }
        let entry: MealPlanEntry
        do {
            entry = try draft.makeEntry(locale: locale)
        } catch MealEntryDraftError.invalidQuantity(let row) {
            validationMessage = "Ingredient \(row) needs a positive quantity. Use '\(locale.decimalSeparator ?? ".")' for decimals, without grouping separators."
            if draft.ingredients.indices.contains(row - 1) {
                focusedField = .quantity(draft.ingredients[row - 1].id)
            }
            return
        } catch {
            validationMessage = "Check the ingredient quantities."
            return
        }
        clearValidation()
        focusedField = nil
        isSubmitting = true
        Task {
            let saved = await model.save(entry)
            isSubmitting = false
            if saved { dismiss() }
        }
    }
}
