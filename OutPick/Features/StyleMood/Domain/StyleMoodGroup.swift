import Foundation

enum StyleMoodGroup: String, CaseIterable, Hashable {
    case essential
    case street
    case casual
    case heritage
    case romantic
    case experimental
    case other

    init(rawValueOrOther value: String) {
        self = Self(rawValue: value) ?? .other
    }
}
