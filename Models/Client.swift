import Foundation
import SwiftData

/// Deliberately minimal — a name and a colour tag. This is not a CRM.
@Model
final class Client {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var lastUsedAt: Date?

    init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
        self.createdAt = Date()
    }
}
