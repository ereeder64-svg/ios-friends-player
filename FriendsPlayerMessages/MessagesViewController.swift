//
//  MessagesViewController.swift
//  Friends Player Messages Extension
//

import Messages
import UIKit

// The bubble a "Send Song" message arrives in belongs to this extension.
// Tapping it wakes this extension with the tapped message, which opens the
// main app straight away with the song's link (RootView's onOpenURL finds
// and plays it). The song card with its "Play in <App>" button is only a
// fallback in case iOS ever declines to open the app.
final class MessagesViewController: MSMessagesAppViewController {

    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "the app"
    private var songURL: URL?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playButton = UIButton(configuration: .filled())
    private let hintLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        for label in [titleLabel, subtitleLabel, hintLabel] {
            label.numberOfLines = 0
            label.textAlignment = .center
        }

        var config = UIButton.Configuration.filled()
        config.title = "Play in \(appName)"
        config.image = UIImage(systemName: "play.fill")
        config.imagePadding = 8
        config.cornerStyle = .capsule
        config.buttonSize = .large
        playButton.configuration = config
        playButton.addAction(UIAction { [weak self] _ in self?.openApp() }, for: .primaryActionTriggered)

        hintLabel.text = "To send a song, open \(appName) and tap the paper-plane button on Now Playing."
        hintLabel.textColor = .secondaryLabel
        hintLabel.font = .preferredFont(forTextStyle: .body)

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, playButton, hintLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(24, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        // Messages can hand over the tapped bubble (willBecomeActive) before
        // this view loads, so pick it up from the conversation here too.
        show(activeConversation?.selectedMessage)
    }

    // Tapping a bubble while the extension isn't running.
    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        show(conversation.selectedMessage)
    }

    override func didBecomeActive(with conversation: MSConversation) {
        super.didBecomeActive(with: conversation)
        if songURL != nil { openApp() }
    }

    // Tapping a bubble while the extension is already open.
    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        show(message)
        openApp()
    }

    /// Song card for a tapped bubble; the sending hint otherwise (opened
    /// from the Messages app drawer).
    private func show(_ message: MSMessage?) {
        songURL = message?.url.flatMap(appURL(from:))
        guard isViewLoaded else { return }  // viewDidLoad calls back in
        let layout = message?.layout as? MSMessageTemplateLayout
        let hasSong = songURL != nil
        titleLabel.text = layout?.caption
        subtitleLabel.text = [layout?.subcaption, layout?.trailingSubcaption].compactMap { $0 }.joined(separator: "  ·  ")
        titleLabel.isHidden = !hasSong
        subtitleLabel.isHidden = !hasSong || (subtitleLabel.text ?? "").isEmpty
        playButton.isHidden = !hasSong
        hintLabel.isHidden = hasSong
    }

    // The app this extension belongs to (this file is shared verbatim by
    // Family Player and Friends Player).
    private let appScheme = (Bundle.main.bundleIdentifier ?? "").contains("Friends-Player") ? "friendsplayer" : "familyplayer"

    /// Bubbles carry only the link's query ("?t=…&p=…") because Messages
    /// drops custom-scheme URLs from messages; rebuild the app link here.
    private func appURL(from messageURL: URL) -> URL? {
        if messageURL.scheme == appScheme { return messageURL }
        guard let query = URLComponents(url: messageURL, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
              !query.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = appScheme
        components.host = "play"
        components.percentEncodedQuery = query
        return components.url
    }

    private func openApp() {
        guard let url = songURL else { return }
        extensionContext?.open(url) { [weak self] opened in
            guard opened else { return }  // leave the Play button up
            DispatchQueue.main.async { self?.dismiss() }
        }
    }
}
