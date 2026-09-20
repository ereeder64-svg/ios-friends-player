//
//  SongRowLayout.swift
//  Friends Player
//

import SwiftUI

/// How much horizontal room a song row has to work with. Driven by actual
/// measured width (not just size class), because the same iPad can be in
/// three meaningfully different states: the iPhone-style compact layout,
/// the iPad layout with the landscape sidebar eating into the width, or
/// the iPad layout with the sidebar collapsed and the full screen to work
/// with.
enum SongRowLayoutMode {
    /// iPhone, or any compact-width context: title stacked over a subtitle
    /// line, as before. No separate columns -- not enough room for them.
    case compact
    /// iPad with less than the full screen's width available (portrait
    /// tab-bar mode, or landscape with the sidebar still showing): artist
    /// and duration get their own columns, but not album (that's the one
    /// column dropped first when width is tighter).
    case regular
    /// iPad landscape with the sidebar collapsed -- the widest state.
    /// Adds an album column between the title and the duration.
    case wide

    /// Threshold picked so a landscape iPad WITH the sidebar showing
    /// (detail column width = full width minus the ~320pt sidebar) stays
    /// under it on every current iPad size, while the sidebar collapsed
    /// (detail column = full screen width) clears it on every current
    /// iPad size in landscape. Also comfortably above any iPad's portrait
    /// full-screen width, so portrait never accidentally qualifies.
    static let wideThreshold: CGFloat = 1100

    static func resolve(width: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?) -> SongRowLayoutMode {
        guard horizontalSizeClass == .regular else { return .compact }
        return width >= wideThreshold ? .wide : .regular
    }
}

private struct SongRowLayoutKey: EnvironmentKey {
    static let defaultValue: SongRowLayoutMode = .compact
}

extension EnvironmentValues {
    var songRowLayout: SongRowLayoutMode {
        get { self[SongRowLayoutKey.self] }
        set { self[SongRowLayoutKey.self] = newValue }
    }
}
