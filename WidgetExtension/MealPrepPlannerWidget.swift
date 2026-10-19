//  Created by Junhao Huang on 2026/10/19.

import SwiftUI
import WidgetKit

// Placeholder that proves the extension reads the shared snapshot.
// Zhengyang (B) replaces the provider and views with the small, medium and lock screen widgets.

@main
struct MealPrepPlannerWidgetBundle: WidgetBundle {
    var body: some Widget {
        MealPrepPlannerWidget()
    }
}

struct MealPrepPlannerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroupConfiguration.widgetKind, provider: SnapshotTimelineProvider()) { entry in
            NextMealPlaceholderView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Meal")
        .description("Shows your next planned meal.")
        .supportedFamilies([.systemSmall])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: MealWidgetSnapshot?
}

struct SnapshotTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshotStore().load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshotStore().load())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct NextMealPlaceholderView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let meal = entry.snapshot?.nextMeal(at: entry.date) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Next meal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(meal.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(meal.scheduledDate, style: .time)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Open MealPrep Planner to plan a meal.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
