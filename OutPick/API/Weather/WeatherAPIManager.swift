//
//  WeatherAPIManager.swift
//  OutPick
//
//  Created by 김가윤 on 11/6/24.
//

import UIKit
import CoreLocation

enum ImageRequestError: Error {
    case imageNotFound
    case couldNotInitializeFromData
}

protocol WeatherAPIManagerDelegate: AnyObject {
    func weatherDidUpdate()
}

class WeatherAPIManager: NSObject {
    
    static let shared = WeatherAPIManager()
    
    weak var delegate: WeatherAPIManagerDelegate?
    private let locationManager = CLLocationManager()
    
    private var currentWeatherRequestTask: Task<Void, Never>? = nil                     // 현재 날씨 요청 작업
    private var weatherForecastRequestTask: Task<Void, Never>? = nil                    // 날씨 예보 요청 작업
    deinit {
        currentWeatherRequestTask?.cancel()
        weatherForecastRequestTask?.cancel()
    } // 뷰 컨트롤러 해제 시 작업 취소
    
    private var currentWeatherData: CurrentWeatherData? // 현재 날씨 데이터
    private var hourlyForecastData = [HourlyForecast]() // 시간별 날씨 데이터
    private var dailyForecastData = [DailyForecast]()   // 일별 날씨 데이터
    private var cityName: String?                       // 현재 위치 도시 이름
    
    // 날씨 및 도시 이름 데이터 접근자
    var currentWeather: CurrentWeatherData? {
        return currentWeatherData
    }
    var hourlyForecast: [HourlyForecast] {
        return hourlyForecastData
    }
    var dailyForecast: [DailyForecast] {
        return dailyForecastData
    }
    var currentCity: String? {
        return cityName
    }
    
    private override init() {
        super.init()
        self.setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100.0
    }
    
    func startLocationUpdates() {
        locationManager.startUpdatingLocation()
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }
    
    func getCachedIcon(for iconString: String) -> UIImage? {
        return ImageCacheManager.shared.object(forKey: iconString as NSString)
    }
    
    func cacheIcon(_ image: UIImage, for iconString: String) {
        ImageCacheManager.shared.setObject(image, forKey: iconString as NSString)
    }
    
    //MARK: OpenWeather API로 데이터 불러오기
    func updateWeatherInfo(_ lat: Double, _ lon: Double, completion: @escaping () -> Void) async throws {
        
        print("D")
        // 기존 작업 취소
        currentWeatherRequestTask?.cancel()
        weatherForecastRequestTask?.cancel()
        
        CurrentWeatherRequest.shared.currentLat = lat
        CurrentWeatherRequest.shared.currentLon = lon
        WeatherForecastRequest.shared.currentLat = lat
        WeatherForecastRequest.shared.currentLon = lon
        
        // 현재 날씨 요청
        currentWeatherRequestTask = Task { [weak self] in
            guard let self = self else { return }
            
            if let currentWeatherInfo = try? await CurrentWeatherRequest.shared.sendWeatherRequest() {
                self.currentWeatherData = currentWeatherInfo
            } else {
                self.currentWeatherData = nil
            }
            currentWeatherRequestTask = nil
        }
        
        weatherForecastRequestTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                
                let weatherForecastInfo = try await WeatherForecastRequest.shared.sendWeatherRequest()
                self.hourlyForecastData = weatherForecastInfo.hourly
                self.dailyForecastData = weatherForecastInfo.daily
                
                for forecast in hourlyForecastData {
                    if let iconString = forecast.weather.last?.icon {
                        do {
                            
                            try await cacheWeatherIcon(iconString)
                            
                        } catch {
                            
                            print("시간별 예보 이미지 \(iconString) 캐싱 실패: \(error.localizedDescription)")
                            try await cacheWeatherIcon(iconString)
                            
                        }
                    }
                }
                
                for forecast in dailyForecastData {
                    if let iconString = forecast.weather.last?.icon {
                        do {
                            
                            try await cacheWeatherIcon(iconString)
                            
                        } catch {
                            
                            print("일별 예보 이미지 \(iconString) 캐싱 실패: \(error.localizedDescription)")
                            try await cacheWeatherIcon(iconString)
                            
                        }
                    }
                }
                
            } catch {
                
                print("날씨 예보 정보 불러오기 실패: \(error)")
                self.hourlyForecastData = []
                self.dailyForecastData = []
                
            }
            
            weatherForecastRequestTask = nil
            
        }
        
        // 현재 위치 도시 이름 불러오기
        getCityName()
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
            completion()
        }
    }

    private func cacheWeatherIcon(_ iconString: String) async throws{
        // 이미 캐시된 아이콘이면 취소
        if getCachedIcon(for: iconString) != nil { return }
        
        do {
            
            let url = URL(string: "https://openweathermap.org/img/wn/\(iconString)@2x.png")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else {
                
                throw ImageRequestError.imageNotFound
            }
            
            cacheIcon(image, for: iconString)
            
        } catch {
            
            print("날씨 아이콘 캐시 실패: \(error)")
            throw error
            
        }
        
    }
    
    func getCityName() {
        let geocoder = CLGeocoder()
        guard let location = locationManager.location else {return}
        
        geocoder.reverseGeocodeLocation(location) { (placemarks, error) in
            if let error = error {
                print("Reverse geocode failed with error: \(error.localizedDescription)")
                return
            }
            
            guard let placemark = placemarks?.first else {return}

            if let administrativeArea = placemark.administrativeArea {
                self.cityName = administrativeArea
            }
        }
    }
    
    func loadIcon(_ weather: [WeatherForecast]) async throws -> UIImage {
        guard let iconString = weather.last?.icon else {return UIImage()}
        
        let urlComponents = URLComponents(string: "https://openweathermap.org/img/wn/\(iconString)@2x.png")!
        
        let (data, response) = try await URLSession.shared.data(from: urlComponents.url!)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ImageRequestError.imageNotFound
        }
        
        guard let image = UIImage(data: data) else {
            throw ImageRequestError.couldNotInitializeFromData
        }
        
        self.cacheIcon(image, for: iconString)
        return image
    }
}

//MARK: 위치 서비스 이용 관련 extension
extension WeatherAPIManager: CLLocationManagerDelegate {
    // 위치 서비스 권한 확인 및 요청
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            print("위치 서비스 사용 가능")
        case .restricted, .denied:
            print("위치 서비스 사용 불가")
        case .notDetermined:
            print("권한 설정 필요")
            locationManager.requestWhenInUseAuthorization()
        default:
            break
        }
    }
    
    // 위치 데이터 불러오기 성공 시 호출
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {return}
        
        print("A")
        
        DispatchQueue.main.async {
            print("B")
            Task {
                    try await self.updateWeatherInfo(location.coordinate.latitude, location.coordinate.longitude) {
                    self.delegate?.weatherDidUpdate()
                }
            }
        }
        
        // 위치 업데이트 중단 (배터리 절약)
        manager.stopUpdatingLocation()
    }
    
    // 위치 데이터 불러오기 실패 시 호출
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        print("Error: \(error)")
    }
}
