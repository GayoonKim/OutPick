//
//  NWPathNetworkStatusProvider.swift
//  OutPick
//
//  Created by Codex on 2/25/26.
//

import Foundation
import Network
import Combine

final class NWPathNetworkStatusProvider: NetworkStatusProviding {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "outpick.network.status")
    private let subject = CurrentValueSubject<NetworkStatus, Never>(.offline)
    private let lock = NSLock()

    private var started = false
    private var _currentStatus: NetworkStatus = .offline

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
    }

    var currentStatus: NetworkStatus {
        lock.lock()
        defer { lock.unlock() }
        return _currentStatus
    }

    var statusPublisher: AnyPublisher<NetworkStatus, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    func startMonitoring() {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            let status = NetworkStatus(
                isOnline: path.status == .satisfied,
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained,
                accessClass: Self.accessClass(for: path),
                updatedAt: Date()
            )

            self.lock.lock()
            self._currentStatus = status
            self.lock.unlock()

            self.subject.send(status)
        }

        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        lock.lock()
        let shouldCancel = started
        started = false
        lock.unlock()
        guard shouldCancel else { return }
        monitor.cancel()
    }

    private static func accessClass(for path: NWPath) -> NetworkAccessClass {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.status == .satisfied { return .other }
        return .unknown
    }
}
