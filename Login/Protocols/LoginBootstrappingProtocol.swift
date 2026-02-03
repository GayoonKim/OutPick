//
//  LoginBootstrappingProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

protocol LoginBootstrappingProtocol: AnyObject {
    /// 로그인 성공 + 프로필 존재(= Main 진입 확정) 이후에 필요한 “초기화만” 수행
    func bootstrapAfterLogin(userEmail: String) async throws
}
