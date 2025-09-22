//
//  NetworkMonitor.swift
//  OutPick
//
//  Created by 김가윤 on 9/22/25.
//

import Network
import CoreTelephony

enum NetworkType {
    case wifi
    case cellular5G
    case cellularLTE
    case cellular3G
    case other
    case unknown
}

final class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue.global(qos: .background)
    
    private(set) var isConnected: Bool = false
    private(set) var networkType: NetworkType = .unknown
    
    private init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            self.isConnected = path.status == .satisfied
            
            if path.usesInterfaceType(.wifi) {
                self.networkType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                self.networkType = self.checkCellularType()
            } else {
                self.networkType = .other
            }
        }
        monitor.start(queue: queue)
    }
    
    private func checkCellularType() -> NetworkType {
        let networkInfo = CTTelephonyNetworkInfo()
        
        let currentRadioTech: String?
        if #available(iOS 12.0, *) {
            currentRadioTech = networkInfo.serviceCurrentRadioAccessTechnology?.values.first
        } else {
            currentRadioTech = networkInfo.currentRadioAccessTechnology
        }
        
        guard let tech = currentRadioTech else { return .unknown }
        
        switch tech {
        case CTRadioAccessTechnologyEdge,
             CTRadioAccessTechnologyGPRS,
             CTRadioAccessTechnologyCDMA1x:
            return .cellular3G
            
        case CTRadioAccessTechnologyWCDMA,
             CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0,
             CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB,
             CTRadioAccessTechnologyeHRPD:
            return .cellular3G // HSPA 등도 3G 계열
        
        case CTRadioAccessTechnologyLTE:
            return .cellularLTE
            
        case CTRadioAccessTechnologyNRNSA,
             CTRadioAccessTechnologyNR:
            return .cellular5G
            
        default:
            return .unknown
        }
    }
    
    var isHighSpeed: Bool {
        switch networkType {
        case .wifi, .cellular5G, .cellularLTE: return true
        case .cellular3G, .other, .unknown: return false
        }
    }
}
