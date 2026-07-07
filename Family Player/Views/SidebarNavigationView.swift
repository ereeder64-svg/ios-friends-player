//
//  SidebarNavigationView.swift
//  Family Player
//

import SwiftUI

/// iPad-landscape navigation, modeled on Apple Music's sidebar.
///
/// Deliberately NOT built on NavigationSplitView: that API's own collapse
/// behavior leaves a persistent leading "rail" and its own automatic
/// sidebar-toggle control, which alongside a custom toggle button produced
/// two separate closed-drawer-looking buttons at once with no way back to
/// a single one. Instead this is a plain HStack whose leading column is
/// either fully present or fully gone:
///   - Expanded: sidebar column (with its own collapse button in its
///     header) + detail. No extra chrome on the detail side.
///   - Collapsed: sidebar column is completely removed (not minimized to a
///     rail); the detail side's own top toolbar takes over navigation,
///     showing a drawer-reopen button plus one icon per section. Tapping
///     the drawer button there brings the sidebar column back and that
///     toolbar row disappears -- there is only ever one "drawer" control
///     visible at a time.
enum SidebarItem: String, Identifiable, CaseIterable {
    case search
    case new
    case personas
    case albums
    case songs
    case playlists
    case favorites
    case downloads
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: return "Search"
        case .new: return "New"
        case .personas: return "Personas"
        case .albums: return "Albums"
        case .songs: return "Songs"
        case .playlists: return "Playlists"
        case .favorites: return "Favorites"
        case .downloads: return "Downloads"
        case .library: return "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .search: return "magnifyingglass"
        case .new: return "sparkles"
        case .personas: return "person.2"
        case .albums: return "square.stack"
        case .songs: return "music.note"
        case .playlists: return "music.note.list"
        case .favorites: return "heart.fill"
        case .downloads: return "arrow.down.circle"
        case .library: return "music.note.house"
        }
    }
}

struct SidebarNavigationView: View {
    @Environment(PlaybackEngine.self) private var engine
    @State private var selection: SidebarItem? = .albums
    @State private var isSidebarExpanded = true
    @State private var detailWidth: CGFloat = 0

    private let sidebarWidth: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if isSidebarExpanded {
                    sidebarColumn
                        .frame(width: sidebarWidth)
                    Divider()
                }
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // NavigationSplitView has no equivalent of TabView's
            // .tabViewBottomAccessory, so the mini player is pinned here
            // instead, spanning the full width beneath both columns --
            // matching where Apple Music puts it on iPad.
            if engine.currentSong != nil {
                Divider()
                MiniPlayerBar(onTap: { engine.isShowingNowPlayingSheet = true })
                    .frame(height: 56)
                    .background(.bar)
            }
        }
    }

    // MARK: - Sidebar column

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Family Player")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSidebarExpanded = false
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .accessibilityLabel("Hide Sidebar")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)

            List(selection: $selection) {
                Section {
                    sidebarRow(.search)
                    sidebarRow(.new)
                }
                Section("Library") {
                    sidebarRow(.personas)
                    sidebarRow(.albums)
                    sidebarRow(.songs)
                    sidebarRow(.playlists)
                    sidebarRow(.favorites)
                    sidebarRow(.downloads)
                }
                Section {
                    sidebarRow(.library)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .tag(item)
    }

    // MARK: - Detail column

    // Everything lives inside ONE shared NavigationStack so that both my
    // collapsed-toolbar content and each page's own toolbar items (e.g.
    // Favorites' bulk-download menu) actually merge into a single real nav
    // bar. A .toolbar{} applied from outside a NavigationStack -- as a
    // modifier chained onto its return value, or onto a switch whose case
    // returns a self-wrapped NavigationStack -- never merges into that
    // stack's bar, which is why the collapsed reopen button used to
    // silently fail to appear. .id(selection) resets the stack (and any
    // pushed navigation state) whenever the sidebar selection changes, so
    // switching sections doesn't leave a stale pushed detail view behind.
    private var detailContent: some View {
        NavigationStack {
            detailView(for: selection ?? .albums)
                // The detail column's actual rendered width is what determines
                // how much room a song row has -- it shrinks when the sidebar
                // is showing and grows to the full screen width once it's
                // collapsed, which is exactly the signal used to decide
                // whether to add the album column.
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newValue in
                    detailWidth = newValue
                }
                .environment(
                    \.songRowLayout,
                    SongRowLayoutMode.resolve(width: detailWidth, horizontalSizeClass: .regular)
                )
                .toolbar { collapsedToolbarContent }
        }
        .id(selection)
    }

    // Only present while the sidebar is hidden -- this is the "top menu"
    // that takes over its job: a button to bring the sidebar back, plus
    // one icon per section so the sections are still reachable without
    // reopening it.
    @ToolbarContentBuilder
    private var collapsedToolbarContent: some ToolbarContent {
        if !isSidebarExpanded {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSidebarExpanded = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .accessibilityLabel("Show Sidebar")
            }
            ToolbarItemGroup(placement: .navigationBarLeading) {
                ForEach(SidebarItem.allCases) { item in
                    Button {
                        selection = item
                    } label: {
                        Image(systemName: item.systemImage)
                    }
                    .foregroundStyle(selection == item ? Color.accentColor : Color.secondary)
                    .accessibilityLabel(item.title)
                }
            }
        }
    }

    // All of these are the bare *Content variants (no internal
    // NavigationStack) -- the single NavigationStack in detailContent is
    // the only one, so every page's own .toolbar/.navigationTitle/
    // .searchable and my collapsed-toolbar content all merge into it.
    // (NewTabView/FavoritesTabView/PlaylistsTabView/DownloadsTabView/
    // LibraryTabView remain thin NavigationStack-wrapping structs for use
    // in the iPhone tab bar, unaffected by this.)
    @ViewBuilder
    private func detailView(for item: SidebarItem) -> some View {
        switch item {
        case .search:
            SearchTabView()
        case .new:
            NewTabContent()
        case .personas:
            PersonasListView()
        case .albums:
            AllAlbumsView()
        case .songs:
            AllSongsView()
        case .playlists:
            PlaylistsTabContent()
        case .favorites:
            FavoritesTabContent()
        case .downloads:
            DownloadsTabContent()
        case .library:
            LibraryTabContent()
        }
    }
}
