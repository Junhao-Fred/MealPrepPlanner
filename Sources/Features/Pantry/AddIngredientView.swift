//  Created by Mingchen Liang on 2026/10/20.

import SwiftUI

@MainActor
struct AddIngredientView: View {
    let model: PantryViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @State private var draft: IngredientEntryDraft
    @State private var validationMessage: String?
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?
    private let isEditing: Bool

    private enum Field: Hashable {
        case name, quantity, unit
    }

    /// Pass `editing` to change a stored batch instead of adding a new one.
    init(model: PantryViewModel, editing ingredient: Ingredient? = nil) {
        self.model = model
        isEditing = ingredient != nil
        _draft = State(initialValue: ingredient.map { IngredientEntryDraft(editing: $0) } ?? IngredientEntryDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredient") {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .quantity }
                        .accessibilityLabel("Ingredient name")
                    TextField("Quantity", text: $draft.quantityText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .quantity)
                        .accessibilityLabel("Ingredient quantity")
                    TextField("Unit, e.g. g, ml, piece", text: $draft.unit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .unit)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .accessibilityLabel("Ingredient unit")
                }
                .disabled(isSubmitting || model.isBusy)

                Section {
                    Toggle("Set expiry date", isOn: $draft.hasExpiryDate)
                    if draft.hasExpiryDate {
                        DatePicker("Expiry date", selection: $draft.expiryDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Expiry")
                } footer: {
                    Text("Leave this off if no expiry date is known. Ingredients remain valid through their expiry day.")
                }
                .disabled(isSubmitting || model.isBusy)

                if let message = validationMessage ?? model.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if isSubmitting {
                    ProgressView("Saving ingredient…")
                }
            }
            .navigationTitle(isEditing ? "Edit Ingredient" : "Add Ingredient")
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
            .onChange(of: draft.name) { _, _ in clearValidation() }
            .onChange(of: draft.quantityText) { _, _ in clearValidation() }
            .onChange(of: draft.unit) { _, _ in clearValidation() }
        }
    }

    private func clearValidation() {
        validationMessage = nil
        model.clearError()
    }

    private func save() {
        guard !isSubmitting, !model.isBusy else { return }
        let ingredient: Ingredient
        do {
            ingredient = try draft.makeIngredient(locale: locale, calendar: calendar)
        } catch {
            validationMessage = "Enter a positive quantity using '\(locale.decimalSeparator ?? ".")' for decimals, without grouping separators."
            focusedField = .quantity
            return
        }

        validationMessage = nil
        focusedField = nil
        isSubmitting = true
        Task {
            let saved = await model.save(ingredient)
            isSubmitting = false
            // Keep the draft and sheet intact on failure. A refresh warning stays on PantryView.
            if saved { dismiss() }
        }
    }
}
