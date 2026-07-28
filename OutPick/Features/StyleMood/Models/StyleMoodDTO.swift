import Foundation

struct StyleMoodDTO: Equatable {
    let id: String
    let displayName: String
    let displayGroup: String
    let sortOrder: Int
    let isFeaturedInOnboarding: Bool

    init?(id: String, data: [String: Any]) {
        guard id.isEmpty == false,
              let displayName = data["displayName"] as? String,
              displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        self.id = id
        self.displayName = displayName
        self.displayGroup = data["displayGroup"] as? String ?? "other"
        if let sortOrder = data["sortOrder"] as? Int {
            self.sortOrder = sortOrder
        } else if let sortOrder = data["sortOrder"] as? NSNumber {
            self.sortOrder = sortOrder.intValue
        } else {
            self.sortOrder = .max
        }
        self.isFeaturedInOnboarding = data["isFeaturedInOnboarding"] as? Bool ?? false
    }

    func toDomain() -> StyleMood {
        StyleMood(
            id: id,
            displayName: displayName,
            displayGroup: StyleMoodGroup(rawValueOrOther: displayGroup),
            sortOrder: sortOrder,
            isFeaturedInOnboarding: isFeaturedInOnboarding
        )
    }
}
