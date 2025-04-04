//
//  WeatherAPIRequest.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import Foundation

// 날씨 API 요청 프로토콜
protocol WeatherAPIRequest {
    associatedtype Response
    
    var path: String {get}
    var queryItems: [URLQueryItem]? {get}
    var request: URLRequest {get}
}

extension WeatherAPIRequest {
    var host: String {"api.openweathermap.org"}
    var queryItems: [URLQueryItem]? {nil}
}

extension WeatherAPIRequest {
    var request: URLRequest {
        var urlComponents = URLComponents()
        
        urlComponents.scheme = "https"
        urlComponents.host = host
        urlComponents.path = path
        urlComponents.queryItems = queryItems
        
        let request = URLRequest(url: urlComponents.url!)
        
        return request
    }
}

extension WeatherAPIRequest where Response: Decodable {
    func sendWeatherRequest() async throws -> Response {
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw WeatherAPIRequestError.itemNotFound
            }
            
            let jsonDecoder = JSONDecoder()
            let decodedData = try jsonDecoder.decode(Response.self, from: data)
            
            return decodedData
        } catch {
            
            throw WeatherAPIRequestError.itemNotFound
            
        }
        
    }
}

enum WeatherAPIRequestError: Error {
    case itemNotFound
}
