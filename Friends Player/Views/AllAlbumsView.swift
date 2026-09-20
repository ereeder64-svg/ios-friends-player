//
//  AllAlbumsView.swift
//  Friends Player
//

import SwiftUI
import SwiftData

struct AllAlbumsView: View {
    @Environment(ShareAccessCoordinator.self) private var coordinator
    @Query(sort: \Album.title) private var albums: [Album]
    @State private var searchText = ""

    private let columns = AdaptiveTileGrid.columns

    // Only show albums from shares this device actually has connected --
    // Song/Album sync globally via CloudKit, but a share this device hasn't
    // linked has no local file access, so it'd just show placeholder
    // artwork and fail to play.
    private var reachableAlbums: [Album] {
        albums.filter { coordinator.connectedShareNames.contains($0.shareName) }
    }

    private var filteredAlbums: [Album] {
        guard !searchText.isEmpty else { return reachableAlbums }
        let q = searchText.lowercased()
        return reachableAlbums.filter { album in
            album.title.lowercased().contains(q) ||
            (album.persona?.name.lowercased().contains(q) ?? false)
        }
    }

    private var allSongs: [Song] {
        filteredAlbums.flatMap { album in
            (album.songs ?? []).sorted { ($0.trackNumber ?? 0, $0.title) < ($1.trackNumber ?? 0, $1.title) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PlayShuffleButtons(songs: allSongs)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filteredAlbums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            AlbumTile(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Albums")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search albums or personas"
        )
        .toolbar {
            if !allSongs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        BulkDownloadMenuItems(songs: allSongs, label: "All Albums")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .overlay {
            if albums.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack")
            } else if filteredAlbums.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

struct AlbumDetailView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.songRowLayout) private var rowLayout
    let album: Album

    // The album's own name is already the screen title, so it'd be
    // redundant as a per-row column -- but on iPad there's real width
    // going unused next to the title. Fill it with the persona/artist
    // name instead (still nothing on iPhone: compact rows stay exactly
    // as they were, title-only, no subtitle).
    private var rowSubtitleMode: SongListRow.SubtitleMode {
        rowLayout == .compact ? .none : .artistOnly
    }

    private var sortedSongs: [Song] {
        (album.songs ?? []).sorted { ($0.trackNumber ?? 0, $0.title) < ($1.trackNumber ?? 0, $1.title) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AlbumArtworkView(
                    cachePath: album.artworkCachePath,
                    title: album.title,
                    size: 260,
                    cornerRadius: 12
                )
                .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
                .padding(.top, 24)

                VStack(spacing: 4) {
                    Text(album.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if let persona = album.persona {
                        Text(persona.name)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text("\((album.songs ?? []).count) song\((album.songs ?? []).count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal)

                PlayShuffleButtons(songs: sortedSongs)
                    .padding(.horizontal)

                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedSongs.enumerated()), id: \.element.stableID) { idx, song in
                        SongListRow(song: song, scope: sortedSongs, style: .dark, subtitleMode: rowSubtitleMode)
                            .padding(.vertical, 6)
                        if idx < sortedSongs.count - 1 {
                            Divider()
                                .background(.white.opacity(0.15))
                                .padding(.leading, 48)
                        }
                    }
                }
                .padding(.horizontal)

                SongsCountFooter(songs: sortedSongs, style: .dark)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
        }
        .background(albumBackground)
        // No .navigationTitle here on purpose -- the album title is
        // already shown below the artwork; a second copy of it up in the
        // nav bar was pure redundancy.
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    BulkDownloadMenuItems(songs: sortedSongs, label: "Album")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        // Reachable from Albums, Personas, Search, and Playlists -- this
        // is the "song view" that had no way back to the drawer once the
        // iPad sidebar was collapsed.
        .sidebarDrawerToolbar()
    }

    @ViewBuilder
    private var albumBackground: some View {
        if let path = album.artworkCachePath,
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 80)
                .overlay(Color.black.opacity(0.45))
                .ignoresSafeArea()
        } else {
            let tint = AlbumArtworkView.accentColor(for: album.title)
            LinearGradient(
                colors: [tint.opacity(0.55), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}


