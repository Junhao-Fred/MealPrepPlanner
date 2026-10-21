import SwiftUI
import WidgetKit

@main
struct MealPrepPlannerWidgetBundle: WidgetBundle {
    var body: some Widget {
        MealPrepPlannerWidget()
    }
}

struct MealPrepPlannerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroupConfiguration.widgetKind, provider: SnapshotTimelineProvider()) { entry in
            MealWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Meal Prep Planner")
        .description("Your next meal, today's plans and ingredients to use soon.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: MealWidgetSnapshot?

    static func sample(at date: Date) -> SnapshotEntry {
        SnapshotEntry(date: date, snapshot: MealWidgetSnapshot(
            generatedAt: date,
            meals: [
                .init(id: UUID(), name: "Tomato Pasta", mealType: "Dinner", scheduledDate: date.addingTimeInterval(3_600)),
                .init(id: UUID(), name: "Berry Oats", mealType: "Snack", scheduledDate: date.addingTimeInterval(7_200))
            ],
            ingredients: [
                .init(id: UUID(), name: "Milk", expiryDate: date),
                .init(id: UUID(), name: "Tomato", expiryDate: date)
            ]
        ))
    }
}

struct SnapshotTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        .sample(at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let now = Date()
        completion(context.isPreview ? .sample(at: now) : SnapshotEntry(date: now, snapshot: WidgetSnapshotStore().load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore().load()
        let dates = WidgetTimelineSchedule.dates(from: now, mealDates: snapshot?.meals.map(\.scheduledDate) ?? [])
        let entries = dates.map { SnapshotEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(3_600))))
    }
}

struct MealWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: SnapshotEntry

    private var nextMeal: MealWidgetSnapshot.Meal? {
        entry.snapshot?.nextMeal(at: entry.date)
    }

    private var remainingMeals: [MealWidgetSnapshot.Meal] {
        entry.snapshot?.remainingMealsToday(at: entry.date, calendar: calendar) ?? []
    }

    private var expiringCount: Int {
        entry.snapshot?.useSoonIngredients(at: entry.date, calendar: calendar).count ?? 0
    }

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                lockScreen
            } else if family == .systemMedium && !dynamicTypeSize.isAccessibilitySize {
                medium
            } else {
                small
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Next Meal", systemImage: "fork.knife")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            nextMealContent
            Spacer(minLength: 0)
            if entry.snapshot != nil { expiryLabel }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Next Meal", systemImage: "fork.knife")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    nextMealContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if entry.snapshot != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Today · \(remainingMeals.count) left")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if remainingMeals.isEmpty {
                            Text("No meals left today")
                                .font(.caption)
                        } else {
                            ForEach(remainingMeals.prefix(2)) { meal in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(meal.name).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(meal.scheduledDate, style: .time)
                                }
                                .font(.caption)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            if entry.snapshot != nil { expiryLabel }
        }
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Next Meal", systemImage: "fork.knife")
                .font(.caption.bold())
            if let meal = nextMeal {
                Text(meal.name).font(.headline).lineLimit(1)
                HStack {
                    mealTime(meal.scheduledDate)
                    Spacer(minLength: 4)
                    Label("\(expiringCount)", systemImage: "clock")
                        .accessibilityLabel("\(expiringCount) ingredients to use soon")
                }
                .font(.caption2)
            } else {
                Text(emptyMessage).font(.caption).lineLimit(2)
                if entry.snapshot != nil { expiryLabel }
            }
        }
    }

    @ViewBuilder
    private var nextMealContent: some View {
        if let meal = nextMeal {
            Text(meal.name).font(.headline).lineLimit(2)
            Text(meal.mealType).font(.caption).foregroundStyle(.secondary)
            mealTime(meal.scheduledDate).font(.caption)
        } else {
            Text(emptyMessage).font(.subheadline)
        }
    }

    private var emptyMessage: String {
        entry.snapshot == nil ? "Open the app to get started." : "No upcoming meals. Plan one in the app."
    }

    private var accessibilitySummary: String {
        guard entry.snapshot != nil else { return "Meal Prep Planner. Open the app to get started." }
        let mealDescription: String
        if let meal = nextMeal {
            let time = meal.scheduledDate.formatted(date: .abbreviated, time: .shortened)
            mealDescription = "Next meal: \(meal.name), \(time)."
        } else {
            mealDescription = "No upcoming meals."
        }
        return "\(mealDescription) \(remainingMeals.count) meals left today. \(expiringCount) ingredients to use soon."
    }

    private var expiryLabel: some View {
        Label("\(expiringCount) to use soon", systemImage: "clock")
            .font(.caption)
            .accessibilityLabel("\(expiringCount) ingredients to use soon")
    }

    @ViewBuilder
    private func mealTime(_ date: Date) -> some View {
        if calendar.isDate(date, inSameDayAs: entry.date) {
            Text(date, style: .time)
        } else {
            Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
        }
    }
}

#if DEBUG
#Preview("Small", as: .systemSmall) {
    MealPrepPlannerWidget()
} timeline: {
    SnapshotEntry.sample(at: Date())
}

#Preview("Medium", as: .systemMedium) {
    MealPrepPlannerWidget()
} timeline: {
    SnapshotEntry.sample(at: Date())
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    MealPrepPlannerWidget()
} timeline: {
    SnapshotEntry.sample(at: Date())
}

#Preview("Empty", as: .systemSmall) {
    MealPrepPlannerWidget()
} timeline: {
    SnapshotEntry(date: Date(), snapshot: MealWidgetSnapshot(generatedAt: Date(), meals: [], ingredients: []))
    SnapshotEntry(date: Date().addingTimeInterval(60), snapshot: nil)
}
#endif
