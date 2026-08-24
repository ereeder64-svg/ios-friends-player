//
//  NetworkMonitor.swift
//  Family Player
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnWiFi: Bool = false

    // A monitor scoped to just the Wi-Fi interface reports `.satisfied`
    // only when Wi-Fi itself is usable, regardless of whether cellular is
    // also up -- simpler and more direct than inspecting
    // `path.usesInterfaceType(.wifi)` on a general-purpose monitor.
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let onWiFi = path.status == .satisfied
            Task { @MainActor in
                self?.isOnWiFi = onWiFi
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.luxrecta.Family-Player.NetworkMonitor"))
    }
}
