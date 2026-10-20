//
//  SongShareLink.swift
//  Friends Player
//

import Foundation

// "Send this song to someone" links. A link is the TARGET app's own URL
// scheme plus enough descriptive text (title / album / artist) for the
// receiving app to find the matching song in ITS OWN library. Song.stableID
// can't be used for this: it's shareName|relativePath, and the share names
// differ between Family Player and Friends Player (and between people), so
// the same song has different identifiers on different phones. Matching is
// by content instead.
//
// Each app registers its own scheme (familyplayer / friendsplayer), so the
// sender picks which app the recipient runs and the link opens that one.
enum SongShareLink {

    enum Target: CaseIterable, Identifiable {
        case familyPlayer
        case friendsPlayer

        var id: Self { self }

        var scheme: String {
            switch self {
            case .familyPlayer: return "familyplayer"
            case .friendsPlayer: return "friendsplayer"
            }
        }

        var appName: String {
            switch self {
            case .familyPlayer: return "Family Player"
            case .friendsPlayer: return "Friends Player"
            }
        }

        /// Image-set name of this app's icon, shown in the share preview.
        /// Both apps carry both images (the sender's app has no access to
        /// the other app's asset catalog).
        var iconAssetName: String {
            switch self {
            case .familyPlayer: return "ShareIcon-FamilyPlayer"
            case .friendsPlayer: return "ShareIcon-FriendsPlayer"
            }
        }
    }

    struct Payload: Equatable {
        let title: String
        let album: String
        let persona: String
        let sender: String
    }

    private static let host = "play"

    // URLComponents leaves "&", "=" and "+" unescaped inside query values
    // (they're legal in a query), so a title like "Rock & Roll" would split
    // into two parameters. Escape everything except unreserved characters.
    private static let valueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    // Spaces are written as "+" (a literal "+" is escaped as %2B) -- much
    // shorter and more readable in a text message than "%20".
    private static func encode(_ value: String) -> String {
        (value.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? "")
            .replacingOccurrences(of: "%20", with: "+")
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }

    // MARK: - Sending

    static func url(for song: Song, sender: String, target: Target) -> URL? {
        var items = [URLQueryItem(name: "t", value: encode(song.displayTitle))]
        if let persona = song.album?.persona?.name, !persona.isEmpty {
            items.append(URLQueryItem(name: "p", value: encode(persona)))
        }
        if !sender.isEmpty {
            items.append(URLQueryItem(name: "from", value: encode(sender)))
        }

        var components = URLComponents()
        components.scheme = target.scheme
        components.host = host
        components.percentEncodedQueryItems = items
        return components.url
    }

    /// The line of text that accompanies the link ("Eric sent you ...").
    static func intro(for song: Song, sender: String) -> String {
        let personaName = song.album?.persona?.name ?? ""
        let byline = personaName.isEmpty ? "" : " by \(personaName)"
        return sender.isEmpty
            ? "Check out \"\(song.displayTitle)\"\(byline)."
            : "\(sender) sent you \"\(song.displayTitle)\"\(byline)."
    }

    /// What goes in the Messages compose box: the intro line, then the link.
    static func message(for song: Song, sender: String, target: Target) -> String {
        let intro = intro(for: song, sender: sender)
        guard let url = url(for: song, sender: sender, target: target) else { return intro }
        return "\(intro) Tap to play it in \(target.appName):\n\(url.absoluteString)"
    }

    // MARK: - Receiving

    static func payload(from url: URL) -> Payload? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems else { return nil }
        func value(_ name: String) -> String {
            items.first(where: { $0.name == name })?.value.map(decode) ?? ""
        }
        let title = value("t")
        guard !title.isEmpty else { return nil }
        return Payload(title: title, album: value("a"), persona: value("p"), sender: value("from"))
    }

    private static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Best match for the payload among `songs`: title must match; album
    /// and artist only break ties (the same song can legitimately live on
    /// a different album, or under a slightly different artist folder, in
    /// the other app's library).
    static func findSong(matching payload: Payload, in songs: [Song]) -> Song? {
        let wantTitle = normalized(payload.title)
        guard !wantTitle.isEmpty else { return nil }
        let wantAlbum = normalized(payload.album)
        let wantPersona = normalized(payload.persona)

        var best: (song: Song, score: Int)?
        for song in songs {
            guard normalized(song.displayTitle) == wantTitle || normalized(song.title) == wantTitle else { continue }
            var score = 0
            if !wantAlbum.isEmpty, normalized(song.album?.title ?? "") == wantAlbum { score += 2 }
            if !wantPersona.isEmpty, normalized(song.album?.persona?.name ?? "") == wantPersona { score += 1 }
            if best == nil || score > best!.score {
                best = (song, score)
            }
        }
        return best?.song
    }
}
