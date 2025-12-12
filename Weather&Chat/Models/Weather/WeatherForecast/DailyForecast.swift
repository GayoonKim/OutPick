//
//  DailyForecast.swift
//  OutPick
//
//  Created by 김가윤 on 7/17/24.
//
import Foundation
//  일별 날씨 예보 정보를 나타내는 구조체입니다. 날짜, 온도, 날씨 정보를 포함합니다.
struct DailyForecast: Codable, Comparable {
    let dt: Double
    let temp: Temperature
    let weather: [WeatherForecast]
    
    static func < (lhs: DailyForecast, rhs: DailyForecast) -> Bool {
        return lhs.dt < rhs.dt
    }
    
    static func == (lhs: DailyForecast, rhs: DailyForecast) -> Bool {
        return lhs.dt == rhs.dt
    }
}
