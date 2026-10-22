import SwiftUI

@MainActor
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TodayViewModel
    private let repository: any MealPlanningRepository
    private let dataVersion: Int
    let openPlan: () -> Void

    init(repository: any MealPlanningRepository, dataVersion: Int = 0, openPlan: @escaping () -> Void) {
        self.dataVersion = dataVersion
        self.repository = repository
        self.openPlan = openPlan
        _model = State(initialValue: TodayViewModel(useCase: LoadTodayOverviewUseCase(repository: repository)))
    }

    var body: some View {
        Group {
            if model.snapshot == nil && model.errorMessage == nil {
                ProgressView("Loading meals…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = model.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if let message = model.errorMessage {
                            ErrorCard(message: message) { Task { await model.load() } }
                        }
                        Text(snapshot.date, format: .dateTime.weekday(.wide).month().day())
                            .font(.rounded(.title3, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        island(snapshot)
                        nextMealCard(snapshot)
                            .revealOnScroll()
                        summaryTiles(snapshot)
                            .revealOnScroll()
                        todaysMeals(snapshot)
                        if !snapshot.missedMeals.isEmpty {
                            missedMeals(snapshot)
                        }
                        useSoon(snapshot)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                    .animation(Theme.spring, value: snapshot)
                }
                .refreshable { await model.load() }
            } else {
                ContentUnavailableView {
                    Label("Unable to Load Meals", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(model.errorMessage ?? "Please try again.")
                } actions: {
                    Button("Retry") { Task { await model.load() } }
                        .buttonStyle(PillButtonStyle(systemImage: "arrow.clockwise"))
                }
            }
        }
        .plannerCanvas()
        .navigationTitle("Today")
        .navigationDestination(for: MealDetailsRoute.self) { route in
            MealDetailView(id: route.id, repository: repository) {
                await model.load()
            }
        }
        .task(id: dataVersion) { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func nextMealCard(_ snapshot: TodayOverview) -> some View {
        if let meal = snapshot.nextMeal {
            NavigationLink(value: MealDetailsRoute(id: meal.id)) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        Eyebrow(text: "Next meal", systemImage: "fork.knife", tint: Palette.onSage)
                        Spacer()
                        MealTypeIcon(type: meal.mealType, tint: Palette.onSage, background: Palette.onSage.opacity(0.16))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(meal.meal.name)
                            .font(.rounded(.title, weight: .bold))
                            .multilineTextAlignment(.leading)
                        Text("\(meal.mealType.displayName) · \(meal.scheduledDate.formatted(date: .omitted, time: .shortened))")
                            .font(.rounded(.headline, weight: .medium))
                            .opacity(0.85)
                    }
                    HStack(spacing: 10) {
                        Text("View details")
                            .font(.rounded(.subheadline, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .frame(width: 28, height: 28)
                            .background(Palette.onSage.opacity(0.16), in: Circle())
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(Palette.onSage)
                .bezelCard(
                    LinearGradient(colors: [Palette.sage, Palette.sageDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                    padding: 22
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next meal: \(mealAccessibilityLabel(meal, date: snapshot.date))")
            .accessibilityHint("View meal details")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                IconTile(systemImage: "fork.knife")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing planned yet")
                        .font(.rounded(.title3, weight: .bold))
                    Text("No upcoming meals planned.")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(.secondary)
                }
                Button("Open Meal Plan", action: openPlan)
                    .buttonStyle(PillButtonStyle(systemImage: "arrow.right"))
            }
            .bezelCard(padding: 22)
        }
    }

    @ViewBuilder
    private func island(_ snapshot: TodayOverview) -> some View {
        if let meal = snapshot.nextMeal {
            IslandCapsule(title: meal.meal.name) {
                Text("in \(meal.scheduledDate, style: .timer)")
            }
        } else {
            IslandCapsule(title: "No upcoming meals", isLive: false) {
                Text("Plan one")
            }
        }
    }

    private func summaryTiles(_ snapshot: TodayOverview) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { tiles(snapshot) }
            VStack(spacing: 14) { tiles(snapshot) }
        }
    }

    @ViewBuilder
    private func tiles(_ snapshot: TodayOverview) -> some View {
        DayRing(
            now: snapshot.date,
            mealTimes: snapshot.meals.map(\.scheduledDate),
            count: snapshot.meals.count,
            label: "Meals today"
        )
        .frame(maxWidth: .infinity)
        .bezelCard()
        statTile(
            value: snapshot.expiringIngredients.count, label: "Use soon",
            systemImage: "hourglass", tint: Palette.amber, background: Palette.amberSoft
        )
    }

    private func statTile(value: Int, label: String, systemImage: String, tint: Color, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IconTile(systemImage: systemImage, tint: tint, background: background)
            Text(value, format: .number)
                .font(.rounded(.largeTitle, weight: .bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .bezelCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    private func todaysMeals(_ snapshot: TodayOverview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(eyebrow: "Schedule", title: "Today's Meals", systemImage: "list.bullet")
            if snapshot.meals.isEmpty {
                Text("No unfinished meals today.")
                    .font(.rounded(.subheadline))
                    .foregroundStyle(.secondary)
                    .bezelCard()
            } else {
                ForEach(snapshot.meals) { meal in
                    mealLink(meal, date: snapshot.date)
                        .revealOnScroll()
                }
            }
        }
    }

    private func missedMeals(_ snapshot: TodayOverview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(eyebrow: "Past 7 days", title: "Not Marked Prepared", systemImage: "clock.badge.exclamationmark", tint: Palette.amber)
            Text("Mark these as prepared to update your pantry, or delete the ones you skipped.")
                .font(.rounded(.subheadline))
                .foregroundStyle(.secondary)
            ForEach(snapshot.missedMeals) { meal in
                mealLink(meal, date: snapshot.date, showsDay: true)
                    .revealOnScroll()
            }
        }
    }

    private func useSoon(_ snapshot: TodayOverview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(eyebrow: "Next 3 days", title: "Use Soon", systemImage: "hourglass", tint: Palette.amber)
            if snapshot.expiringIngredients.isEmpty {
                Text("No ingredients expiring in the next three days.")
                    .font(.rounded(.subheadline))
                    .foregroundStyle(.secondary)
                    .bezelCard()
            } else {
                ForEach(snapshot.expiringIngredients) { ingredient in
                    HStack(spacing: 14) {
                        IconTile(systemImage: "leaf.fill", tint: Palette.amber, background: Palette.amberSoft)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ingredient.name)
                                .font(.rounded(.headline, weight: .semibold))
                            Text("\(ingredient.quantity.formatted()) \(ingredient.unit)")
                                .font(.rounded(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let expiry = ingredient.expiryDate {
                            StatusBadge(
                                text: expiry.formatted(.dateTime.month(.abbreviated).day()),
                                systemImage: "clock", tint: Palette.amber
                            )
                        }
                    }
                    .bezelCard(padding: 14)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ingredientAccessibilityLabel(ingredient))
                    .revealOnScroll()
                }
            }
        }
    }

    private func mealLink(_ entry: MealPlanEntry, date: Date, showsDay: Bool = false) -> some View {
        NavigationLink(value: MealDetailsRoute(id: entry.id)) {
            HStack(spacing: 14) {
                MealTypeIcon(type: entry.mealType)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.meal.name)
                        .font(.rounded(.headline, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(entry.mealType.displayName) · \(showsDay ? entry.scheduledDate.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()) : entry.scheduledDate.formatted(date: .omitted, time: .shortened))")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(.secondary)
                    if entry.scheduledDate < date {
                        StatusBadge(text: "Past scheduled time", systemImage: "clock.badge.exclamationmark", tint: Palette.amber)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .bezelCard(padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mealAccessibilityLabel(entry, date: date))
        .accessibilityHint("View meal details")
    }

    private func mealAccessibilityLabel(_ entry: MealPlanEntry, date: Date) -> String {
        let time = entry.scheduledDate.formatted(date: .abbreviated, time: .shortened)
        let status = entry.scheduledDate < date ? ", past scheduled time" : ""
        return "\(entry.meal.name), \(entry.mealType.displayName), \(time)\(status)"
    }

    private func ingredientAccessibilityLabel(_ ingredient: Ingredient) -> String {
        let amount = "\(ingredient.quantity.formatted()) \(ingredient.unit)"
        guard let expiry = ingredient.expiryDate else { return "\(ingredient.name), \(amount)" }
        let date = expiry.formatted(date: .abbreviated, time: .omitted)
        return "\(ingredient.name), \(amount), expires \(date)"
    }
}
