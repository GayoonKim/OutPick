//
//  HomeCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import UIKit
import CoreLocation

@MainActor
class SeparatorView: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .lightGray
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class HomeCollectionViewController: UICollectionViewController {
    
    static let shared = HomeCollectionViewController()
    
    let locationManager = CLLocationManager() // 위치 매니저 인스턴스
    
    var currentWeatherRequestTask: Task<Void, Never>? = nil // 현재 날씨 요청 작업
    var weatherForecastRequestTask: Task<Void, Never>? = nil
    var hourlyForecastImageRequestTask: [IndexPath: Task<Void, Never>] = [:]
    deinit {
        currentWeatherRequestTask?.cancel()
        weatherForecastRequestTask?.cancel()
    } // 뷰 컨트롤러 해제 시 작업 취소
    
    typealias DataSourceType = UICollectionViewDiffableDataSource<ViewModel.Section, ViewModel.Item>
    
    enum ViewModel {
        enum Section: Hashable {
            case currentWeatherSection // 현재 날씨 섹션
            case hourlyForecastSection
        }
        
        enum Item: Hashable {
            case currentWeatherItem(_ dt: Double, _ main: CurrentMain, _ weather: [CurrentWeather])
            case hourlyForecastItem(_ dt: Double, _ temp: Double, _ weather: [WeatherForecast])
            
            func hash(into hasher: inout Hasher) {
                switch self {
                case .currentWeatherItem(let dt, _, _):
                    hasher.combine(dt)
                case .hourlyForecastItem(let dt, _, _):
                    hasher.combine(dt)
                }
            }
            
            static func == (lhs: HomeCollectionViewController.ViewModel.Item, rhs: HomeCollectionViewController.ViewModel.Item) -> Bool {
                switch (lhs, rhs) {
                case (.currentWeatherItem(let ldt, _, _), .currentWeatherItem(let rdt, _, _)):
                    return ldt == rdt
                case (.hourlyForecastItem(let ldt, _, _), .hourlyForecastItem(let rdt, _, _)):
                    return ldt == rdt
                default:
                    return false
                }
            }
        }
    }
    
    struct Model {
        var currentWeatherModel: CurrentWeatherData? // 현재 날씨 데이터 모델
        var cityName: String?
        var hourlyForecastModel = [HourlyForecast]()
    }
    
    var dataSource: DataSourceType!
    var model = Model()
    
    enum ImageRequestError: Error {
        case imageNotFound
        case couldNotInitializeFromData
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 위치 서비스 설정
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100.0
        locationManager.startUpdatingLocation()
        
        dataSource = createDataSource()
        collectionView.dataSource = dataSource
        collectionView.collectionViewLayout = createLayout()
        
        guard let lat = locationManager.location?.coordinate.latitude,
              let lon = locationManager.location?.coordinate.longitude else {return}
        
        currentWeatherRequestTask?.cancel()
        currentWeatherRequestTask = Task {
            if let currentWeatherInfo = try? await CurrentWeatherRequest(lat: lat, lon: lon).sendWeatherRequest() {
                model.currentWeatherModel = currentWeatherInfo
                updateCollectionView()
            } else {
                model.currentWeatherModel = nil
            }
            updateCollectionView()
            currentWeatherRequestTask = nil
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        self.hourlyForecastImageRequestTask[indexPath]?.cancel()
    }
    
    //MARK: OpenWeather API로 데이터 불러오기
    func update(_ lat: Double, _ lon: Double) {
        
        weatherForecastRequestTask?.cancel()
        weatherForecastRequestTask = Task {
            if let weatherForecastInfo = try? await WeatherForecastRequest(lat: lat, lon: lon).sendWeatherRequest() {
                self.model.hourlyForecastModel = weatherForecastInfo.hourly
                self.updateCollectionView()
            } else {
                self.model.hourlyForecastModel = []
            }
            self.updateCollectionView()
            weatherForecastRequestTask = nil
        }
    }
    
    //MARK: Snapshot을 통해 view model 설정, snapshot 생성하고 diffable data source에 등록
    func updateCollectionView() {
        var sectionIDs = [ViewModel.Section]()
        var itemBySection = [ViewModel.Section:[ViewModel.Item]]()
        
        guard let currentWeatherInfo = self.model.currentWeatherModel else {return}
        
        sectionIDs.append(.currentWeatherSection)
        itemBySection[.currentWeatherSection] = [ViewModel.Item.currentWeatherItem(currentWeatherInfo.dt, currentWeatherInfo.main, currentWeatherInfo.weather)]
        
        let hourlyForecasts = self.model.hourlyForecastModel.sorted().reduce(into: [ViewModel.Item]()) { partial, hourlyForecast in
            partial.append(ViewModel.Item.hourlyForecastItem(hourlyForecast.dt, hourlyForecast.temp, hourlyForecast.weather))
        }
        itemBySection[.hourlyForecastSection] = hourlyForecasts
        sectionIDs.append(.hourlyForecastSection)
        
        dataSource.applySnapshotUsing(sectionIDs: sectionIDs, itemsBySection: itemBySection)
    }
    
    //MARK: 컬렉션 뷰 diffable data source 생성 및 셀 설정
    func createDataSource() -> DataSourceType {
        dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) -> UICollectionViewCell? in
            switch item {
            case .currentWeatherItem(_, let main, let weather):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CurrentWeather", for: indexPath) as! CurrentWeatherCollectionViewCell
                
                cell.cityLabel.text = self.model.cityName
                cell.tempLabel.text = "\(String(format: "%.0f", main.temp))°"
                cell.descriptionLabel.text = weather.last?.description
                cell.tempMinMaxLabel.text = "최고: \(String(format: "%.0f", main.tempMax))° 최저: \(String(format: "%.0f", main.tempMin))°"
                
                return cell
                
            case .hourlyForecastItem(let dt, let temp, let weather):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "HourlyForecast", for: indexPath) as! HourlyForecastCollectionViewCell
                
                cell.timeLabel.text = self.convertUnixTimestamp(dt)
                
                self.hourlyForecastImageRequestTask[indexPath]?.cancel()
                self.hourlyForecastImageRequestTask[indexPath] = Task {
                    if let image = try? await self.loadIcon(weather) {
                        cell.iconImageView.image = image
                    }
                    
                    self.hourlyForecastImageRequestTask[indexPath] = nil
                }
                
                cell.tempLabel.text = "\(String(format: "%.0f", temp))°"
                
                return cell
            }
        }
        
        return dataSource
    }
    
    //MARK: 컬렉션 뷰 compositional 레이아웃 구성
    func createLayout() -> UICollectionViewCompositionalLayout {
        let layout = UICollectionViewCompositionalLayout { (sectionIndex, environment) -> NSCollectionLayoutSection? in
            switch self.dataSource.snapshot().sectionIdentifiers[sectionIndex] {
            case .currentWeatherSection:
                let currentWeatherItemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(200))
                let currentWeatherItem = NSCollectionLayoutItem(layoutSize: currentWeatherItemSize)
                
                let currentWeatherGroupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(200))
                let currentWeatherGroup = NSCollectionLayoutGroup.vertical(layoutSize: currentWeatherGroupSize, repeatingSubitem: currentWeatherItem, count: 1)
                
                let currentWeatherSection = NSCollectionLayoutSection(group: currentWeatherGroup)
                
                currentWeatherSection.interGroupSpacing = 20
                currentWeatherItem.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                
                return currentWeatherSection
                
            case .hourlyForecastSection:
                let hourlyForecastItemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.2), heightDimension: .fractionalHeight(1))
                let hourlyForecastItem = NSCollectionLayoutItem(layoutSize: hourlyForecastItemSize)
                    
                let hourlyForecastGroupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(0.15))
                let hourlyForecastGroup = NSCollectionLayoutGroup.horizontal(layoutSize: hourlyForecastGroupSize, repeatingSubitem: hourlyForecastItem, count: 5)
                
                let hourlyForecastSection = NSCollectionLayoutSection(group: hourlyForecastGroup)
                hourlyForecastSection.orthogonalScrollingBehavior = .continuous
                    
                return hourlyForecastSection

            }
        }
        
        return layout
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
                self.model.cityName = administrativeArea
            }
        }
    }
    
    func convertUnixTimestamp(_ time: TimeInterval) -> String {
        let unixTime: TimeInterval = time
        
        let date = Date(timeIntervalSince1970: unixTime)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "a h시"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "ko_KR")
        
        let formattedDate = dateFormatter.string(from: date)
        
        if formattedDate == dateFormatter.string(from: Date()) {
            return "지금"
        } else {
            return formattedDate
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
        
        return image
    }
    
    
}

//MARK: 위치 서비스 이용 관련 extension
extension HomeCollectionViewController: CLLocationManagerDelegate {
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
        guard let coor = locations.last?.coordinate else {return}

        update(coor.latitude, coor.longitude)
        getCityName()
    }
    
    // 위치 데이터 불러오기 실패 시 호출
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        print("Error: \(error)")
    }
}
