//
//  MainTabView.swift
//  Friends Player
//

import SwiftUI

struct MainTabView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // iPad in landscape gets the Apple-Music-style collapsible sidebar
    // instead of the iPhone/portrait tab bar -- there's enough width to
    // spare for a persistent nav column. Driven by the container's actual
    // size (not just orientation) so Split View/Slide Over on iPad, where
    // the app's own width can be narrow even in device-landscape, still
    // falls back to the tab bar.
    @State private var containerSize: CGSize = .zero
    // Which top-level section (Albums, Playlists, a specific tab, etc.)
    // is currently showing. Owned up here, above the branch that swaps
    // between the landscape sidebar and the portrait tab bar, because
    // that branch is a plain `if/else` -- SwiftUI fully discards
    // whichever side isn't active, so anything state owned INSIDE either
    // side is lost on every rotation. Owning it here instead means the
    // same instance survives the swap, so rotating the device keeps you
    // on the same section instead of dumping you back to each layout's
    // own default.
    @State private var sectionState = SidebarDrawerState()
    // Which branch is actually committed to screen. Kept separate from
    // useSidebarLayoutRaw below because that raw value is driven straight
    // off live, continuously-updating rotation-animation geometry: as the
    // device spins from landscape to portrait (or back), the view's
    // measured width/height ratio sweeps through several intermediate
    // states before settling, and reading the branch straight off that
    // live value flips the Group mid-animation -- which is exactly the
    // "stuck on 5-across, squeezed" flash reported: the OLD layout's grid
    // rendering into the NEW orientation's (not-yet-final) width for a
    // frame or two before it "catches up". nil means "not measured yet".
    @State private var isSidebarLayoutCommitted: Bool?

    private var useSidebarLayoutRaw: Bool {
        horizontalSizeClass == .regular && containerSize.width > containerSize.height
    }

    private var useSidebarLayout: Bool {
        isSidebarLayoutCommitted ?? useSidebarLayoutRaw
    }

    var body: some View {
        Group {
            if useSidebarLayout {
                SidebarNavigationView(drawerState: sectionState)
            } else {
                tabLayout
                    // The sidebar layout measures its own detail column
                    // (its width differs from the full screen once the
                    // sidebar is showing); here there's no sidebar, so the
                    // full container width is the right measurement.
                    .environment(
                        \.songRowLayout,
                        SongRowLayoutMode.resolve(width: containerSize.width, horizontalSizeClass: horizontalSizeClass)
                    )
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newValue in
            containerSize = newValue
        }
        // Debounces the branch switch itself (not the width/height
        // measurements column layouts use, which stay live) so a rotation
        // has to actually settle before the sidebar<->tab-bar swap
        // commits. .task(id:) cancels and restarts this on every change
        // to the raw value, so a value that's only true for one
        // in-between animation frame never gets a chance to commit -- only
        // one that holds steady for the full delay does. The very first
        // measurement (isSidebarLayoutCommitted still nil, e.g. right at
        // launch) commits immediately so there's no startup flash of the
        // wrong layout.
        .task(id: useSidebarLayoutRaw) {
            // Portrait doesn't have a sidebar option at all, so the
            // instant rotation is heading that way -- even one frame into
            // the animation, well before the debounced branch swap below
            // actually happens -- close the sidebar column right away.
            // The still-on-screen SidebarNavigationView grows its detail
            // column to full width immediately, so by the time the swap
            // to the tab bar actually lands a moment later, the content
            // underneath is already the correct width instead of visibly
            // "catching up" right after the swap -- that's the flash/
            // hiccup this is fixing. Reopening it on the way back to
            // landscape works the same way, so a round trip doesn't leave
            // it collapsed.
            sectionState.isSidebarExpanded = useSidebarLayoutRaw

            if isSidebarLayoutCommitted == nil {
                isSidebarLayoutCommitted = useSidebarLayoutRaw
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            isSidebarLayoutCommitted = useSidebarLayoutRaw
        }
        .sheet(isPresented: Bindable(engine).isShowingNowPlayingSheet) {
            NowPlayingSheet()
        }
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { engine.lastError != nil },
                set: { if !$0 { engine.clearLastError() } }
            ),
            actions: { Button("OK") { engine.clearLastError() } },
            message: { Text(engine.lastError ?? "") }
        )
    }

    private var tabLayout: some View {
        TabView(selection: activeTabBinding) {
            Tab("Library", systemImage: "music.note.house", value: SidebarItem.library) {
                LibraryTabView(sectionState: sectionState)
            }
            Tab("New", systemImage: "sparkles", value: SidebarItem.new) {
                NewTabView()
            }
            Tab("Playlists", systemImage: "music.note.list", value: SidebarItem.playlists) {
                PlaylistsTabView()
            }
            Tab("Favorites", systemImage: "heart.fill", value: SidebarItem.favorites) {
                FavoritesTabView()
            }
            Tab("Downloads", systemImage: "arrow.down.circle", value: SidebarItem.downloads) {
                DownloadsTabView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: engine.currentSong != nil) {
            MiniPlayerBar(onTap: { engine.isShowingNowPlayingSheet = true })
        }
    }

    // Search/Personas/Albums/Songs don't have their own tab here -- they
    // only exist one level deep, pushed inside the Library tab (see
    // LibraryTabView) -- so the shared selection maps all four (plus
    // Library itself, plus "nothing chosen yet") onto the Library tab.
    // LibraryTabView is what actually pushes to the right one of those
    // four once sectionState.selection names one of them.
    private var activeTabBinding: Binding<SidebarItem> {
        Binding(
            get: {
                guard let selection = sectionState.selection,
                      !SidebarItem.nestedUnderLibraryTab.contains(selection) else {
                    return .library
                }
                return selection
            },
            set: { newTab in
                sectionState.selection = newTab
            }
        )
    }
}

private struct PlaceholderTab: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text("Coming soon.")
            )
            .navigationTitle(title)
        }
    }
}
