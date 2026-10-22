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
                .containerBackground(for: .widget) { WidgetCanvas() }
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

/// Cream canvas with a sage glow on the Home Screen. Lock Screen widgets keep the system background.
struct WidgetCanvas: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryRectangular {
            Color.clear
        } else {
            ZStack {
                Palette.canvas
                RadialGradient(
                    colors: [Palette.sage.opacity(0.18), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: 220
                )
            }
        }
    }
}

struct MealWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.calendar) private var calendar
    let entry: SnapshotEntry

    /// A live countdown reads well for the next few hours; further out, show the time instead.
    private static let countdownWindow: TimeInterval = 12 * 3_600

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
            } else if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            heading
            nextMealContent
            Spacer(minLength: 0)
            if entry.snapshot != nil { expiryChip }
        }
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                heading
                nextMealContent
                Spacer(minLength: 0)
                if entry.snapshot != nil { expiryChip }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if entry.snapshot != nil {
                DayRing(
                    now: entry.date,
                    mealTimes: remainingMeals.map(\.scheduledDate),
                    count: remainingMeals.count,
                    label: "left today",
                    fixedDiameter: 92
                )
                .accessibilityLabel(remainingAccessibilityLabel)
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 6) {
            if nextMeal != nil {
                LiveDot()
            }
            Text("NEXT MEAL")
                .font(.rounded(.caption2, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Palette.sage)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var nextMealContent: some View {
        if let meal = nextMeal {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.rounded(.headline, weight: .bold))
                    .lineLimit(2)
                Text(meal.mealType)
                    .font(.rounded(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                countdown(to: meal.scheduledDate)
                    .font(.rounded(.title3, weight: .bold))
                    .foregroundStyle(Palette.sage)
                    .monospacedDigit()
                    .padding(.top, 2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Next meal: \(meal.name), \(meal.mealType)")
        } else {
            Text(emptyMessage)
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func countdown(to date: Date) -> some View {
        if date.timeIntervalSince(entry.date) < Self.countdownWindow {
            Text(date, style: .timer)
        } else {
            mealTime(date)
        }
    }

    private var expiryChip: some View {
        Label("\(expiringCount) to use soon", systemImage: "hourglass")
            .font(.rounded(.caption2, weight: .semibold))
            .foregroundStyle(expiringCount > 0 ? Palette.emberText : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (expiringCount > 0 ? Palette.ember : Color.secondary).opacity(0.13),
                in: Capsule()
            )
            .accessibilityLabel("\(expiringCount) ingredients to use soon")
    }

    // MARK: Lock Screen

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Next Meal", systemImage: "fork.knife")
                .font(.rounded(.caption, weight: .bold))
                .widgetAccentable()
            if let meal = nextMeal {
                Text(meal.name).font(.rounded(.headline, weight: .bold)).lineLimit(1)
                HStack {
                    countdown(to: meal.scheduledDate)
                        .monospacedDigit()
                    Spacer(minLength: 4)
                    Label("\(expiringCount)", systemImage: "hourglass")
                        .accessibilityLabel("\(expiringCount) ingredients to use soon")
                }
                .font(.rounded(.caption2, weight: .semibold))
            } else {
                Text(emptyMessage).font(.rounded(.caption)).lineLimit(2)
                if entry.snapshot != nil {
                    Label("\(expiringCount) to use soon", systemImage: "hourglass")
                        .font(.rounded(.caption2, weight: .semibold))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Helpers

    private var emptyMessage: String {
        entry.snapshot == nil ? "Open the app to get started." : "No upcoming meals. Plan one in the app."
    }

    private var remainingAccessibilityLabel: String {
        let count = remainingMeals.count
        guard count > 0 else { return "No meals left today" }
        let names = remainingMeals.map(\.name).joined(separator: ", ")
        return "\(count) \(count == 1 ? "meal" : "meals") left today: \(names)"
    }

    @ViewBuilder
    private func mealTime(_ date: Date) -> some View {
        if calendar.isDate(date, inSameDayAs: entry.date) {
            Text(date, style: .time)
        } else {
            Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
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
