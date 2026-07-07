//
//  AdaptiveTileGrid.swift
//  Family Player
//

import SwiftUI

/// Shared column layout for album/persona/playlist tile grids.
///
/// On iPhone this settles at the same 2-across layout the app always used.
/// On iPad, tiles no longer get stretched to giant fixed-2-column sizes —
/// column count grows with available width, so:
///   - iPad mini: ~4 across portrait, ~6 across landscape
///   - iPad Air/Pro 11": ~5 across portrait, ~7 across landscape
///   - iPad Pro 12.9/13": ~6 across portrait, ~8 across landscape
/// Rotating or using Split View just re-flows the count automatically.
enum AdaptiveTileGrid {
    static let spacing: CGFloat = 20

    static var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 140), spacing: spacing)]
    }
}
