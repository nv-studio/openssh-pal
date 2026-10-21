import SwiftUI

/// Turns a `ColorRole` into something drawable.
///
/// This is the **only** place in the codebase that names a colour, and the only one that
/// references a generated asset catalog symbol. Concentrating it here is what keeps the catalog
/// dependency reviewable, and what lets every other file deal in roles.
///
/// Where a system semantic style expresses the intent it is used in preference to a colour set,
/// because the system styles already adapt to appearance, increased contrast and the user's
/// accent colour. A colour set exists only for the three state colours, where no system semantic
/// carries the meaning.
enum ColorRoleAppearance {

    /// The style a role renders as.
    ///
    /// Returns `AnyShapeStyle` because the branches are genuinely different types — a
    /// hierarchical style and a catalog colour are not interchangeable to the compiler — and an
    /// opaque return type cannot span them.
    static func style(for role: ColorRole) -> AnyShapeStyle {
        switch role {
        case .primaryText:
            AnyShapeStyle(.primary)
        case .secondaryText:
            AnyShapeStyle(.secondary)
        case .success:
            AnyShapeStyle(Color.success)
        case .warning:
            AnyShapeStyle(Color.warning)
        case .failure:
            AnyShapeStyle(Color.failure)
        case .destructive:
            // Deliberately the same colour set as `.failure`: a destructive action and a failed
            // one should read alike. They stay separate roles because their *meanings* differ,
            // and a later design may want to split them.
            AnyShapeStyle(Color.failure)
        case .prominent:
            // Follows the user's system accent colour, which is why no accent asset exists.
            AnyShapeStyle(.tint)
        case .fieldBorder:
            AnyShapeStyle(.tertiary)
        case .fieldBackground:
            AnyShapeStyle(.quaternary)
        case .separator:
            AnyShapeStyle(.quaternary)
        case .containerBackground:
            // The faintest fill there is: a container should be told apart from the panel,
            // not compete with what it holds.
            AnyShapeStyle(.quinary)
        case .rowHover:
            AnyShapeStyle(.quaternary)
        case .selectedTab:
            // Fully opaque white or black, deliberately not `.primary` or `Color.primary`. The
            // label colour is translucent, and the live menu bar window draws translucent text
            // brighter than a translucent filled shape, so the underline came out grey beneath
            // a bright title. An opaque colour renders the same on both.
            AnyShapeStyle(Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
            }))
        }
    }
}
