import Foundation

struct StyleMoodDTO: Equatable {
    let id: String
    let displayName: String
    let displayGroup: String
    let aliases: [String]
    let sortOrder: Int
    let isFeaturedInOnboarding: Bool
    let status: String

    init?(id: String, data: [String: Any]) {
        guard id.isEmpty == false,
              let displayName = data["displayName"] as? String,
              displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        self.id = id
        self.displayName = displayName
        self.displayGroup = data["displayGroup"] as? String ?? "other"
        self.aliases = data["aliases"] as? [String] ?? []
        if let sortOrder = data["sortOrder"] as? Int {
            self.sortOrder = sortOrder
        } else if let sortOrder = data["sortOrder"] as? NSNumber {
            self.sortOrder = sortOrder.intValue
        } else {
            self.sortOrder = .max
        }
        self.isFeaturedInOnboarding = data["isFeaturedInOnboarding"] as? Bool ?? false
        self.status = data["status"] as? String ?? "inactive"
    }

    func toDomain() -> StyleMood {
        StyleMood(
            id: id,
            displayName: displayName,
            displayGroup: StyleMoodGroup(rawValueOrOther: displayGroup),
            aliases: aliases,
            sortOrder: sortOrder,
            isFeaturedInOnboarding: isFeaturedInOnboarding,
            status: StyleMoodStatus(rawValue: status) ?? .inactive
        )
    }
}
