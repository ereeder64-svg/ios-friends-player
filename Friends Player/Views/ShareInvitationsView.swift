//
//  ShareInvitationsView.swift
//  Friends Player
//

import SwiftUI
import SwiftData

struct ShareInvitationsView: View {
    // ShareBookmark lives in its own local-only ModelContainer (not the
    // app's shared/synced one), so it can't be read via @Query here.
    @Environment(ShareAccessCoordinator.self) private var coordinator

    private var connectedNames: Set<String> {
        Set(coordinator.configuredShareNames())
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accept Your Shared Folders")
                        .font(.headline)
                    Text("Tap each share below to open its invitation. iCloud will prompt you to add it to your iCloud Drive. You only need to do this once per share, per device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Share Invitations") {
                ForEach(ShareAccessCoordinator.expectedShares, id: \.self) { name in
                    inviteRow(for: name)
                }
            }

            Section {
                Text("After accepting, return to this app and use Setup or Manage Shares to connect the folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Accept Shares")
        .sidebarDrawerToolbar()
    }

    @ViewBuilder
    private func inviteRow(for name: String) -> some View {
        if let urlString = ShareInvitations.urls[name],
           let url = URL(string: urlString) {
            Button {
                UIApplication.shared.open(url)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: connectedNames.contains(name)
                          ? "checkmark.circle.fill"
                          : "arrow.up.right.square")
                        .foregroundStyle(connectedNames.contains(name) ? .green : .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.body)
                        Text(connectedNames.contains(name)
                             ? "Already connected in the app"
                             : "Tap to open invitation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        } else {
            Text(name)
                .foregroundStyle(.secondary)
        }
    }
}
