//
//  FriendsPlayerWidgetBundle.swift
//  FriendsPlayerWidget
//
//  Created by Eric Reeder on 6/25/26.
//

import WidgetKit
import SwiftUI

@main
struct FriendsPlayerWidgetBundle: WidgetBundle {
    var body: some Widget {
        FriendsPlayerWidget()
        FriendsPlayerWidgetControl()
        FriendsPlayerWidgetLiveActivity()
    }
}
