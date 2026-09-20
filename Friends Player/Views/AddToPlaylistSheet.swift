//
//  AddToPlaylistSheet.swift
//  Friends Player
//

import SwiftUI
import SwiftData

struct AddToPlaylistSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.dateCreated, order: .reverse) private var playlists: [Playlist]
    let song: Song

    @State private var showCreateSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("New Playlist", systemImage: "plus.circle.fill")
                    }
                }
                if !playlists.isEmpty {
                    Section("Add to") {
                        ForEach(playlists) { playlist in
                            Button {
                                addSong(to: playlist)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(playlist.name)
                                    Spacer()
                                    if alreadyContains(playlist) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\((playlist.entries ?? []).count)")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                }
                            }
                            .disabled(alreadyContains(playlist))
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreatePlaylistSheet(initialSong: song) { _ in
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func alreadyContains(_ playlist: Playlist) -> Bool {
        (playlist.entries ?? []).contains { $0.song?.stableID == song.stableID }
    }

    private func addSong(to playlist: Playlist) {
        guard !alreadyContains(playlist) else { return }
        let position = (playlist.entries ?? []).count
        let entry = PlaylistEntry(playlist: playlist, song: song, position: position)
        modelContext.insert(entry)
        try? modelContext.save()
    }
}
