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
        "Public Share":  "https://www.icloud.com/iclouddrive/06fQX6Nen05Q5ngVz7FPqMHxg#Public_Share",
        "Family Share":  "https://www.icloud.com/iclouddrive/029XKy-_wX2NDjH_Df2iqZAlQ#Family_Share",
        "Legacy Share":  "https://www.icloud.com/iclouddrive/089aQzMdsdpgQELnR89qW9bag#Legacy_Share",
        "Amanda":        "https://www.icloud.com/iclouddrive/09dZEfrAknvW9i5gQxzNRUlvg#Amanda",
        "Chris":         "https://www.icloud.com/iclouddrive/05blObTO1Vxt63y3R9jpZwj3Q#Chris",
        "Emily":         "https://www.icloud.com/iclouddrive/0e6O69PtqtAczNTjVi_GjqnlA#Emily",
        "Michele":       "https://www.icloud.com/iclouddrive/08aQhfu7aSZUvZwyku0rY8axQ#Michele",
    ]
}
