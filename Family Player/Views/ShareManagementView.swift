//
//  ShareManagementView.swift
//  Family Player
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ShareManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ShareAccessCoordinator.self) private var coordinator
    @Environment(LibraryScanner.self) private var scanner

    @Query(sort: \ShareBookmark.shareName) private var bookmarks: [ShareBookmark]

    @State private var selectingShare: String?
    @State private var isPickerPresented = false
    @State private var errorMessage: String?
    @State private var confirmRemoval: String?

    private var configuredNames: Set<String> {
        Set(bookmarks.map { $0.shareName })
    }

    private var availableToAdd: [String] {
        ShareAccessCoordinator.expectedShares.filter { !configuredNames.contains($0) }
    }

    private var duplicatedURLs: Set<URL> {
        var counts: [URL: Int] = [:]
        for url in coordinator.resolvedURLs.values {
            counts[url, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ShareInvitationsView()
                } label: {
                    Label("Accept iCloud Share Invitations", systemImage: "envelope.arrow.triangle.branch")
                }
            }

            if !bookmarks.isEmpty {
                Section("Connected Shares") {
                    ForEach(bookmarks) { bookmark in
                        bookmarkRow(bookmark)
                    }
                }
            }

            if !availableToAdd.isEmpty {
                Section("Add Share") {
                    ForEach(availableToAdd, id: \.self) { name in
                        Button {
                            beginPicking(name)
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text(name)
                                Spacer()
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            Section {
                Text("If the same folder is connected to two shares, songs will appear twice. Use Change Folder to fix a misassigned share, or Remove Share to disconnect it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Manage Shares")
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert(
            "Couldn't save folder",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "Remove Share?",
            isPresented: Binding(
                get: { confirmRemoval != nil },
                set: { if !$0 { confirmRemoval = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let name = confirmRemoval {
                    removeShare(name)
                }
                confirmRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                confirmRemoval = nil
            }
        } message: {
            Text("Removes the connection and deletes all songs from this share on this device. The shared folder in iCloud is not affected.")
        }
    }

    @ViewBuilder
    private func bookmarkRow(_ bookmark: ShareBookmark) -> some View {
        let url = coordinator.url(for: bookmark.shareName)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.shareName)
                    .font(.body.weight(.medium))
                if let url {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if url.lastPathComponent != bookmark.shareName {
                        Label("Folder name doesn't match", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if duplicatedURLs.contains(url) {
                        Label("Same folder as another share", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                } else {
                    Label("Could not resolve folder", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Menu {
                Button {
                    beginPicking(bookmark.shareName)
                } label: {
                    Label("Change Folder", systemImage: "folder")
                }
                Button(role: .destructive) {
                    confirmRemoval = bookmark.shareName
                } label: {
                    Label("Remove Share", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func beginPicking(_ shareName: String) {
        selectingShare = shareName
        isPickerPresented = true
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        defer { selectingShare = nil }
        guard let shareName = selectingShare else { return }

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try coordinator.saveBookmark(for: shareName, pickedURL: url, context: modelContext)
                // Trigger a rescan so the new content is indexed and orphans are pruned.
                Task {
                    await scanner.scan(coordinator: coordinator, context: modelContext)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func removeShare(_ shareName: String) {
        do {
            try coordinator.removeBookmark(for: shareName, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let songDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.shareName == shareName }
        )
        if let songs = try? modelContext.fetch(songDescriptor) {
            for song in songs {
                if let path = song.downloadCachePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
                let doomedID = song.stableID
                let entryDescriptor = FetchDescriptor<PlaylistEntry>(
                    predicate: #Predicate<PlaylistEntry> { $0.song?.stableID == doomedID }
                )
                if let entries = try? modelContext.fetch(entryDescriptor) {
                    for entry in entries {
                        modelContext.delete(entry)
                    }
                }
                modelContext.delete(song)
            }
        }

        let albumDescriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.shareName == shareName }
        )
        if let albums = try? modelContext.fetch(albumDescriptor) {
            for album in albums {
                if let path = album.artworkCachePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
                modelContext.delete(album)
            }
        }

        let personaDescriptor = FetchDescriptor<Persona>()
        if let personas = try? modelContext.fetch(personaDescriptor) {
            for persona in personas where persona.albums.isEmpty {
                modelContext.delete(persona)
            }
        }

        try? modelContext.save()
    }
}
