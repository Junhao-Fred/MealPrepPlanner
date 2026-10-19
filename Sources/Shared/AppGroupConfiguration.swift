//  Created by Junhao Huang on 2026/10/19.

/// Identifiers shared by the app and the widget extension.
/// `identifier` must match the App Group in both targets' entitlements.
enum AppGroupConfiguration {
    static let identifier = "group.com.manbo.MealPrepPlanner"
    static let widgetKind = "MealPrepPlannerWidget"
    static let snapshotKey = "mealWidgetSnapshot"
}
