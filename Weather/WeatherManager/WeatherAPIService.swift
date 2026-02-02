//
//  WeatherAPIService.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import Foundation

public enum WeatherAPIError: Error, Equatable {
    case networkOffline
    case networkTimeout
    case networkConnectionLost
    case badStatus(code: Int)
    case decoding
    case invalidResponse
    case unknown

    public var isOffline: Bool {
        switch self {
        case .networkOffline, .networkConnectionLost: return true
        default: return false
        }
    }
}

public enum WeatherAPIErrorClassifier {
    public static func classify(_ error: Error) -> WeatherAPIError {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet: return .networkOffline
            case .timedOut: return .networkTimeout
            case .networkConnectionLost: return .networkConnectionLost
            default: return .unknown
            }
        }
        return .unknown
    }
}


// 현재 날씨 요청을 위한 클래스
class CurrentWeatherRequest: WeatherAPIRequest {
    // Response는 CurrentWeatherData 타입으로 정의
    typealias Response = CurrentWeatherData
    
    static let shared = CurrentWeatherRequest()
    
    // 위도, 경도
    private var lat: Double = 0.0
    private var lon: Double = 0.0
    
    // Prefer parameterized requests over shared mutable state
    init() {}
    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
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
    
    static func send(lat: Double, lon: Double) async throws -> CurrentWeatherData {
        let req = CurrentWeatherRequest(lat: lat, lon: lon)
        return try await req.sendWeatherRequest()
    }
}

// 날씨 예보를 위한 클래스
class WeatherForecastRequest: WeatherAPIRequest {
    typealias Response = WeatherForecastData
    
    static let shared = WeatherForecastRequest()
    
    // 위도, 경도
    private var lat: Double = 0.0
    private var lon: Double = 0.0
    
    // Prefer parameterized requests over shared mutable state
    init() {}
    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    static func send(lat: Double, lon: Double) async throws -> WeatherForecastData {
        let req = WeatherForecastRequest(lat: lat, lon: lon)
        return try await req.sendWeatherRequest()
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
