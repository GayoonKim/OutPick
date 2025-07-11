//
//  WeatherForecastData.swift
//  OutPick
//
//  Created by 김가윤 on 7/17/24.
//

import Foundation
//  전체 날씨 예보 데이터를 나타내는 구조체입니다. 시간별 및 일별 예보 정보를 포함합니다.
struct WeatherForecastData: Codable {
    let hourly: [HourlyForecast]
    let daily: [DailyForecast]
}
