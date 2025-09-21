//
//  WeatherAPIManager.swift
//  OutPick
//
//  Created by 김가윤 on 11/6/24.
//

import UIKit
import CoreLocation
import Network
import Combine
//import OSLog

enum ImageRequestError: Error {
    case imageNotFound
    case couldNotInitializeFromData
}

//protocol WeatherAPIManagerDelegate: AnyObject {
//    func weatherDidUpdate()
//    func weatherDidFail(isOffline: Bool, message: String)
//    func networkStatusDidChange(isOnline: Bool)
//}

actor ConcurrencyLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func release() {
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
        } else {
            running -= 1
        }
    }
}

class WeatherAPIManager: NSObject {
    
    static let shared = WeatherAPIManager()
    
//    weak var delegate: WeatherAPIManagerDelegate?
    private let locationManager = CLLocationManager()
    
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "WeatherAPI.pathMonitor")
    private var isOnline = true
    
    private var weatherUpdateTask: Task<Void, Never>? = nil
//    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "OutPick", category: "WeatherAPI")
    
    // MARK: - Combine publishers (preferred)
    private let weatherUpdateSubject = PassthroughSubject<Void, Never>()
    private let weatherFailSubject = PassthroughSubject<(isOffline: Bool, message: String), Never>()
    private let networkStatusSubject = CurrentValueSubject<Bool, Never>(true)

    public var weatherUpdated: AnyPublisher<Void, Never> { weatherUpdateSubject.eraseToAnyPublisher() }
    public var weatherFailed: AnyPublisher<(isOffline: Bool, message: String), Never> { weatherFailSubject.eraseToAnyPublisher() }
    public var networkStatus: AnyPublisher<Bool, Never> { networkStatusSubject.eraseToAnyPublisher() }
    
    deinit {
        weatherUpdateTask?.cancel()
        pathMonitor.cancel()
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
        
        // 네트워크 상태 모니터링 시작
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let online = (path.status == .satisfied)
            
            if online != self.isOnline {
                self.isOnline = online
                DispatchQueue.main.async {
                    self.networkStatusSubject.send(online)
                }
            }
        }
        
        pathMonitor.start(queue: pathQueue)
    }
    
    func startLocationUpdates() {
        locationManager.startUpdatingLocation()
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }
    
    //MARK: OpenWeather API로 데이터 불러오기
    func updateWeatherInfo(_ lat: Double, _ lon: Double) async throws {
        print(#function, "3. updateWeatherInfo 호출 시작")

        // 두 요청을 병렬 실행 (async let)
        do {
            async let current = CurrentWeatherRequest.send(lat: lat, lon: lon)
            async let forecast = WeatherForecastRequest.send(lat: lat, lon: lon)
            
            let (currentInfo, forecastInfo) = try await (current, forecast)
            try Task.checkCancellation()
            print(#function, "success", currentInfo, forecastInfo)
            
            // 상태 반영은 메인 액터에서만 수행
            await MainActor.run {
                self.currentWeatherData = currentInfo
                self.hourlyForecastData = forecastInfo.hourly
                self.dailyForecastData  = forecastInfo.daily
            }

            // 예보 아이콘 중복 제거 후 병렬 캐싱
            let hourlyIcons = forecastInfo.hourly.compactMap { $0.weather.last?.icon }
            let dailyIcons  = forecastInfo.daily.compactMap  { $0.weather.last?.icon }
            let uniqueIcons = Array(Set(hourlyIcons + dailyIcons))

            let limiter = ConcurrencyLimiter(limit: 5)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for icon in uniqueIcons {
                    if self.getCachedIcon(for: icon) != nil { continue }
                    group.addTask {
                        await limiter.acquire()
                        do {
                            try Task.checkCancellation()
                            try await self.cacheWeatherIcon(icon)
                            await limiter.release()
                        } catch {
                            await limiter.release()
                            throw error
                        }
                    }
                }
                try await group.waitForAll()
            }
            
            print(#function, "5. updateWeatherInfo 호출 완료")
        } catch is CancellationError {
            // 취소는 정상 흐름: 조용히 종료(최근 성공 데이터 유지)
            print(#function, "Weather update failed: Cancelled")
            return
        } catch {
            // 실패 시 최근 성공 데이터는 유지하고, 배너/토스트로 네트워크 확인 유도
            let classified = WeatherAPIErrorClassifier.classify(error)
            let offlineLikely = classified.isOffline || (self.isOnline == false)
            
            await MainActor.run {
//                self.logger.error("Weather update failed: \(String(describing: error))")
                self.weatherFailSubject.send((offlineLikely, offlineLikely ? "네트워크 연결을 확인하세요." : "일시적인 오류가 발생했어요. 잠시 후 다시 시도해 주세요."))
            }
            return
        }

        
        // 작업 핸들 정리(기존 task 핸들을 사용하지 않는 구조로 전환)
        await MainActor.run {
            self.weatherUpdateTask = nil
        }

        let province = await self.resolveProvinceName(lat: lat, lon: lon)
        // 완료 콜백은 메인에서 즉시 호출
        await MainActor.run {
            self.cityName = province
            self.weatherUpdateSubject.send()
        }
    }
    
    func getCachedIcon(for iconString: String) -> UIImage? {
        return ImageCacheManager.shared.object(forKey: iconString as NSString)
    }
    
    func cacheIcon(_ image: UIImage, for iconString: String) {
        ImageCacheManager.shared.setObject(image, forKey: iconString as NSString)
    }

    private func cacheWeatherIcon(_ iconString: String) async throws{
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

    private func resolveProvinceName(lat: Double, lon: Double) async -> String? {
        let geocoder = CLGeocoder()
        
        let location = CLLocation(latitude: lat, longitude: lon)
        return await withCheckedContinuation { cont in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                guard error == nil, let p = placemarks?.first else {
                    cont.resume(returning: nil)
                    return
                }
                // 광역 행정 구역(administrativeArea) 우선, 없을 때 최소한의 폴백
                let name = p.administrativeArea ?? p.locality ?? p.country
                cont.resume(returning: name)
    }
    
        }
    }
    
    private func getCityName() {
        guard let loc = locationManager.location else { return }
        
        Task { [weak self] in
            guard let self = self else { return }
            
            let name = await self.resolveProvinceName(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
            await MainActor.run {
                self.cityName = name
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

        weatherUpdateTask?.cancel()
        weatherUpdateTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                try await self.updateWeatherInfo(location.coordinate.latitude, location.coordinate.longitude)
            } catch is CancellationError {
                // 취소는 정상 흐름
                print(#function, "Weather update failed: Cancelled")
            } catch {
//                self.logger.error("Weather update failed: \(String(describing: error))")
                print("Weather update failed: \(String(describing: error))")
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
