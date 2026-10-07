import SwiftUI

/// How tightly a subtree packs its content.
enum Density: Sendable, Hashable {
    case regular
    case compact

    /// The multiplier applied to inter-row spacing.
    var spacingScale: CGFloat {
        switch self {
        case .regular: 1
        case .compact: 0.6
        }
    }
}

extension EnvironmentValues {

    /// Set on an ancestor to pack part of the hierarchy more tightly than its siblings.
    ///
    /// An environment value rather than a parameter, so a container can set it once instead of
    /// every component in that container accepting and forwarding it.
    @Entry var panelDensity: Density = .regular
}

#Preview("One override, two densities side by side") {
    HStack(alignment: .top, spacing: Spacing.loose) {
        DensityDemo(title: "regular")
        DensityDemo(title: "compact")
            .environment(\.panelDensity, .compact)
    }
    .padding(Spacing.loose)
}

/// Exists only for the preview above, to show that the override reaches a subtree without
/// touching its sibling.
private struct DensityDemo: View {
    let title: String

    @Environment(\.panelDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.regular * density.spacingScale) {
            Text(title).font(Typography.sectionHeader)
            ForEach(1..<4) { index in
                Text("row \(index)").font(Typography.control)
            }
        }
    }
}
