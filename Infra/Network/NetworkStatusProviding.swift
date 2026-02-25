//
//  NetworkStatusProviding.swift
//  OutPick
//
//  Created by Codex on 2/25/26.
//

import Foundation
import Combine

enum NetworkAccessClass: String, Sendable, Equatable {
    case wifi
    case wired
    case cellular
    case other
    case unknown
}

struct NetworkStatus: Sendable, Equatable {
    let isOnline: Bool
    let isExpensive: Bool
    let isConstrained: Bool
    let accessClass: NetworkAccessClass
    let updatedAt: Date

    static let offline = NetworkStatus(
        isOnline: false,
        isExpensive: false,
        isConstrained: false,
        accessClass: .unknown,
        updatedAt: Date()
    )
}

protocol NetworkStatusProviding: AnyObject {
    var currentStatus: NetworkStatus { get }
    var statusPublisher: AnyPublisher<NetworkStatus, Never> { get }

    func startMonitoring()
    func stopMonitoring()
}
