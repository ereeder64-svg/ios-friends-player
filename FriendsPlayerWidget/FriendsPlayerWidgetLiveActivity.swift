//
//  FriendsPlayerWidgetLiveActivity.swift
//  FriendsPlayerWidget
//
//  Created by Eric Reeder on 6/25/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct FriendsPlayerWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct FriendsPlayerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FriendsPlayerWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension FriendsPlayerWidgetAttributes {
    fileprivate static var preview: FriendsPlayerWidgetAttributes {
        FriendsPlayerWidgetAttributes(name: "World")
    }
}

extension FriendsPlayerWidgetAttributes.ContentState {
    fileprivate static var smiley: FriendsPlayerWidgetAttributes.ContentState {
        FriendsPlayerWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: FriendsPlayerWidgetAttributes.ContentState {
         FriendsPlayerWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: FriendsPlayerWidgetAttributes.preview) {
   FriendsPlayerWidgetLiveActivity()
} contentStates: {
    FriendsPlayerWidgetAttributes.ContentState.smiley
    FriendsPlayerWidgetAttributes.ContentState.starEyes
}
