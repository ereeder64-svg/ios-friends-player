//
//  ShareInvitations.swift
//  Family Player
//

import Foundation

// iCloud share invitation URLs. Tapping one opens the system "Add to iCloud
// Drive" sheet so the family member can accept the share. These URLs are
// effectively access tokens — keep the GitHub repository private.
enum ShareInvitations {
    // TODO: replace with the real iCloud Drive share link before shipping
    // this fork. Create/share a folder named "Friends" from Files app
    // (or reuse an existing one) -> Share -> Copy Link, the same way each
    // of the family shares was set up in the original app.
    static let urls: [String: String] = [
        "Friends": "https://www.icloud.com/iclouddrive/REPLACE_ME#Friends",
    ]
}
