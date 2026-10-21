//
//  MessagesViewController.swift
//  Friends Player Messages Extension
//

import Messages
import UIKit

// The bubble a "Send Song" message arrives in belongs to this extension.
// When the recipient taps it, Messages wakes this extension with the
// tapped message; all it does is hand the message's link to the main app,
// whose onOpenURL (RootView) finds the song and plays it.
final class MessagesViewController: MSMessagesAppViewController {

    private var lastOpened: (url: URL, at: Date)?

    override func viewDidLoad() {
        super.viewDidLoad()
        let hint = UILabel()
        hint.text = "To send a song, open Friends Player and tap the paper-plane button on Now Playing."
        hint.numberOfLines = 0
        hint.textAlignment = .center
        hint.textColor = .secondaryLabel
        hint.font = .preferredFont(forTextStyle: .body)
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hint.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }

    // Tapping a bubble while the extension isn't running.
    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        openApp(for: conversation.selectedMessage)
    }

    // Tapping a bubble while the extension is already open.
    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        openApp(for: message)
    }

    private func openApp(for message: MSMessage?) {
        guard let url = message?.url else { return }
        // willBecomeActive and didSelect can both fire for one tap.
        if let last = lastOpened, last.url == url, Date().timeIntervalSince(last.at) < 2 { return }
        lastOpened = (url, Date())
        extensionContext?.open(url) { [weak self] _ in
            DispatchQueue.main.async { self?.dismiss() }
        }
    }
}
