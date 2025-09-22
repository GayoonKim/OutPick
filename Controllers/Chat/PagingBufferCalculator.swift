//
//  PagingBufferCalculator.swift
//  OutPick
//
//  Created by 김가윤 on 9/22/25.
//

import UIKit

struct PagingBufferCalculator {
    static func calculate(
        for room: ChatRoom?,
        scrollVelocity: CGFloat
    ) -> Int {
        // 1. 네트워크 기반 기본값
        var buffer: Int
        switch NetworkMonitor.shared.networkType {
        case .wifi: buffer = 300
        case .cellular5G: buffer = 250
        case .cellularLTE: buffer = 200
        case .cellular3G: buffer = 100
        default: buffer = 50
        }
        
        // 2. 스크롤 속도 반영
        if scrollVelocity > 1500 {
            buffer += 100
        } else if scrollVelocity < 300 {
            buffer -= 50
        }
        
        // 3. 메모리 상태 반영
        if MemoryMonitor.isMemoryPressureHigh() {
            buffer = min(buffer, 100)
        }
        
        // 4. 대규모 방 참여자 수 제한
        if let room = room, room.participants.count > 100 {
            buffer = min(buffer, 80)
        }
        
        // 5. 하한 보정
        return max(50, buffer)
    }
}
