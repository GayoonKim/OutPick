//
//  HomeCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import UIKit
import CoreLocation

@MainActor
class HomeCollectionViewController: UICollectionViewController {
    
    let locationManager = CLLocationManager() // 위치 매니저 인스턴스
    var currentWeatherRequestTask: Task<Void, Never>? = nil // 현재 날씨 요청 작업
    deinit { currentWeatherRequestTask?.cancel() } // 뷰 컨트롤러 해제 시 작업 취소
    
    typealias DataSourceType = UICollectionViewDiffableDataSource<ViewModel.Section, ViewModel.Item>
    
    enum ViewModel {
        enum Section: Hashable {
            case currentWeatherSection // 현재 날씨 섹션
        }
        
        enum Item: Hashable {
            case currentWeatherItem(_ dt: Double, _ main: CurrentMain, _ weather: [CurrentWeather])
            
            func hash(into hasher: inout Hasher) {
                switch self {
                case .currentWeatherItem(let dt, _, _):
                    hasher.combine(dt)
                }
            }
            
            static func == (lhs: HomeCollectionViewController.ViewModel.Item, rhs: HomeCollectionViewController.ViewModel.Item) -> Bool {
                switch (lhs, rhs) {
                case (.currentWeatherItem(let ldt, _, _), .currentWeatherItem(let rdt, _, _)):
                    return ldt == rdt
                }
            }
        }
    }
    
    struct Model {
        var currentWeatherModel: CurrentWeatherData? // 현재 날씨 데이터 모델
        var cityName: String?
    }
    
    var dataSource: DataSourceType!
    var model = Model()

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
    }
    
    //MARK: OpenWeather API로 데이터 불러오기
    func update(_ coor: CLLocationCoordinate2D) {
        
        // 현재 날씨 불러오기
        currentWeatherRequestTask?.cancel()
        currentWeatherRequestTask = Task {
            if let currentWeatherInfo = try? await CurrentWeatherRequest(lat: coor.latitude, lon: coor.longitude).sendWeatherRequest() {
                self.model.currentWeatherModel = currentWeatherInfo
                self.updateCollectionView()
            } else {
                updateCollectionView()
                self.model.currentWeatherModel = nil
            }
        }
    }
    
    //MARK: Snapshot을 통해 view model 설정, snapshot 생성하고 diffable data source에 등록
    func updateCollectionView() {
        var sectionIDs = [ViewModel.Section]()
        var itemBySection = [ViewModel.Section:[ViewModel.Item]]()
        
        guard let currentWeatherInfo = self.model.currentWeatherModel else { return }
        
        sectionIDs.append(.currentWeatherSection)
        itemBySection[.currentWeatherSection] = [ViewModel.Item.currentWeatherItem(currentWeatherInfo.dt, currentWeatherInfo.main, currentWeatherInfo.weather)]
        
        dataSource.applySnapshotUsing(sectionIDs: sectionIDs, itemsBySection: itemBySection)
    }
    
    //MARK: 컬렉션 뷰 diffable data source 생성 및 셀 설정
    func createDataSource() -> DataSourceType {
        dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) -> UICollectionViewCell? in
            switch item {
            case .currentWeatherItem(_, let main, let weather):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CurrentWeather", for: indexPath) as! CurrentWeatherCollectionViewCell
                
                cell.cityLabel.text = self.model.cityName
                cell.tempLabel.text = "\(Int(main.temp))°"
                cell.descriptionLabel.text = weather.last?.description
                cell.tempMinMaxLabel.text = "최고: \(Int(main.tempMax))° 최저: \(Int(main.tempMin))°"
                
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

        update(coor)
        getCityName()
    }
    
    // 위치 데이터 불러오기 실패 시 호출
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        print("Error: \(error)")
    }
}
