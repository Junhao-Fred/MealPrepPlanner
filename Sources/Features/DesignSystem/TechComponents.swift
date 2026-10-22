//  Created by Mingchen Liang on 2026/10/22.

import SwiftUI

/// A pulsing neon dot that marks something live. Still when Reduce Motion is on.
struct LiveDot: View {
    var tint: Color = Palette.ember
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.35))
                .frame(width: 16, height: 16)
                .scaleEffect(pulsing ? 1.25 : 0.6)
                .opacity(pulsing ? 0 : 1)
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

/// A Dynamic Island style capsule: always black, with a live dot, a title and a trailing value.
struct IslandCapsule<Trailing: View>: View {
    let title: String
    var isLive = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            LiveDot(tint: isLive ? Palette.ember : .gray)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
                .foregroundStyle(isLive ? Color(white: 1, opacity: 0.75) : .gray)
                .monospacedDigit()
        }
        .font(.rounded(.subheadline, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(Color.black, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(white: 1, opacity: 0.12), lineWidth: 0.5))
        .shadow(color: Palette.shadow, radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }
}

/// A 24-hour ring: sage shows how much of today has passed, neon dots mark meal times.
struct DayRing: View {
    let now: Date
    let mealTimes: [Date]
    let count: Int
    let label: String
    @Environment(\.calendar) private var calendar
    /// Fixed size for places that cannot grow, such as widgets. Otherwise it scales with Dynamic Type.
    var fixedDiameter: CGFloat?
    @ScaledMetric(relativeTo: .largeTitle) private var scaledDiameter: CGFloat = 116

    private var diameter: CGFloat { fixedDiameter ?? scaledDiameter }
    private var lineWidth: CGFloat { diameter < 100 ? 7 : 10 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.sage.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction(of: now))
                .stroke(
                    AngularGradient(colors: [Palette.sage.opacity(0.35), Palette.sage], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            ForEach(Array(mealTimes.enumerated()), id: \.offset) { _, time in
                Circle()
                    .fill(Palette.ember)
                    .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                    .frame(width: lineWidth + 4, height: lineWidth + 4)
                    .offset(y: -diameter / 2)
                    .rotationEffect(.degrees(fraction(of: time) * 360))
            }
            VStack(spacing: 0) {
                Text(count, format: .number)
                    .font(.rounded(.title, weight: .bold))
                    .contentTransition(.numericText())
                Text(label)
                    .font(.rounded(.caption2, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(lineWidth * 2)
        }
        .frame(width: diameter, height: diameter)
        .padding(lineWidth / 2 + 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(count)")
    }

    private func fraction(of date: Date) -> Double {
        let start = calendar.startOfDay(for: now)
        return min(max(date.timeIntervalSince(start) / 86_400, 0), 1)
    }
}

/// Seven columns of dots: filled = prepared, outlined = planned, faint = free slot. Today is marked in neon.
struct WeekDotMatrix: View {
    struct Day: Identifiable {
        let date: Date
        let prepared: Int
        let planned: Int
        var id: Date { date }
    }

    let days: [Day]
    var rows = 4
    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                let isToday = calendar.isDateInToday(day.date)
                VStack(spacing: 7) {
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.rounded(.caption2, weight: .bold))
                        .foregroundStyle(isToday ? Palette.emberText : .secondary)
                    VStack(spacing: 5) {
                        ForEach(0..<rows, id: \.self) { row in
                            dotView(row: row, day: day)
                        }
                    }
                    Text(day.date, format: .dateTime.day())
                        .font(.rounded(.caption, weight: isToday ? .bold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? Palette.emberText : .primary)
                    Circle()
                        .fill(isToday ? Palette.ember : .clear)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: day, isToday: isToday))
            }
        }
    }

    @ViewBuilder
    private func dotView(row: Int, day: Day) -> some View {
        if row < day.prepared {
            Circle().fill(Palette.sage).frame(width: dot, height: dot)
        } else if row < day.prepared + day.planned {
            Circle().strokeBorder(Palette.sage, lineWidth: 2).frame(width: dot, height: dot)
        } else {
            Circle().fill(Palette.hairline).frame(width: dot, height: dot)
        }
    }

    private func accessibilityLabel(for day: Day, isToday: Bool) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let total = day.prepared + day.planned
        let meals = total == 1 ? "1 meal" : "\(total) meals"
        return "\(isToday ? "Today, " : "")\(date): \(meals), \(day.prepared) prepared"
    }
}

/// A thin ring showing days left before expiry over a one-week scale.
struct FreshnessRing: View {
    let expiry: Date
    let now: Date
    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 44

    var body: some View {
        let days = daysLeft
        let tint: Color = days < 0 ? .red : (days < 3 ? Palette.ember : Palette.sage)
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(max(Double(days + 1) / 7, 0.04), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(days < 0 ? "!" : "\(days)d")
                .font(.rounded(.caption, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(days < 0 ? Color.red : (days < 3 ? Palette.emberText : Palette.sage))
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var daysLeft: Int {
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: expiry)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
