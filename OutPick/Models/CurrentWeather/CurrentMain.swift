//
//  CurrentMain.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import Foundation

// 현재 날씨의 주요 정보를 담는 구조체
struct CurrentMain: Codable {
    let temp: Double // 현재 온도
    let tempMin: Double // 최저 온도
    let tempMax: Double // 최고 온도
    
    enum CodingKeys: String, CodingKey {
        case temp
        case tempMin = "temp_min"
        case tempMax = "temp_max"
    }
}