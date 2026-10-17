//  Created by Junhao Huang on 2026/9/27.

import Foundation

/// A scheduled meal preparation.
struct MealPlanEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID

    var meal: Meal

    var scheduledDate: Date

    var mealType: MealType

    var isPrepared: Bool

    init(
        id: UUID = UUID(),
        meal: Meal,
        scheduledDate: Date,
        mealType: MealType,
        isPrepared: Bool = false
    ) {
        self.id = id
        self.meal = meal
        self.scheduledDate = scheduledDate
        self.mealType = mealType
        self.isPrepared = isPrepared
    }
}
