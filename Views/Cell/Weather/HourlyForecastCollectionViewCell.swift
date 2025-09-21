//
//  HourlyForecastCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 7/17/24.
//

import UIKit

class HourlyForecastCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "hourlyWeatherCell"
    
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var tempLabel: UILabel!
}
