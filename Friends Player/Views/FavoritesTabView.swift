//
//  FavoritesTabView.swift
//  Friends Player
//

import SwiftUI
import SwiftData

struct FavoritesTabView: View {
    var body: some View {
        NavigationStack {
            FavoritesTabContent()
        }
    }
}

private enum FavoritesScope: String, CaseIterable {
    case mine = "Mine"
    case family = "Family"
}

struct FavoritesTabContent: View {
    @Query(
        filter: #Predicate<Song> { $0.isFavorite },
        sort: \Song.title
    )
    private var allFavoriteSongs: [Song]
    @Query private var allSongs: [Song]
    @Environment(ShareAccessCoordinator.self) private var coordinator
    @Environment(FavoritesSharingService.self) private var favoritesSharing
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var scope: FavoritesScope = .mine

    private var favoriteSongs: [Song] {
        allFavoriteSongs.filter { coordinator.connectedShareNames.contains($0.shareName) }
    }

    private var filteredSongs: [Song] {
        let base: [Song]
        if searchText.isEmpty {
            base = Array(favoriteSongs)
        } else {
            let q = searchText.lowercased()
            base = favoriteSongs.filter { song in
                song.title.lowercased().contains(q) ||
                (song.album?.title.lowercased().contains(q) ?? false) ||
                (song.album?.persona?.name.lowercased().contains(q) ?? false)
            }
        }
        return base.sortedByAlbumThenTitle()
    }

    // Maps each merged family favorite back to a locally-known Song, when
    // this device happens to have that share connected. Family members
    // share the same underlying iCloud Drive folders, so this resolves for
    // most songs -- but not necessarily all of them.
    private var localSongsByStableID: [String: Song] {
        Dictionary(
            allSongs
                .filter { coordinator.connectedShareNames.contains($0.shareName) }
                .map { ($0.stableID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Favorites Scope", selection: $scope) {
                    ForEach(FavoritesScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                switch scope {
                case .mine:
                    mineContent
                case .family:
                    familyContent
                }
            }
            .padding(.bottom, 16)
        }
        .refreshable {
            await favoritesSharing.refresh(context: modelContext)
        }
        .onChange(of: scope) { _, newScope in
            guard newScope == .family else { return }
            Task { await favoritesSharing.refresh(context: modelContext) }
        }
        .navigationTitle("Favorites")
        .toolbar {
            if scope == .mine, !favoriteSongs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        BulkDownloadMenuItems(songs: Array(favoriteSongs), label: "All Favorites")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            if scope == .family {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        FavoritesSharingSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search favorites"
        )
    }

    @ViewBuilder
    private var mineContent: some View {
        PlayShuffleButtons(songs: filteredSongs)
            .padding(.horizontal, 20)

        SongListSection(songs: filteredSongs)

        if !filteredSongs.isEmpty {
            SongsCountFooter(songs: filteredSongs)
                .padding(.horizontal, 20)
                .padding(.top, 4)
        }

        if favoriteSongs.isEmpty {
            ContentUnavailableView(
                "No Favorites Yet",
                systemImage: "heart",
                description: Text("Tap the heart icon while playing, or open a song's menu to add favorites.")
            )
            .padding(.top, 40)
        } else if filteredSongs.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .padding(.top, 40)
        }
    }

    private var filteredFamilyFavorites: [FamilyFavorite] {
        guard !searchText.isEmpty else { return favoritesSharing.familyFavorites }
        let q = searchText.lowercased()
        return favoritesSharing.familyFavorites.filter {
            $0.title.lowercased().contains(q) ||
            $0.albumTitle.lowercased().contains(q) ||
            $0.personaName.lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var familyContent: some View {
        if favoritesSharing.familyFavorites.isEmpty {
            ContentUnavailableView(
                favoritesSharing.isSharingEnabled ? "No Family Favorites Yet" : "Favorites Sharing Is Off",
                systemImage: "person.2",
                description: Text(
                    favoritesSharing.isSharingEnabled
                        ? "Once family members share their favorites too, they'll show up here."
                        : "Turn on sharing from the gear icon above to see and share family favorites."
                )
            )
            .padding(.top, 40)
        } else if filteredFamilyFavorites.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .padding(.top, 40)
        } else {
            FamilyFavoritesSection(
                favorites: filteredFamilyFavorites,
                localSongsByStableID: localSongsByStableID
            )
        }
        if favoritesSharing.isRefreshing {
            ProgressView()
                .padding(.top, 8)
        }
        if let lastError = favoritesSharing.lastError {
            Text(lastError)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        }
    }
}

// MARK: - Family Favorites list

private struct FamilyFavoritesSection: View {
    let favorites: [FamilyFavorite]
    let localSongsByStableID: [String: Song]

    private let horizontalInset: CGFloat = 20

    private var localSongsInOrder: [Song] {
        favorites.compactMap { localSongsByStableID[$0.stableID] }
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(favorites.enumerated()), id: \.element.stableID) { idx, favorite in
                FamilyFavoriteRow(
                    favorite: favorite,
                    localSong: localSongsByStableID[favorite.stableID],
                    scope: localSongsInOrder
                )
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, 6)
                if idx < favorites.count - 1 {
                    Divider().padding(.leading, horizontalInset + 56)
                }
            }
        }
    }
}

private struct FamilyFavoriteRow: View {
    let favorite: FamilyFavorite
    let localSong: Song?
    let scope: [Song]

    var body: some View {
        HStack(spacing: 8) {
            if let localSong {
                SongListRow(song: localSong, scope: scope)
            } else {
                // A family member favorited this from a share this device
                // doesn't have connected -- show what we know, no playback.
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(favorite.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if !favorite.personaName.isEmpty { Text(favorite.personaName) }
                            if !favorite.albumTitle.isEmpty {
                                Text("\u{2022}")
                                Text(favorite.albumTitle)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                }
            }
            FamilyFavoriteCountBadge(owners: favorite.owners)
        }
    }
}

private struct FamilyFavoriteCountBadge: View {
    let owners: [String]
    @State private var showingOwners = false

    var body: some View {
        Button {
            showingOwners = true
        } label: {
            Text("\(owners.count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingOwners) {
            // A List here (even with an explicit idealHeight) clipped its
            // own row content in a popover this small -- a plain VStack
            // sized to its natural content height doesn't have that
            // problem, and the owner count is always small (family-sized).
            VStack(alignment: .leading, spacing: 10) {
                ForEach(owners, id: \.self) { name in
                    Text(name)
                        .font(.subheadline)
                }
            }
            .padding()
            .frame(minWidth: 140, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Sharing settings

struct FavoritesSharingSettingsView: View {
    @Environment(FavoritesSharingService.self) private var favoritesSharing
    @Environment(\.modelContext) private var modelContext
    @State private var displayName: String = ""
    @State private var shareURL: URL?
    @State private var isWorking = false
    @State private var showDisableConfirm = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Toggle("Share My Favorites", isOn: Binding(
                        get: { favoritesSharing.isSharingEnabled },
                        set: { newValue in
                            if newValue {
                                Task { await enable() }
                            } else {
                                showDisableConfirm = true
                            }
                        }
                    ))
                    if isWorking {
                        ProgressView()
                    }
                }
            } footer: {
                Text("Shares your favorited songs, read-only, with the rest of the family. Turning this off immediately revokes their access.")
            }

            Section {
                TextField("e.g. Chris", text: $displayName)
                    .textInputAutocapitalization(.words)
                if favoritesSharing.isSharingEnabled {
                    Button("Update Name") {
                        Task { await updateName() }
                    }
                    .disabled(
                        displayName.trimmingCharacters(in: .whitespaces).isEmpty ||
                        displayName == favoritesSharing.ownerDisplayName
                    )
                }
            } header: {
                Text("Your Name")
            } footer: {
                Text("Shown to family members next to the songs you've favorited.")
            }

            if favoritesSharing.isSharingEnabled, let shareURL {
                Section("Invite Link") {
                    ShareLink(item: shareURL) {
                        Label("Send Invite Link", systemImage: "square.and.arrow.up")
                    }
                    Text(shareURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let lastError = favoritesSharing.lastError {
                Section {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Family Favorites")
        .disabled(isWorking)
        .alert("Stop Sharing Favorites?", isPresented: $showDisableConfirm) {
            Button("Stop Sharing", role: .destructive) {
                Task { await disable() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The rest of the family will immediately lose access to your favorites list.")
        }
        .task {
            displayName = favoritesSharing.ownerDisplayName
            if favoritesSharing.isSharingEnabled {
                shareURL = await favoritesSharing.currentShareURL()
            }
        }
    }

    private func updateName() async {
        isWorking = true
        defer { isWorking = false }
        await favoritesSharing.updateOwnerName(displayName, context: modelContext)
    }

    private func enable() async {
        isWorking = true
        defer { isWorking = false }
        let name = displayName.trimmingCharacters(in: .whitespaces)
        shareURL = await favoritesSharing.enableSharing(
            displayName: name.isEmpty ? "Family" : name,
            context: modelContext
        )
    }

    private func disable() async {
        isWorking = true
        defer { isWorking = false }
        await favoritesSharing.disableSharing()
        shareURL = nil
    }
}
