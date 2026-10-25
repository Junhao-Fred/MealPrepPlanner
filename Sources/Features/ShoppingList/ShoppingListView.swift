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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let snapshot = model.snapshot {
                    rangeCard(snapshot)
                        .revealOnScroll()
                }

                if model.isLoading {
                    ProgressView(model.snapshot == nil ? "Loading shopping list…" : "Refreshing shopping list…")
                        .font(.rounded(.subheadline))
                        .frame(maxWidth: .infinity)
                }

                if let message = model.errorMessage {
                    ErrorCard(
                        message: message,
                        detail: model.snapshot != nil ? "Showing the last loaded result. It may be out of date." : nil,
                        retryDisabled: model.isLoading
                    ) { Task { await model.load() } }
                }

                if let snapshot = model.snapshot {
                    if snapshot.items.isEmpty {
                        Group {
                            if snapshot.plannedMealCount == 0 {
                                ContentUnavailableView("No Meals to Shop For", systemImage: "calendar")
                            } else {
                                ContentUnavailableView("Nothing to Buy", systemImage: "checkmark.circle")
                            }
                        }
                        .bezelCard(padding: 20)
                    } else {
                        itemsCard(snapshot.items)
                            .revealOnScroll()
                    }
                } else if !model.isLoading && model.errorMessage == nil {
                    Button("Load Shopping List") { Task { await model.load() } }
                        .buttonStyle(PillButtonStyle(systemImage: "arrow.clockwise"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .animation(Theme.spring, value: model.snapshot?.items)
        }
        .plannerCanvas()
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

    private func rangeCard(_ snapshot: ShoppingListSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "This week", systemImage: "cart", tint: Palette.onSage)
            Text("\(snapshot.startDate.formatted(date: .abbreviated, time: .omitted)) – \(snapshot.endDate.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                .font(.rounded(.title2, weight: .bold))
            Text("Unfinished meals: \(snapshot.plannedMealCount)")
                .font(.rounded(.headline, weight: .medium))
                .opacity(0.85)
        }
        .foregroundStyle(Palette.onSage)
        .bezelCard(
            LinearGradient(colors: [Palette.sage, Palette.sageDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
            padding: 22
        )
    }

    private func itemsCard(_ items: [ShoppingListItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(eyebrow: "\(items.count) to buy", title: "To Buy", systemImage: "bag")
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Palette.hairline) }
                    HStack(spacing: 14) {
                        IconTile(systemImage: "cart.fill")
                        Text(item.name)
                            .font(.rounded(.headline, weight: .semibold))
                        Spacer(minLength: 12)
                        Text("\(item.quantity.formatted()) \(item.unit)")
                            .font(.rounded(.title3, weight: .bold))
                            .foregroundStyle(Palette.sage)
                        Button {
                            Task { await model.addToPantry(item) }
                        } label: {
                            if model.addingItemID == item.id {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark.circle")
                                    .font(.title2)
                            }
                        }
                        .buttonStyle(.borderless)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(model.addingItemID != nil || model.isLoading)
                        .accessibilityLabel("Bought \(item.name), add to pantry")
                    }
                    .padding(.vertical, 10)
                }
            }
            .bezelCard(padding: 16)
        }
    }
}
