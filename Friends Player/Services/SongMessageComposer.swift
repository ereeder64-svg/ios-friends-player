//
//  SongMessageComposer.swift
//  Friends Player
//

import Messages
import MessageUI
import UIKit

/// Sends a song as an iMessage app bubble -- the app icon with the song
/// title, no visible link. Tapping the bubble wakes this app's Messages
/// extension on the recipient's phone, which opens the app with the
/// SongShareLink URL carried inside the message.
///
/// Only works when the recipient runs THIS app (the bubble belongs to this
/// app's extension), so sends to the other app still go out as a plain
/// text link -- see SendSongLinks.
@MainActor
final class SongMessageComposer: NSObject, MFMessageComposeViewControllerDelegate {
    static let shared = SongMessageComposer()

    /// False on the simulator and on devices without Messages set up.
    static var canSendBubble: Bool { MFMessageComposeViewController.canSendText() }

    func present(song: Song, sender: String) {
        let target = SongShareLink.Target.current
        guard let url = SongShareLink.bubbleURL(for: song, sender: sender) else { return }

        let layout = MSMessageTemplateLayout()
        layout.image = UIImage(named: target.iconAssetName)
        layout.caption = SongShareLink.title(of: song)
        layout.subcaption = song.album?.persona?.name
        layout.trailingSubcaption = sender.isEmpty ? nil : "from \(sender)"

        let message = MSMessage()
        message.layout = layout
        message.url = url
        message.summaryText = SongShareLink.intro(for: song, sender: sender)

        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = self
        composer.message = message

        // Called from a Menu item; let the menu finish dismissing first.
        DispatchQueue.main.async {
            Self.topViewController()?.present(composer, animated: true)
        }
    }

    nonisolated func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        Task { @MainActor in controller.dismiss(animated: true) }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
