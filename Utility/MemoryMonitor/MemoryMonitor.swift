//
//  MemoryMonitor.swift
//  OutPick
//
//  Created by 김가윤 on 9/22/25.
//

import Foundation

final class MemoryMonitor {
    static func currentMemoryUsageMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_,
                          task_flavor_t(TASK_VM_INFO),
                          $0,
                          &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576.0 // MB 단위 변환
    }
    
    static func isMemoryPressureHigh() -> Bool {
        return currentMemoryUsageMB() > 800 // 800MB 이상 사용 시 압박으로 간주
    }
}
