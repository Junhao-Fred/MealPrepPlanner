//  Created by Mingchen Liang on 2026/10/20.

import SwiftUI

/// Embed in the Pantry tab's NavigationStack and share this model with ingredient forms.
@MainActor
struct PantryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: PantryViewModel
    @State private var presentedSheet: PantrySheet?

    private enum PantrySheet: Identifiable {
        case add
        case use(Ingredient)

        var id: String {
            switch self {
            case .add: return "add"
            case .use(let ingredient): return ingredient.id.uuidString
            }
        }
    }

    private let dataVersion: Int

    init(model: PantryViewModel, dataVersion: Int = 0) {
        self.dataVersion = dataVersion
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if model.ingredients.isEmpty {
                emptyContent
            } else {
                stockList
            }
        }
        .navigationTitle("Pantry")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Refresh pantry", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
                Button(action: addIngredient) {
                    Label("Add ingredient", systemImage: "plus")
                }
                .disabled(model.isBusy)
            }
        }
        .task { await model.refreshAfterDataChange() }
        .onChange(of: dataVersion) { _, _ in
            Task { await model.refreshAfterDataChange() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && presentedSheet == nil {
                Task { await model.load() }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .add:
                AddIngredientView(model: model)
            case .use(let ingredient):
                PantryUsageSheet(ingredient: ingredient, model: model)
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if model.isLoading {
            ProgressView("Loading pantry…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = model.errorMessage {
            ContentUnavailableView {
                Label("Unable to Load Pantry", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await model.load() } }
                    .disabled(model.isBusy)
            }
        } else if model.needsReload {
            ContentUnavailableView {
                Label("Refresh Your Pantry", systemImage: "arrow.clockwise")
            } description: {
                Text("Load your stock to see the latest quantities.")
            } actions: {
                Button("Refresh") { Task { await model.load() } }
                    .disabled(model.isBusy)
            }
        } else {
            ContentUnavailableView {
                Label("No Pantry Stock", systemImage: "cabinet")
            } description: {
                Text("Your ingredients will appear here once added. Used-up batches are hidden.")
            } actions: {
                Button("Add Ingredient", action: addIngredient)
                    .disabled(model.isBusy)
                Button("Refresh") { Task { await model.load() } }
                    .disabled(model.isBusy)
            }
        }
    }

    private var stockList: some View {
        List {
            if let message = model.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Retry Refresh") { Task { await model.load() } }
                        .disabled(model.isBusy)
                }
            } else if model.needsReload && !model.isLoading {
                Section {
                    Text("Refresh the pantry before using stock.")
                    Button("Refresh") { Task { await model.load() } }
                        .disabled(model.isBusy)
                }
            }

            if model.isLoading {
                ProgressView("Refreshing pantry…")
            }

            Section("Available Stock") {
                ForEach(model.ingredients) { ingredient in
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ingredient.name)
                                .font(.headline)
                            Text("\(ingredient.quantity.formatted()) \(ingredient.unit)")
                            expiryLabel(for: ingredient)
                                .font(.subheadline)
                        }
                        .accessibilityElement(children: .combine)

                        Button {
                            model.clearError()
                            presentedSheet = .use(ingredient)
                        } label: {
                            Label("Use Ingredient", systemImage: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Use \(ingredient.name)")
                        .disabled(model.isBusy || model.needsReload)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .refreshable { await model.load() }
    }

    private func addIngredient() {
        guard !model.isBusy else { return }
        model.clearError()
        presentedSheet = .add
    }

    @ViewBuilder
    private func expiryLabel(for ingredient: Ingredient) -> some View {
        if let expiry = ingredient.expiryDate {
            let today = Calendar.current.startOfDay(for: Date())
            if expiry < today {
                Label("Expired \(expiry.formatted(date: .abbreviated, time: .omitted))",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if Calendar.current.isDate(expiry, inSameDayAs: today) {
                Label("Expires today", systemImage: "clock")
                    .foregroundStyle(.orange)
            } else {
                Text("Expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No expiry date")
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct PantryUsageSheet: View {
    let ingredient: Ingredient
    let model: PantryViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var quantityText = ""
    @State private var validationMessage: String?
    @State private var isSubmitting = false
    @FocusState private var quantityFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(ingredient.name) {
                    Text("Available: \(ingredient.quantity.formatted()) \(ingredient.unit)")
                    LabeledContent("Amount (\(ingredient.unit))") {
                        TextField("0", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($quantityFocused)
                            .accessibilityLabel("Amount to use in \(ingredient.unit)")
                            .disabled(isSubmitting || model.isBusy)
                    }
                }

                if let message = validationMessage ?? model.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView("Updating stock…")
                        } else {
                            Text("Confirm Usage")
                        }
                    }
                    .disabled(isSubmitting || model.isBusy || quantityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Enter the amount actually used. Stock changes only after you confirm.")
                }
            }
            .navigationTitle("Use Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting || model.isBusy)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { quantityFocused = false }
                }
            }
            .interactiveDismissDisabled(isSubmitting || model.isBusy)
            .onChange(of: quantityText) { _, _ in
                validationMessage = nil
                model.clearError()
            }
        }
    }

    private func submit() {
        guard !isSubmitting, !model.isBusy else { return }
        guard let quantity = PantryQuantityParser.parse(quantityText, locale: locale) else {
            validationMessage = "Enter a positive number using '\(locale.decimalSeparator ?? ".")' for decimals, without grouping separators."
            return
        }
        guard quantity <= ingredient.quantity else {
            validationMessage = "The amount exceeds the available stock."
            return
        }

        validationMessage = nil
        quantityFocused = false
        isSubmitting = true
        Task {
            // The use case rechecks current stock; this sheet's snapshot is only an input hint.
            let succeeded = await model.useIngredient(id: ingredient.id, quantity: quantity)
            isSubmitting = false
            if succeeded { dismiss() }
        }
    }
}
