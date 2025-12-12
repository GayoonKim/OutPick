//
//  CurrentWeather.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import Foundation

// 현재 날씨 정보를 담는 구조체
struct CurrentWeather: Codable {
    let description: String // 날씨 설명
    let icon: String // 날씨 아이콘
}