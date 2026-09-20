//
//  AlbumArtworkView.swift
//  Friends Player
//

import SwiftUI

struct AlbumArtworkView: View {
    let cachePath: String?
    let title: String
    var size: CGFloat? = nil
    var cornerRadius: CGFloat = 6

    var body: some View {
        artwork
            .modifier(SquareSize(size: size))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    private var artwork: some View {
        if let path = cachePath,
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Self.accentColor(for: title), Self.accentColor(for: title).opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(String(title.prefix(1)).uppercased())
                    .font(.system(size: geo.size.width * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    static func accentColor(for title: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .mint, .red, .brown]
        let hash = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

private struct SquareSize: ViewModifier {
    let size: CGFloat?

    func body(content: Content) -> some View {
        if let size {
            content.frame(width: size, height: size)
        } else {
            content.aspectRatio(1, contentMode: .fit)
        }
    }
}
