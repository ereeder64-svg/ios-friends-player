//
//  SidebarNavigationView.swift
//  Friends Player
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
enum SidebarItem: String, Identifiable, CaseIterable, Hashable {
    case search
    case new
    case personas
    case albums
    case songs
    case genres
    case playlists
    case favorites
    case downloads
    case library

    var id: String { rawValue }

    // On iPhone/portrait's tab bar these five don't get their own tab --
    // they only exist one level deep, pushed inside the Library tab.
    // Landscape's flat sidebar treats them (and Library itself) as equal
    // top-level items. This is the mapping used to reconcile the two
    // whenever the cross-orientation selection needs to pick an actual
    // tab-bar destination (see MainTabView.activeTabBinding) or decide
    // whether Library's own NavigationStack should have something pushed
    // (see LibraryTabView).
    static let nestedUnderLibraryTab: Set<SidebarItem> = [.search, .personas, .albums, .songs, .genres]

    var title: String {
        switch self {
        case .search: return "Search"
        case .new: return "New"
        case .personas: return "Personas"
        case .albums: return "Albums"
        case .songs: return "Songs"
        case .genres: return "Genres"
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
        case .genres: return "guitars"
        case .playlists: return "music.note.list"
        case .favorites: return "heart.fill"
        case .downloads: return "arrow.down.circle"
        case .library: return "music.note.house"
        }
    }
}

struct SidebarNavigationView: View {
    @Environment(PlaybackEngine.self) private var engine
    // Owned here and pushed into the environment for every screen inside
    // detailContent's NavigationStack (see SidebarDrawerToolbar.swift) --
    // that's what lets a pushed Persona/Album/Playlist detail screen (or
    // anything else drilled into) still show the reopen button and get
    // back to the drawer, instead of only the root page of each section
    // having it.
    // Owned by MainTabView (which never gets torn down when the device
    // rotates) and passed in here, instead of being a local @State --
    // that's what lets "which section you're on" survive the
    // landscape-sidebar <-> portrait-tab-bar swap, since that swap
    // recreates this whole view from scratch every time.
    @Bindable var drawerState: SidebarDrawerState
    @State private var detailWidth: CGFloat = 0

    private let sidebarWidth: CGFloat = 260

    // Extra breathing room between the sidebar's divider and the detail
    // column's own content (title, search bar, play pill, song rows).
    // Only needed when the sidebar is actually showing -- when it's
    // collapsed, the detail column already starts at the screen edge and
    // everything lines up correctly on its own (system nav title/search
    // inset matches the custom 20pt padding used elsewhere). With the
    // sidebar open, the system title/search chrome hugs the divider much
    // more tightly than the custom-padded content below it, so without
    // this the "Albums"/"Playlists"/"Personas" title and search field
    // visually stick to the divider while the Play pill and song rows
    // sit further right.
    private let sidebarContentBuffer: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if drawerState.isSidebarExpanded {
                    sidebarColumn
                        .frame(width: sidebarWidth)
                    Divider()
                }
                detailContent
                    .padding(.leading, drawerState.isSidebarExpanded ? sidebarContentBuffer : 0)
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
                Text("Friends Player")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        drawerState.isSidebarExpanded = false
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .accessibilityLabel("Hide Sidebar")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)

            List(selection: $drawerState.selection) {
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
            detailView(for: drawerState.selection ?? .albums)
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
                .sidebarDrawerToolbar()
        }
        .id(drawerState.selection)
        // Both of these need to live OUTSIDE the NavigationStack, not on the
        // root content inside it. A view pushed via NavigationLink (e.g.
        // Albums -> a specific album) inherits environment from where the
        // NavigationStack itself sits, not from modifiers stuck onto
        // whichever root page happens to be showing at the time -- that's
        // why sidebarDrawerState (already out here) reaches pushed screens
        // fine, while songRowLayout, when it lived inside on detailView(...),
        // silently fell back to its .compact default for every pushed
        // screen even though the root page read the right value.
        .environment(
            \.songRowLayout,
            SongRowLayoutMode.resolve(width: detailWidth, horizontalSizeClass: .regular)
        )
        .environment(\.sidebarDrawerState, drawerState)
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
        case .genres:
            GenresListView()
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
