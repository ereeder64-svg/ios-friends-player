//
//  PlaylistCollageView.swift
//  Family Player
//

import SwiftUI

struct PlaylistCollageView: View {
    let cachePaths: [String]
    let title: String
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            switch cachePaths.count {
            case 0:
                AlbumArtworkView(cachePath: nil, title: title, cornerRadius: cornerRadius)
            case 1:
                AlbumArtworkView(cachePath: cachePaths[0], title: title, cornerRadius: cornerRadius)
            default:
                grid
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                quadrant(0)
                quadrant(1)
            }
            HStack(spacing: 0) {
                quadrant(2)
                quadrant(3)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    private func quadrant(_ idx: Int) -> some View {
        let path = idx < cachePaths.count ? cachePaths[idx] : nil
        if let path, let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .aspectRatio(1, contentMode: .fit)
                .clipped()
        } else {
            AlbumArtworkView.accentColor(for: title)
                .opacity(0.4)
                .aspectRatio(1, contentMode: .fit)
        }
    }
}
