//
//  ShareInvitations.swift
//  Family Player
//

import Foundation

// iCloud share invitation URLs. Tapping one opens the system "Add to iCloud
// Drive" sheet so the family member can accept the share. These URLs are
// effectively access tokens — keep the GitHub repository private.
enum ShareInvitations {
    static let urls: [String: String] = [
        "Friends": "https://www.icloud.com/iclouddrive/085J73J7FUnjrTsYbjdOa8YOg#Friends_Share",
    ]
}
