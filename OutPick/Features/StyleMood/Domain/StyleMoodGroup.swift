import Foundation

enum StyleMoodGroup: String, CaseIterable, Hashable {
    case essential = "베이직·포멀"
    case street = "스트릿·트렌드"
    case heritage = "헤리티지·유틸리티"
    case sports = "스포츠·아웃도어"
    case vintage = "빈티지·서브컬처"
    case romantic = "로맨틱·익스프레시브"
    case other

    init(rawValueOrOther value: String) {
        self = Self(rawValue: value) ?? .other
    }

    var displayName: String {
        rawValue
    }
}
