//  Created by Mingchen Liang on 2026/10/22.

import UIKit

/// App-only: navigation bar styling is not available to the widget extension.
extension Theme {
    /// Rounded navigation titles to match the in-content headings.
    static func configureAppearance() {
        let largeTitle = roundedFont(.largeTitle, weight: .bold)
        let title = roundedFont(.headline, weight: .semibold)

        // Transparent at the top so the canvas shows; a blurred bar once content scrolls under it.
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        for appearance in [edge, scrolled] {
            appearance.largeTitleTextAttributes = [.font: largeTitle]
            appearance.titleTextAttributes = [.font: title]
        }

        let navigationBar = UINavigationBar.appearance()
        navigationBar.scrollEdgeAppearance = edge
        navigationBar.standardAppearance = scrolled
        navigationBar.compactAppearance = scrolled
    }

    private static func roundedFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let weighted = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        guard let descriptor = weighted.fontDescriptor.withDesign(.rounded) else { return weighted }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}
