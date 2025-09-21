//
//  DailyForecastCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 7/18/24.
//

import UIKit

class DailyForecastCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "dailyWeatherCell"
    
    @IBOutlet weak var dayLabel: UILabel!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var tempMinMaxLabel: UILabel!
}
