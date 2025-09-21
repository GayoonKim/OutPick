//
//  HomeCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import UIKit
import CoreLocation
import Combine

class HomeCollectionViewController: UICollectionViewController {
    
    let locationManager = CLLocationManager() // 위치 매니저 인스턴스
    
    var currentWeatherRequestTask: Task<Void, Never>? = nil                     // 현재 날씨 요청 작업
    var weatherForecastRequestTask: Task<Void, Never>? = nil                    // 날씨 예보 요청 작업
    var hourlyForecastImageRequestTask: [IndexPath: Task<Void, Never>] = [:]
    var dailyForecastImageRequestTask: [IndexPath: Task<Void, Never>] = [:]
    
    deinit {
        currentWeatherRequestTask?.cancel()
        weatherForecastRequestTask?.cancel()
    } // 뷰 컨트롤러 해제 시 작업 취소
    
    typealias DataSourceType = UICollectionViewDiffableDataSource<ViewModel.Section, ViewModel.Item>
    
    enum ViewModel {
        enum Section: Hashable {
            case currentWeatherSection // 현재 날씨 섹션
            case hourlyForecastSection // 시간별 예보 섹션
            case dailyForecastSection  // 일별 예보 섹션
        }
        
        enum Item: Hashable {
            case currentWeatherItem(_ dt: Double, _ main: CurrentMain, _ weather: [CurrentWeather])
            case hourlyForecastItem(_ dt: Double, _ temp: Double, _ weather: [WeatherForecast])
            case dailyForecastItem(_ dt: Double, _ temp: Temperature, _ weather: [WeatherForecast])
            
            func hash(into hasher: inout Hasher) {
                switch self {
                case .currentWeatherItem(let dt, _, _):
                    hasher.combine(dt)
                case .hourlyForecastItem(let dt, _, _):
                    hasher.combine(dt)
                case .dailyForecastItem(let dt, _, _):
                    hasher.combine(dt)
                }
            }
            
            static func == (lhs: HomeCollectionViewController.ViewModel.Item, rhs: HomeCollectionViewController.ViewModel.Item) -> Bool {
                switch (lhs, rhs) {
                case (.currentWeatherItem(let ldt, _, _), .currentWeatherItem(let rdt, _, _)):
                    return ldt == rdt
                case (.hourlyForecastItem(let ldt, _, _), .hourlyForecastItem(let rdt, _, _)):
                    return ldt == rdt
                case (.dailyForecastItem(let ldt, _, _), .dailyForecastItem(let rdt, _, _)):
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
        var dailyForecastModel = [DailyForecast]()
    }
    
    var dataSource: DataSourceType!
    var model = Model()
    
    private var cancellables = Set<AnyCancellable>()
//    private var tabViewControllers: [Int: UIViewController] = [:]
//    private var currentChildViewController: UIViewController?
//    private var currentTabIndex: Int?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 셀 등록
        self.collectionView.register(CurrentWeatherCollectionViewCell.self, forCellWithReuseIdentifier: CurrentWeatherCollectionViewCell.reuseIdentifier)
        self.collectionView.register(HourlyForecastCollectionViewCell.self, forCellWithReuseIdentifier: HourlyForecastCollectionViewCell.reuseIdentifier)
        self.collectionView.register(DailyForecastCollectionViewCell.self, forCellWithReuseIdentifier: DailyForecastCollectionViewCell.reuseIdentifier)
        
        
        // dataSource // layout 준비
        self.dataSource = self.createDataSource()
        self.collectionView.dataSource = self.dataSource
        self.collectionView.collectionViewLayout = self.createLayout()
        
        WeatherAPIManager.shared.delegate = self

        self.model.currentWeatherModel = WeatherAPIManager.shared.currentWeather
        self.model.hourlyForecastModel = WeatherAPIManager.shared.hourlyForecast
        self.model.dailyForecastModel = WeatherAPIManager.shared.dailyForecast
        
        Task {@MainActor in
            self.updateCollectionView()
        }
        
    }
    
//    override func viewController(_ index: Int) -> UIViewController {
//        let storyboard = UIStoryboard(name: "Main", bundle: nil)
//        switch index {
//        case 0:
//            // Weather tab
//            let vc = storyboard.instantiateViewController(withIdentifier: "weatherVC")
//            let nav = UINavigationController(rootViewController: vc)
//            nav.isNavigationBarHidden = true
//            return nav
//        case 1:
//            // Chat list tab
//            let listVC = RoomListsCollectionViewController(collectionViewLayout: UICollectionViewFlowLayout())
//            let nav = UINavigationController(rootViewController: listVC)
//            nav.isNavigationBarHidden = true
//            return nav
//
//        case 4:
//            // Settings tab
//            let vc = storyboard.instantiateViewController(withIdentifier: "settingsVC")
//            let nav = UINavigationController(rootViewController: vc)
//            nav.isNavigationBarHidden = true
//            return nav
//
//        default:
//            return UINavigationController(rootViewController: UIViewController())
//        }
//    }

    override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        self.hourlyForecastImageRequestTask[indexPath]?.cancel()
        self.dailyForecastImageRequestTask[indexPath]?.cancel()
    }
    
    //MARK: Snapshot을 통해 view model 설정, snapshot 생성하고 diffable data source에 등록
    func updateCollectionView() {
        guard dataSource != nil else { return }
        
        var sectionIDs = [ViewModel.Section]()
        var itemBySection = [ViewModel.Section:[ViewModel.Item]]()
        
        guard let currentWeatherInfo =  self.model.currentWeatherModel else {return}
        
        sectionIDs.append(.currentWeatherSection)
        itemBySection[.currentWeatherSection] = [ViewModel.Item.currentWeatherItem(currentWeatherInfo.dt, currentWeatherInfo.main, currentWeatherInfo.weather)]
        
        let hourlyForecasts = self.model.hourlyForecastModel.sorted().reduce(into: [ViewModel.Item]()) { partial, hourlyForecast in
            partial.append(ViewModel.Item.hourlyForecastItem(hourlyForecast.dt, hourlyForecast.temp, hourlyForecast.weather))
        }
        itemBySection[.hourlyForecastSection] = hourlyForecasts
        sectionIDs.append(.hourlyForecastSection)
        
        let dailyForecasts = self.model.dailyForecastModel.sorted().reduce(into: [ViewModel.Item]()) { partial, dailyForecast in
            partial.append(ViewModel.Item.dailyForecastItem(dailyForecast.dt, dailyForecast.temp, dailyForecast.weather))
        }
        itemBySection[.dailyForecastSection] = dailyForecasts
        sectionIDs.append(.dailyForecastSection)
        
        dataSource.applySnapshotUsing(sectionIDs: sectionIDs, itemsBySection: itemBySection)
    }
    
    //MARK: 컬렉션 뷰 diffable data source 생성 및 셀 설정
    func createDataSource() -> DataSourceType {
        dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) -> UICollectionViewCell? in
            switch item {
            case .currentWeatherItem(_, let main, let weather):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CurrentWeatherCollectionViewCell.reuseIdentifier, for: indexPath) as! CurrentWeatherCollectionViewCell
                
                cell.cityLabel.text = WeatherAPIManager.shared.currentCity
                cell.tempLabel.text = "\(String(format: "%.0f", main.temp))°"
                cell.descriptionLabel.text = weather.last?.description
                cell.tempMinMaxLabel.text = "최고: \(String(format: "%.0f", main.tempMax))° 최저: \(String(format: "%.0f", main.tempMin))°"

                return cell
                
            case .hourlyForecastItem(let dt, let temp, let weather):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: HourlyForecastCollectionViewCell.reuseIdentifier, for: indexPath) as! HourlyForecastCollectionViewCell
                
                cell.timeLabel.text = self.convertUnixTimestamp(dt)
                
                if let iconString = weather.last?.icon,
                   let image = WeatherAPIManager.shared.getCachedIcon(for: iconString) {
                    cell.iconImageView.image = image
                } else {
                    self.hourlyForecastImageRequestTask[indexPath]?.cancel()
                    self.hourlyForecastImageRequestTask[indexPath] = Task {
                        
                        if let image = try? await WeatherAPIManager.shared.loadIcon(weather) {
                            cell.iconImageView.image = image
                        }
                        
                        self.hourlyForecastImageRequestTask[indexPath] = nil
                    }
                }
                
                cell.tempLabel.text = "\(String(format: "%.0f", temp))°"
                
                
                return cell
                
            case .dailyForecastItem(let dt, let temp, let weather):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DailyForecastCollectionViewCell.reuseIdentifier, for: indexPath) as! DailyForecastCollectionViewCell
                
                cell.dayLabel.text = self.getDay(dt)
                
                if let iconString = weather.last?.icon,
                   let image = WeatherAPIManager.shared.getCachedIcon(for: iconString) {
                    cell.imageView.image = image
                } else {
                    self.dailyForecastImageRequestTask[indexPath]?.cancel()
                    self.dailyForecastImageRequestTask[indexPath] = Task {
                        if let image = try? await WeatherAPIManager.shared.loadIcon(weather) {
                            cell.imageView.image = image
                        }
                        
                        self.dailyForecastImageRequestTask[indexPath] = nil
                    }
                }
                
                cell.tempMinMaxLabel.text = "\(String(format: "%.0f", temp.min))° ~ \(String(format: "%.0f", temp.max))°"

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
//                let currentWeatherGroup = NSCollectionLayoutGroup.vertical(layoutSize: currentWeatherGroupSize, repeatingSubitem: currentWeatherItem, count: 1)
                let currentWeatherGroup = NSCollectionLayoutGroup.horizontal(layoutSize: currentWeatherGroupSize, subitems: [currentWeatherItem])
                
                let currentWeatherSection = NSCollectionLayoutSection(group: currentWeatherGroup)
                currentWeatherSection.interGroupSpacing = 20
                currentWeatherItem.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

                return currentWeatherSection
                
            case .hourlyForecastSection:
                // 스크롤 가능한 내부 그룹
                let hourlyForecastItemSize = NSCollectionLayoutSize(widthDimension: .absolute(80), heightDimension: .fractionalHeight(1))
                let hourlyForecastItem = NSCollectionLayoutItem(layoutSize: hourlyForecastItemSize)
                    
                let scrollableGroupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
                let scrollableGroup = NSCollectionLayoutGroup.horizontal(layoutSize: scrollableGroupSize, subitems: [hourlyForecastItem])
                
                // 외부 그룹 (배경 뷰 크기와 동일)
                let outerGroupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(0.15))
                let outerGroup = NSCollectionLayoutGroup.vertical(layoutSize: outerGroupSize, subitems: [scrollableGroup])
                
                let hourlyForecastSection = NSCollectionLayoutSection(group: outerGroup)
                hourlyForecastSection.orthogonalScrollingBehavior = .continuous
                hourlyForecastSection.interGroupSpacing = 5
                
                let sectionBackgroundDecoration = NSCollectionLayoutDecorationItem.background(elementKind: "background")
                sectionBackgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
                hourlyForecastSection.decorationItems = [sectionBackgroundDecoration]

                return hourlyForecastSection

            case .dailyForecastSection:
                let dailyForecastItemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(0.2))
                let dailyForecastItem = NSCollectionLayoutItem(layoutSize: dailyForecastItemSize)
                
                let dailyForecastGroupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(0.33))
                let dailyForecastGroup = NSCollectionLayoutGroup.vertical(layoutSize: dailyForecastGroupSize, subitems: [dailyForecastItem])
                
                let dailyForecastSection = NSCollectionLayoutSection(group: dailyForecastGroup)
                dailyForecastSection.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 0, trailing: 10)
                
                let sectionBackgroundDecoration = NSCollectionLayoutDecorationItem.background(elementKind: "background")
                sectionBackgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 0, trailing: 10)
                dailyForecastSection.decorationItems = [sectionBackgroundDecoration]
                

                return dailyForecastSection
            }
        }
        
        layout.register(BackgroundDecorationView.self, forDecorationViewOfKind: "background")
        return layout
    }
    
    private func convertUnixTimestamp(_ time: TimeInterval) -> String {
        let unixTime: TimeInterval = time
        
        let date = Date(timeIntervalSince1970: unixTime)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "a h시"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "ko_KR")
        
        let formattedDate = dateFormatter.string(from: date)
        
        if compareDate(date) {
            return "지금"
        } else {
            return formattedDate
        }
    }
    
    private func compareDate(_ date: Date) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "ko_KR")
        
        let formattedDate = dateFormatter.string(from: date)
        
        if formattedDate == dateFormatter.string(from: Date()) {
            return true
        } else {
            return false
        }
    }
    
    private func compareDateWithoutTime(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = Date()
        
        // 오늘 날짜와 비교 (시간은 제외)
        let currentComponents = calendar.dateComponents([.year, .month, .day], from: today)
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        
        return currentComponents.year == dateComponents.year &&
               currentComponents.month == dateComponents.month &&
               currentComponents.day == dateComponents.day
    }
    
    private func getDay(_ time: TimeInterval) -> String {
        let unixTime: TimeInterval = time
        
        let date = Date(timeIntervalSince1970: unixTime)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "ko_KR")
        
        if compareDateWithoutTime(date) {
            return "오늘"
        } else {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.dateFormat = "E"
            weekdayFormatter.locale = Locale(identifier: "ko_KR")
            return weekdayFormatter.string(from: date)
        }
    }

}

extension HomeCollectionViewController: WeatherAPIManagerDelegate {
    func weatherDidUpdate() {
        self.updateCollectionView()
    }
}
