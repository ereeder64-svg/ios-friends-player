//
//  CreatePlaylistSheet.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct CreatePlaylistSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var initialSong: Song? = nil
    var onCreated: ((Playlist) -> Void)? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Playlist Name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                if let song = initialSong {
                    Section("First Song") {
                        HStack {
                            AlbumArtworkView(
                                cachePath: song.album?.artworkCachePath,
                                title: song.album?.title ?? song.displayTitle,
                                size: 36,
                                cornerRadius: 4
                            )
                            VStack(alignment: .leading) {
                                Text(song.displayTitle).font(.subheadline)
                                Text(song.album?.persona?.name ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        let playlist = Playlist(name: trimmed)
                        modelContext.insert(playlist)
                        if let song = initialSong {
                            let entry = PlaylistEntry(playlist: playlist, song: song, position: 0)
                            modelContext.insert(entry)
                        }
                        try? modelContext.save()
                        onCreated?(playlist)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .presentationDetents([.medium])
        }
    }
}

struct RenamePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var name: String

    init(playlist: Playlist) {
        self.playlist = playlist
        _name = State(initialValue: playlist.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Playlist Name", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Rename Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        playlist.name = trimmed
                        try? playlist.modelContext?.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .presentationDetents([.medium])
        }
    }
}
