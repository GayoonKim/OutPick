//
//  DateManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/14/25.
//

import UIKit

class DateManager {
    
    static let shared = DateManager()
    private(set) var currentMonth: String
    
    private init() {
        self.currentMonth = DateManager.getCurrentMonth()
    }
    
    private static func getCurrentMonth() -> String {
        
        let currentDate = Date()
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: currentDate)
        
        return "\(currentMonth)월"
        
    }
    
    func getMonthFromTimestamp(date: Date) -> String {
        
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        return "\(month)월"
        
    }
    
}
