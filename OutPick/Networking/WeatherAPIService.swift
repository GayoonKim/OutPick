//
//  WeatherAPIService.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import Foundation

// 현재 날씨 요청을 위한 구조체
struct CurrentWeatherRequest: WeatherAPIRequest {
    // Response는 CurrentWeatherData 타입으로 정의
    typealias Response = CurrentWeatherData
    
    // 위도
    var lat: Double
    // 경도
    var lon: Double
    
    // API 경로
    var path: String { "/data/2.5/weather" }
    
    // 쿼리 아이템
    var queryItems: [URLQueryItem]? {[
        "lat": "\(lat)", // 위도
        "lon": "\(lon)", // 경도
        "appid": "\(Bundle.shared.apiKey!)", // API 키
        "units": "metric", // 단위
        "lang": "kr" // 언어
    ].map{ URLQueryItem(name: $0.key, value: $0.value) }}
}

struct WeatherForecastRequest: WeatherAPIRequest {
    typealias Response = WeatherForecastData
    
    var lat: Double
    var lon: Double
    
    var path: String { "/data/3.0/onecall" }
    var queryItems: [URLQueryItem]? {[
        "lat": "\(lat)",
        "lon": "\(lon)",
        "appid": "\(Bundle.shared.apiKey!)",
        "units": "metric",
        "lang": "kr",
        "exclude": "current, minutely, alerts"
    ].map{ URLQueryItem(name: $0.key, value: $0.value) }}
}
