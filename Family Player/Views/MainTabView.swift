//
//  MainTabView.swift
//  Family Player
//

import SwiftUI

struct MainTabView: View {
    @Environment(PlaybackEngine.self) private var engine
    @State private var showNowPlaying = false

    var body: some View {
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
            Tab(role: .search) {
                SearchTabView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: engine.currentSong != nil) {
            MiniPlayerBar(onTap: { showNowPlaying = true })
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingSheet()
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
