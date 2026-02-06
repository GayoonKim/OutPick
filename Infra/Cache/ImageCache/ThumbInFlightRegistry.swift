//
//  ThumbInFlightRegistry.swift
//  OutPick
//
//  Created by 김가윤 on 2/7/26.
//

import UIKit

/// 동일 key의 디스크 read + 디코딩(UIImage 생성)을 병합하는 actor
actor ThumbInFlightRegistry {
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    func getOrCreate(
        forKey key: String,
        create: @Sendable @escaping () async -> UIImage?
    ) -> Task<UIImage?, Never> {
        if let existing = tasks[key] { return existing }

        let task = Task { await create() }
        tasks[key] = task
        return task
    }

    func remove(forKey key: String) {
        tasks.removeValue(forKey: key)
    }
}
