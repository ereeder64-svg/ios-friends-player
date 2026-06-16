//
//  SetupView.swift
//  Family Player
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var coordinator: ShareAccessCoordinator
    let onComplete: () -> Void

    @State private var selectingShare: String?
    @State private var isPickerPresented = false
    @State private var configured: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect Your Shared Folders")
                            .font(.title2.bold())
                        Text("For each folder you have access to, tap Select and navigate to it in iCloud Drive \u{2192} Shared. Skip any you don't have access to.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    NavigationLink {
                        ShareInvitationsView()
                    } label: {
                        Label("Haven't accepted your invitations yet?", systemImage: "envelope.arrow.triangle.branch")
                    }
                }

                Section("Shared Folders") {
                    ForEach(ShareAccessCoordinator.expectedShares, id: \.self) { shareName in
                        HStack {
                            Image(systemName: configured.contains(shareName)
                                  ? "checkmark.circle.fill"
                                  : "folder")
                                .foregroundStyle(configured.contains(shareName) ? .green : .secondary)
                            Text(shareName)
                            Spacer()
                            Button(configured.contains(shareName) ? "Change" : "Select") {
                                selectingShare = shareName
                                isPickerPresented = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .navigationTitle("Setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        onComplete()
                    }
                    .disabled(configured.isEmpty)
                }
            }
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
            .onAppear {
                configured = Set(coordinator.resolvedURLs.keys)
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        defer { selectingShare = nil }
        guard let shareName = selectingShare else { return }

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try coordinator.saveBookmark(for: shareName, pickedURL: url, context: modelContext)
                configured.insert(shareName)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
