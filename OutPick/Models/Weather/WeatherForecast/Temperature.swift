//
//  Temperature.swift
//  OutPick
//
//  Created by 김가윤 on 7/17/24.
//

import Foundation
//  온도 정보를 나타내는 구조체입니다. 최저 및 최고 온도를 포함합니다.
struct Temperature: Codable {
    let min: Double
    let max: Double
}
