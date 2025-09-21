//
//  CurrentWeatherData.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import Foundation

// 현재 날씨 데이터를 담는 구조체
struct CurrentWeatherData: Codable {
    let dt: Double // 데이터 타임스탬프
    let main: CurrentMain // 주요 날씨 정보
    let weather: [CurrentWeather] // 날씨 설명 배열
}

extension CurrentWeatherData: Hashable {
    static func == (lhs: CurrentWeatherData, rhs: CurrentWeatherData) -> Bool {
        return lhs.dt == rhs.dt
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(dt)
    }
}