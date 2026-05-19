//
//  APIKEY.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import Foundation

// API 키를 번들에서 가져오는 확장
extension Bundle {
    static let shared = Bundle()
    
    // API 키를 번들에서 가져옵니다.
    var apiKey: String? {
        return Bundle.main.infoDictionary?["API_KEY"] as? String
    }
}