import Foundation

enum ExpiryRules {
    static func isExpired(_ expiryDate: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let expiryDate else { return false }
        return expiryDate < calendar.startOfDay(for: now)
    }

    static func isExpiringSoon(_ expiryDate: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let expiryDate else { return false }
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 3, to: start) else { return false }
        return expiryDate >= start && expiryDate < end
    }
}
