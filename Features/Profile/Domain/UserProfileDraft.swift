//
//  UserProfileDraft.swift
//  OutPick
//

import Foundation

/// 1단계에서 만든 임시 입력값(2단계로 넘길 draft)
struct UserProfileDraft: Equatable {
    var gender: String?
    var birthdate: String?
}
