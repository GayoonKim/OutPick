//
//  FirstProfileViewModel.swift
//  OutPick
//

import Foundation

/// 프로필 설정 1단계(성별/생년월일) ViewModel
@MainActor
final class FirstProfileViewModel {

    struct State: Equatable {
        var selectedGender: String? = nil
        var birthdate: Date? = nil
        var isNextEnabled: Bool = false
        var maxBirthdate: Date
    }

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    private let onNext: (UserProfileDraft) -> Void

    init(onNext: @escaping (UserProfileDraft) -> Void) {
        self.onNext = onNext

        // 만 15세 제한(기존 로직 유지): (현재연도-15)년 1월 1일
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let max = cal.date(from: DateComponents(year: year - 15, month: 1, day: 1)) ?? now

        self.state = State(maxBirthdate: max)
        recompute()
    }

    func selectGender(_ gender: String) {
        state.selectedGender = gender
        recompute()
    }

    func setBirthdate(_ date: Date) {
        state.birthdate = date
        recompute()
    }

    func tapNext() {
        guard state.isNextEnabled else { return }

        let draft = UserProfileDraft(
            gender: state.selectedGender,
            birthdate: state.birthdate.map { Self.formatDate($0) }
        )
        onNext(draft)
    }

    // MARK: - Private

    private func recompute() {
        state.isNextEnabled = (state.selectedGender != nil && state.birthdate != nil)
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
