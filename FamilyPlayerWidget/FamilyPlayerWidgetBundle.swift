//
//  FamilyPlayerWidgetBundle.swift
//  FamilyPlayerWidget
//
//  Created by Eric Reeder on 6/25/26.
//

import WidgetKit
import SwiftUI

@main
struct FamilyPlayerWidgetBundle: WidgetBundle {
    var body: some Widget {
        FamilyPlayerWidget()
        FamilyPlayerWidgetControl()
        FamilyPlayerWidgetLiveActivity()
    }
}
