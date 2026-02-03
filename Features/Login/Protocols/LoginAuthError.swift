//
//  LoginAuthError.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

/// 로그인 레이어에서 공통으로 쓰는 에러
enum LoginAuthError: Error {
    case missingIDToken
    case missingEmail
}
