//
//  PersonasListView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct PersonasListView: View {
    @Query(sort: \Persona.name) private var personas: [Persona]
    @State private var searchText = ""

    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]

    private var filteredPersonas: [Persona] {
        guard !searchText.isEmpty else { return personas }
        let q = searchText.lowercased()
        return personas.filter { $0.name.lowercased().contains(q) }
    }

    private var allSongs: [Song] {
        filteredPersonas.flatMap { persona in
            (persona.albums ?? [])
                .sorted { $0.title < $1.title }
                .flatMap { album in
                    (album.songs ?? []).sorted { ($0.trackNumber ?? 0, $0.title) < ($1.trackNumber ?? 0, $1.title) }
                }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PlayShuffleButtons(songs: allSongs)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filteredPersonas) { persona in
                        NavigationLink {
                            PersonaDetailView(persona: persona)
                        } label: {
                            PersonaTile(persona: persona)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Personas")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search personas"
        )
        .toolbar {
            if !allSongs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        BulkDownloadMenuItems(songs: allSongs, label: "All Personas")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .overlay {
            if personas.isEmpty {
                ContentUnavailableView(
                    "No Personas",
                    systemImage: "person.2",
                    description: Text("Scan the library to populate.")
                )
            } else if filteredPersonas.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

struct PersonaDetailView: View {
    let persona: Persona

    private var sortedAlbums: [Album] {
        (persona.albums ?? []).sorted { $0.title < $1.title }
    }

    private var allSongs: [Song] {
        sortedAlbums.flatMap { album in
            (album.songs ?? []).sorted { ($0.trackNumber ?? 0, $0.title) < ($1.trackNumber ?? 0, $1.title) }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PlayShuffleButtons(songs: allSongs)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(sortedAlbums) { album in
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
        .navigationTitle(persona.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    BulkDownloadMenuItems(songs: allSongs, label: "Persona")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
