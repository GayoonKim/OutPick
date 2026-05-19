//
//  Array+Chunked.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/26.
//

import Foundation

extension Array {
    /// Firestore whereIn 10개 제한 대응을 위한 배열 분할 유틸
    func chunked(max: Int) -> [[Element]] {
        guard max > 0 else { return [self] }

        var result: [[Element]] = []
        result.reserveCapacity((count / max) + 1)

        var i = 0
        while i < count {
            let end = Swift.min(i + max, count)
            result.append(Array(self[i..<end]))
            i = end
        }
        return result
    }
}
