//
//  MainTabView.swift
//  Family Player
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

    private var useSidebarLayout: Bool {
        horizontalSizeClass == .regular && containerSize.width > containerSize.height
    }

    var body: some View {
        Group {
            if useSidebarLayout {
                SidebarNavigationView()
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
        TabView {
            Tab("Library", systemImage: "music.note.house") {
                LibraryTabView()
            }
            Tab("New", systemImage: "sparkles") {
                NewTabView()
            }
            Tab("Playlists", systemImage: "music.note.list") {
                PlaylistsTabView()
            }
            Tab("Favorites", systemImage: "heart.fill") {
                FavoritesTabView()
            }
            Tab("Downloads", systemImage: "arrow.down.circle") {
                DownloadsTabView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: engine.currentSong != nil) {
            MiniPlayerBar(onTap: { engine.isShowingNowPlayingSheet = true })
        }
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
