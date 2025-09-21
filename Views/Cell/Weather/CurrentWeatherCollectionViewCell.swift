//
//  CurrentWeatherCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import UIKit

// 현재 날씨 정보를 표시하는 컬렉션 뷰 셀
class CurrentWeatherCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "currentWeatherCell"
    
    @IBOutlet weak var cityLabel: UILabel! // 도시 이름 레이블
    @IBOutlet weak var tempLabel: UILabel! // 현재 온도 레이블
    @IBOutlet weak var descriptionLabel: UILabel! // 날씨 설명 레이블
    @IBOutlet weak var tempMinMaxLabel: UILabel! // 최저/최고 온도 레이블
}
