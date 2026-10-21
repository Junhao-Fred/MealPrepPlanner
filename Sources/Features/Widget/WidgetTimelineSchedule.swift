import Foundation

enum WidgetTimelineSchedule {
    static func dates(from now: Date, mealDates: [Date], calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: now)
        let midnights = (1...2).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        guard let end = midnights.last else { return [now] }

        var dates = Set([now] + midnights)
        for mealDate in mealDates where mealDate >= now && mealDate < end {
            dates.insert(mealDate)
            let nextDate = mealDate.addingTimeInterval(1)
            if nextDate < end { dates.insert(nextDate) }
        }
        return dates.sorted()
    }
}
