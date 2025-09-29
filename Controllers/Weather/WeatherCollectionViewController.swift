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
    
    //    typealias DataSourceType = UICollectionViewDiffableDataSource<ViewModelSection, ViewModel.Item>
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>
    
    //    enum ViewModel {
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
        
        static func == (lhs: Item, rhs: Item) -> Bool {
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
//    }
    
    struct Model {
        var currentWeatherModel: CurrentWeatherData? // 현재 날씨 데이터 모델
        var cityName: String?
        var hourlyForecastModel = [HourlyForecast]()
        var dailyForecastModel = [DailyForecast]()
    }
    
    var dataSource: DataSourceType!
    var model = Model()
    
    private var cancellables = Set<AnyCancellable>()
    // Network/UI state mirrors (read-only from publishers)
    private var isOffline: Bool = false
    private var isRefreshing: Bool = false
    private var lastRefreshDate: Date?
    private var offlineBannerShown = false
    private let staleThreshold: TimeInterval = 10 * 60 // 10분

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
        
        bindPublisher()
    }
    
    private func bindPublisher() {
        WeatherAPIManager.shared.weatherUpdated
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                // 최신 데이터로 UI 갱신
                guard let self = self else { return }
                
                self.model.currentWeatherModel = WeatherAPIManager.shared.currentWeather
                self.model.hourlyForecastModel = WeatherAPIManager.shared.hourlyForecast
                self.model.dailyForecastModel = WeatherAPIManager.shared.dailyForecast
                self.model.cityName = WeatherAPIManager.shared.currentCity
                self.lastRefreshDate = Date()
                self.isRefreshing = false
                updateCollectionView()
            }
            .store(in: &cancellables)
//
        WeatherAPIManager.shared.weatherFailed
            .receive(on: RunLoop.main)
            .sink { [weak self] isOffline, message in
                guard let self = self else { return }
                self.isRefreshing = false
                self.presentWeatherErrorBanner(isOffline: isOffline) // “네트워크 연결을 확인하세요.” 등
            }
            .store(in: &cancellables)

//        WeatherAPIManager.shared.networkStatus
//            .removeDuplicates()
//            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
//            .receive(on: RunLoop.main)
//            .sink { [weak self] isOnline in
//                guard let self = self,
//                      let container = self.navigationController?.view ?? self.view else { return }
//
//                if !isOnline {
//                    // 전환 시 1회만 순간 안내 배너
//                    if !self.offlineBannerShown {
//                        BannerView.presentWeatherError(on: container, isOffline: true)
//                        self.offlineBannerShown = true
//                    }
//                } else {
//                    // 온라인 복구 순간 안내 + 자동 새로고침(신선도 조건부)
//                    self.offlineBannerShown = false
//                    BannerView.show(on: container, message: "네트워크가 복구되었어요.", style: .success, autoHideAfter: 1.6)
//                    if self.isDataStale() && !self.isRefreshing {
//                        self.isRefreshing = true
//                        WeatherAPIManager.shared.startLocationUpdates()
//                    }
//                }
//            }
//            .store(in: &cancellables)
    }
    
    
    private func isDataStale() -> Bool {
        guard let t = lastRefreshDate else { return true }
        return Date().timeIntervalSince(t) > staleThreshold
    }
    
    /// 오프라인/일시 오류 배너 표시(안전한 컨테이너 선택 + 메인 스레드 보장)
    func presentWeatherErrorBanner(isOffline: Bool) {
        guard let container = self.navigationController?.view ?? self.view else { return }

        // 혹시 메인 스레드가 아닐 수도 있으니 방어적으로 보장
        if Thread.isMainThread {
            BannerView.presentWeatherError(on: container, isOffline: isOffline)
        } else {
            DispatchQueue.main.async {
                BannerView.presentWeatherError(on: container, isOffline: isOffline)
            }
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        self.hourlyForecastImageRequestTask[indexPath]?.cancel()
        self.dailyForecastImageRequestTask[indexPath]?.cancel()
    }
    
    //MARK: Snapshot을 통해 view model 설정, snapshot 생성하고 diffable data source에 등록
    func updateCollectionView() {
        guard dataSource != nil else { return }
        
        var sectionIDs = [Section]()
        var itemBySection = [Section:[Item]]()
        
        guard let currentWeatherInfo =  self.model.currentWeatherModel else {return}
        sectionIDs.append(.currentWeatherSection)
        itemBySection[.currentWeatherSection] = [Item.currentWeatherItem(currentWeatherInfo.dt, currentWeatherInfo.main, currentWeatherInfo.weather)]
        
        let hourlyForecasts = self.model.hourlyForecastModel.sorted().reduce(into: [Item]()) { partial, hourlyForecast in
            partial.append(Item.hourlyForecastItem(hourlyForecast.dt, hourlyForecast.temp, hourlyForecast.weather))
        }
        itemBySection[.hourlyForecastSection] = hourlyForecasts
        sectionIDs.append(.hourlyForecastSection)
        
        let dailyForecasts = self.model.dailyForecastModel.sorted().reduce(into: [Item]()) { partial, dailyForecast in
            partial.append(Item.dailyForecastItem(dailyForecast.dt, dailyForecast.temp, dailyForecast.weather))
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
                
                let cityName = self.model.cityName ?? ""
                let tempValue = "\(String(format: "%.0f", main.temp))°"
                let descriptionValue = weather.last?.description ?? ""
                let tempMinMaxValue = "최고: \(String(format: "%.0f", main.tempMax))° 최저: \(String(format: "%.0f", main.tempMin))°"
                
                let vm = CurrentWeatherCollectionViewCell.ViewModel(
                    city: cityName, tempText: tempValue, descriptionText: descriptionValue, minMaxText: tempMinMaxValue
                )
                cell.configure(with: vm)
                
                return cell

            case .hourlyForecastItem(let dt, let temp, let weather):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: HourlyForecastCollectionViewCell.reuseIdentifier, for: indexPath) as! HourlyForecastCollectionViewCell

                let time = self.convertUnixTimestamp(dt)
                let tempText = "\(String(format: "%.0f", temp))°"
                let icon = WeatherAPIManager.shared.getCachedIcon(for: weather.last?.icon ?? "")
                
                let vm = HourlyForecastCollectionViewCell.ViewModel(timeText: time, tempText: tempText, icon: icon)
                cell.configure(with: vm)
                
                return cell
                
            case .dailyForecastItem(let dt, let temp, let weather):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DailyForecastCollectionViewCell.reuseIdentifier, for: indexPath) as! DailyForecastCollectionViewCell

                let dayText = self.getDay(dt)
                let minMAx = "\(String(format: "%.0f", temp.min))° ~ \(String(format: "%.0f", temp.max))°"
                let icon = WeatherAPIManager.shared.getCachedIcon(for: weather.last?.icon ?? "")!
                
                let vm = DailyForecastCollectionViewCell.ViewModel(dayText: dayText, minMaxText: minMAx, icon: icon)
                cell.configure(with: vm)
                
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
                let currentWeatherGroup = NSCollectionLayoutGroup.horizontal(layoutSize: currentWeatherGroupSize, subitems: [currentWeatherItem])
                
                let currentWeatherSection = NSCollectionLayoutSection(group: currentWeatherGroup)
                currentWeatherSection.interGroupSpacing = 20
                currentWeatherItem.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

                return currentWeatherSection
                
            case .hourlyForecastSection:
                // 컨테이너 셀 1개를 전폭으로 배치하고, 내부 가로 컬렉션뷰가 스크롤/스냅을 처리
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .absolute(64),
                    heightDimension: .fractionalHeight(1)
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(64), heightDimension: .absolute(100))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
                section.interGroupSpacing = 8
                section.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)

                let sectionBackgroundDecoration = NSCollectionLayoutDecorationItem.background(elementKind: "background")
                sectionBackgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: -10, bottom: 10, trailing: -10)
                section.decorationItems = [sectionBackgroundDecoration]

                return section

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
