//
//  HourlyForecast.swift
//  OutPick
//
//  Created by 김가윤 on 7/17/24.
//
import Foundation
//  시간별 날씨 예보 정보를 나타내는 구조체입니다. 시간, 온도, 날씨 정보를 포함합니다.
struct HourlyForecast: Codable, Comparable {
    let dt: Double
    let temp: Double
    let weather: [WeatherForecast]
    
    static func == (lhs: HourlyForecast, rhs: HourlyForecast) -> Bool {
        return lhs.dt == rhs.dt
    }
    
    static func < (lhs: HourlyForecast, rhs: HourlyForecast) -> Bool {
        return lhs.dt < rhs.dt
    }
}
