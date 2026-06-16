//
//  Persona.swift
//  Family Player
//

import Foundation
import SwiftData

@Model
final class Persona {
    @Attribute(.unique) var name: String

    @Relationship(deleteRule: .cascade, inverse: \Album.persona)
    var albums: [Album] = []

    init(name: String) {
        self.name = name
    }
}
