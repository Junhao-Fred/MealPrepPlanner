//  Created by Mingchen Liang on 2026/10/20.

import SwiftUI

/// Embed in the Pantry tab's NavigationStack and share this model with ingredient forms.
@MainActor
struct PantryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: PantryViewModel
    @State private var presentedSheet: PantrySheet?
    @State private var pendingDeletion: PantryItemGroup?
    @State private var choosingBatchToEdit: PantryItemGroup?

    private enum PantrySheet: Identifiable {
        case add
        case edit(Ingredient)
        case use(PantryItemGroup)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let ingredient): return "edit-\(ingredient.id.uuidString)"
            case .use(let group): return "use-\(group.id.name)-\(group.id.unit)"
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
            case .edit(let ingredient):
                AddIngredientView(model: model, editing: ingredient)
            case .use(let group):
                PantryUsageSheet(group: group, model: model)
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
        ) { group in
            Button("Delete", role: .destructive) {
                Task { await model.deleteGroup(group) }
            }
        } message: { group in
            let batches = group.batches.count == 1 ? "" : " in \(group.batches.count) batches"
            Text("This removes all \(group.quantity.formatted()) \(group.unit) of \(group.name)\(batches) from your pantry.")
        }
        .confirmationDialog(
            "Edit which batch?",
            isPresented: Binding(
                get: { choosingBatchToEdit != nil },
                set: { if !$0 { choosingBatchToEdit = nil } }
            ),
            titleVisibility: .visible,
            presenting: choosingBatchToEdit
        ) { group in
            ForEach(group.batches) { batch in
                Button(batchSummary(batch)) { presentedSheet = .edit(batch) }
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
                eyebrow: "\(model.groups.count) in stock",
                title: "Available Stock",
                systemImage: "shippingbox"
            )
            .canvasRow()

            ForEach(model.groups) { group in
                ingredientCard(group)
                    .canvasRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            model.clearError()
                            pendingDeletion = group
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                        .disabled(model.isBusy)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            model.clearError()
                            if group.batches.count == 1, let batch = group.batches.first {
                                presentedSheet = .edit(batch)
                            } else {
                                choosingBatchToEdit = group
                            }
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Palette.sage)
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

    private func ingredientCard(_ group: PantryItemGroup) -> some View {
        let expiry = group.earliestExpiry
        let soon = ExpiryRules.isExpiringSoon(expiry, now: Date())
        let expired = ExpiryRules.isExpired(expiry, now: Date())
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                if let expiry {
                    FreshnessRing(expiry: expiry, now: Date())
                } else {
                    IconTile(
                        systemImage: "leaf.fill",
                        tint: soon || expired ? Palette.amber : Palette.sage,
                        background: soon || expired ? Palette.amberSoft : Palette.sageSoft
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.rounded(.headline, weight: .semibold))
                    Text("\(group.quantity.formatted()) \(group.unit)")
                        .font(.rounded(.title2, weight: .bold))
                        .contentTransition(.numericText())
                    expiryLabel(for: expiry)
                        .padding(.top, 2)
                    if group.batches.count > 1 {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(group.batches) { batch in
                                Text("· \(batchSummary(batch))")
                                    .font(.rounded(.footnote))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }

            Button {
                model.clearError()
                presentedSheet = .use(group)
            } label: {
                Text("Use Ingredient")
            }
            .buttonStyle(PillButtonStyle(systemImage: "minus", prominent: false))
            .accessibilityLabel("Use \(group.name)")
            .disabled(model.isBusy || model.needsReload)
        }
        .bezelCard(padding: 16)
    }

    private func batchSummary(_ batch: Ingredient) -> String {
        let amount = "\(batch.quantity.formatted()) \(batch.unit)"
        guard let expiry = batch.expiryDate else { return "\(amount), no expiry date" }
        return "\(amount), expires \(expiry.formatted(date: .abbreviated, time: .omitted))"
    }

    private func addIngredient() {
        guard !model.isBusy else { return }
        model.clearError()
        presentedSheet = .add
    }

    @ViewBuilder
    private func expiryLabel(for expiry: Date?) -> some View {
        if let expiry {
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
    let group: PantryItemGroup
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
                Section(group.name) {
                    Text("Available: \(group.quantity.formatted()) \(group.unit)")
                    LabeledContent("Amount (\(group.unit))") {
                        TextField("0", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($quantityFocused)
                            .accessibilityLabel("Amount to use in \(group.unit)")
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
                    Text(group.batches.count > 1
                         ? "Enter the amount actually used. The batch that expires first is used first."
                         : "Enter the amount actually used. Stock changes only after you confirm.")
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
        guard quantity <= group.quantity else {
            validationMessage = "The amount exceeds the available stock."
            return
        }

        validationMessage = nil
        quantityFocused = false
        isSubmitting = true
        Task {
            // The use case rechecks current stock; this sheet's snapshot is only an input hint.
            let succeeded = await model.use(group, quantity: quantity)
            isSubmitting = false
            if succeeded { dismiss() }
        }
    }
}
