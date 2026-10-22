//  Created by Mingchen Liang on 2026/10/22.

import SwiftUI

extension MealType {
    var symbolName: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }
}

/// Decorative meal type tile; the meal type is always also spelled out in text.
struct MealTypeIcon: View {
    let type: MealType
    var tint: Color = Palette.sage
    var background: Color = Palette.sageSoft
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 44

    var body: some View {
        Image(systemName: type.symbolName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}
