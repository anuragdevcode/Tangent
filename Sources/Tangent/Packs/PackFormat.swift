import Foundation

/// Names defined by the v1 wallpaper pack format.
///
/// These are fixed on-disk and page-level contract values, not app branding.
/// They live here so format details stay in one place and the rest of the
/// codebase only ever refers to `PackFormat`.
enum PackFormat {

    /// Metadata file at the root of a pack folder.
    static let infoFile = "LivelyInfo.json"

    /// Optional control-surface file at the root of a pack folder.
    static let propertiesFile = "LivelyProperties.json"

    /// Page-side function historical packs call to receive control values.
    static let legacyPropertyListener = "livelyPropertyListener"

    /// Page-side function Tangent-authored packs call.
    static let propertyListener = "tangentPropertyListener"
}
