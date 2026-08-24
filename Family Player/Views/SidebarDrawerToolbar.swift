//
//  SidebarDrawerToolbar.swift
//  Family Player
//

import SwiftUI

/// Shared state behind the iPad-landscape sidebar's collapse/reopen control.
///
/// SidebarNavigationView owns one instance of this and injects it into the
/// environment for every screen inside its single shared NavigationStack.
/// This exists because SwiftUI toolbars are per-screen: a `.toolbar {}`
/// applied to the stack's root does NOT carry over to a pushed destination
/// (tapping a Persona, then an Album, etc.) -- each pushed screen has to
/// contribute its own toolbar content for anything to show up in its nav
/// bar. Without this, drilling into a Persona -> Album (or a Playlist)
/// left you with no way back to the drawer at all once the sidebar was
/// collapsed, matching exactly the bug reported: "When I go into a song,
/// I have no menu. I have no way to get to the drawer."
@Observable
final class SidebarDrawerState {
    var isSidebarExpanded = true
    // nil means "no explicit choice yet" -- both layouts fall back to
    // their own historical default display (sidebar shows Albums, the tab
    // bar shows Library's own root) without that fallback ever being
    // written back into this shared value, so first launch on either
    // orientation looks exactly like it always has. This is also the
    // single piece of state now shared between SidebarNavigationView
    // (landscape) and MainTabView's tab bar (portrait) so that rotating
    // the device keeps you on the same top-level section instead of each
    // layout tracking its own selection independently.
    var selection: SidebarItem?
}

private struct SidebarDrawerStateKey: EnvironmentKey {
    static let defaultValue: SidebarDrawerState? = nil
}

extension EnvironmentValues {
    var sidebarDrawerState: SidebarDrawerState? {
        get { self[SidebarDrawerStateKey.self] }
        set { self[SidebarDrawerStateKey.self] = newValue }
    }
}

/// Attach to every screen reachable inside the sidebar's NavigationStack
/// (root pages AND anything they push to -- Persona/Album/Playlist detail,
/// Share management, etc.) so the reopen button + section shortcuts are
/// available no matter how deep the user has navigated. On iPhone, where
/// no SidebarDrawerState is ever injected into the environment, this is a
/// harmless no-op -- the view's own local toolbar content is unaffected.
private struct SidebarDrawerToolbarModifier: ViewModifier {
    @Environment(\.sidebarDrawerState) private var drawerState

    func body(content: Content) -> some View {
        content.toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let drawerState, !drawerState.isSidebarExpanded {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        drawerState.isSidebarExpanded = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .accessibilityLabel("Show Sidebar")
            }
            ToolbarItemGroup(placement: .navigationBarLeading) {
                ForEach(SidebarItem.allCases) { item in
                    Button {
                        drawerState.selection = item
                    } label: {
                        Image(systemName: item.systemImage)
                    }
                    .foregroundStyle(drawerState.selection == item ? Color.accentColor : Color.secondary)
                    .accessibilityLabel(item.title)
                }
            }
        }
    }
}

extension View {
    func sidebarDrawerToolbar() -> some View {
        modifier(SidebarDrawerToolbarModifier())
    }
}
