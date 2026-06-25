//
//  AppIconPicker.swift
//  Family Player
//

import SwiftUI
import UIKit

struct AppIconPicker: View {
    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 20) {
            iconOption(name: nil, label: "Red", imageName: "AppIconPreview-Red")
            iconOption(name: "BlackIcon", label: "Black", imageName: "AppIconPreview-Black")
            iconOption(name: "WhiteIcon", label: "White", imageName: "AppIconPreview-White")
            Spacer()
        }
        .padding(.vertical, 4)
        .alert(
            "Couldn't Change Icon",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: { Button("OK") { errorMessage = nil } },
            message: { Text(errorMessage ?? "") }
        )
    }

    @ViewBuilder
    private func iconOption(name: String?, label: String, imageName: String) -> some View {
        let isSelected = current == name
        Button {
            select(name)
        } label: {
            VStack(spacing: 6) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 3 : 1)
                    }
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func select(_ name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "Alternate icons aren't available on this device."
            return
        }
        guard current != name else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            DispatchQueue.main.async {
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    current = name
                }
            }
        }
    }
}
