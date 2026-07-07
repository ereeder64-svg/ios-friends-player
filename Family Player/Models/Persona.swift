//
//  Persona.swift
//  Family Player
//

import Foundation
import SwiftData

@Model
final class Persona {
    // No @Attribute(.unique): CloudKit forbids it. fetchOrCreatePersona(...)
    // in LibraryScanner already fetches by name before inserting, so
    // app-level dedup already exists independent of this constraint.
    var name: String = ""
    var artworkCachePath: String?

    // CloudKit requires ALL relationships be optional, including to-many
    // (array) relationships -- a default empty array is not sufficient.
    @Relationship(deleteRule: .cascade, inverse: \Album.persona)
    var albums: [Album]? = []

    init(name: String) {
        self.name = name
        self.artworkCachePath = nil
    }
}
