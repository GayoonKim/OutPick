//
//  WeatherAPIService.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import Foundation

// 현재 날씨 요청을 위한 클래스
class CurrentWeatherRequest: WeatherAPIRequest {
    // Response는 CurrentWeatherData 타입으로 정의
    typealias Response = CurrentWeatherData
    
    static let shared = CurrentWeatherRequest()
    
    // 위도, 경도
    private var lat: Double = 0.0
    private var lon: Double = 0.0
    
    // 위도 getter, setter
    var currentLat: Double {
        get {
            return lat
        }
        set {
            self.lat = newValue
        }
    }
    
    // 경도 getter, setter
    var currentLon: Double {
        get {
            return lon
        }
        set {
            self.lon = newValue
        }
    }
    
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

// 날씨 예보를 위한 클래스
class WeatherForecastRequest: WeatherAPIRequest {
    typealias Response = WeatherForecastData
    
    static let shared = WeatherForecastRequest()
    
    // 위도, 경도
    private var lat: Double = 0.0
    private var lon: Double = 0.0
    
    // 위도 getter, setter
    var currentLat: Double {
        get {
            return self.lat
        }
        set {
            self.lat = newValue
        }
    }
    
    // 경도 getter, setter
    var currentLon: Double {
        get {
            return self.lon
        }
        set {
            return self.lon = newValue
        }
    }
    
    
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
