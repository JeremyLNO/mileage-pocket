import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var clientID: UUID?
    var createdAt: Date = Date()
    var lastUsedAt: Date?

    init(id: UUID = UUID(), name: String = "", clientID: UUID? = nil) {
        self.id = id
        self.name = name
        self.clientID = clientID
        self.createdAt = Date()
    }
}
