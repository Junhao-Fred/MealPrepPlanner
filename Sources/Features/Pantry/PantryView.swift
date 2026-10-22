//  Created by Mingchen Liang on 2026/10/20.

import SwiftUI

/// Embed in the Pantry tab's NavigationStack and share this model with ingredient forms.
@MainActor
struct PantryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: PantryViewModel
    @State private var presentedSheet: PantrySheet?
    @State private var pendingDeletion: Ingredient?

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
        .plannerCanvas()
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
        .confirmationDialog(
            "Delete \(pendingDeletion?.name ?? "ingredient")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { ingredient in
            Button("Delete", role: .destructive) {
                Task { await model.deleteIngredient(id: ingredient.id) }
            }
        } message: { ingredient in
            Text("This removes all \(ingredient.quantity.formatted()) \(ingredient.unit) from your pantry.")
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
                    .buttonStyle(PillButtonStyle(systemImage: "plus"))
                    .disabled(model.isBusy)
                Button("Refresh") { Task { await model.load() } }
                    .disabled(model.isBusy)
            }
        }
    }

    /// A List rather than a ScrollView so each card gets the system swipe-to-delete.
    private var stockList: some View {
        List {
            if let message = model.errorMessage {
                ErrorCard(message: message, retryTitle: "Retry Refresh", retryDisabled: model.isBusy) {
                    Task { await model.load() }
                }
                .canvasRow()
            } else if model.needsReload && !model.isLoading {
                ErrorCard(message: "Refresh the pantry before using stock.", retryTitle: "Refresh", retryDisabled: model.isBusy) {
                    Task { await model.load() }
                }
                .canvasRow()
            }

            if model.isLoading {
                ProgressView("Refreshing pantry…")
                    .font(.rounded(.subheadline))
                    .frame(maxWidth: .infinity)
                    .canvasRow()
            }

            SectionHeading(
                eyebrow: "\(model.ingredients.count) in stock",
                title: "Available Stock",
                systemImage: "shippingbox"
            )
            .canvasRow()

            ForEach(model.ingredients) { ingredient in
                ingredientCard(ingredient)
                    .canvasRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            model.clearError()
                            pendingDeletion = ingredient
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                        .disabled(model.isBusy)
                    }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(18)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
        .contentMargins(.bottom, 40, for: .scrollContent)
        .animation(Theme.spring, value: model.ingredients)
        .refreshable { await model.load() }
    }

    private func ingredientCard(_ ingredient: Ingredient) -> some View {
        let soon = ExpiryRules.isExpiringSoon(ingredient.expiryDate, now: Date())
        let expired = ExpiryRules.isExpired(ingredient.expiryDate, now: Date())
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                if let expiry = ingredient.expiryDate {
                    FreshnessRing(expiry: expiry, now: Date())
                } else {
                    IconTile(
                        systemImage: "leaf.fill",
                        tint: soon || expired ? Palette.amber : Palette.sage,
                        background: soon || expired ? Palette.amberSoft : Palette.sageSoft
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(ingredient.name)
                        .font(.rounded(.headline, weight: .semibold))
                    Text("\(ingredient.quantity.formatted()) \(ingredient.unit)")
                        .font(.rounded(.title2, weight: .bold))
                        .contentTransition(.numericText())
                    expiryLabel(for: ingredient)
                        .padding(.top, 2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }

            Button {
                model.clearError()
                presentedSheet = .use(ingredient)
            } label: {
                Text("Use Ingredient")
            }
            .buttonStyle(PillButtonStyle(systemImage: "minus", prominent: false))
            .accessibilityLabel("Use \(ingredient.name)")
            .disabled(model.isBusy || model.needsReload)
        }
        .bezelCard(padding: 16)
    }

    private func addIngredient() {
        guard !model.isBusy else { return }
        model.clearError()
        presentedSheet = .add
    }

    @ViewBuilder
    private func expiryLabel(for ingredient: Ingredient) -> some View {
        if let expiry = ingredient.expiryDate {
            let date = expiry.formatted(date: .abbreviated, time: .omitted)
            if ExpiryRules.isExpired(expiry, now: Date()) {
                StatusBadge(text: "Expired \(date)", systemImage: "exclamationmark.triangle.fill", tint: .red)
            } else if Calendar.current.isDateInToday(expiry) {
                StatusBadge(text: "Expires today", systemImage: "clock.fill", tint: Palette.amber)
            } else if ExpiryRules.isExpiringSoon(expiry, now: Date()) {
                StatusBadge(text: "Use soon · \(date)", systemImage: "hourglass", tint: Palette.amber)
            } else {
                StatusBadge(text: "Expires \(date)", systemImage: "calendar")
            }
        } else {
            StatusBadge(text: "No expiry date", systemImage: "infinity")
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
            .plannerCanvas()
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
