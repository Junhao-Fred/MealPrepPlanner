//  Created by Junhao Huang on 2026/9/27.

enum MealType: String, CaseIterable, Codable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack

    var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }
}
