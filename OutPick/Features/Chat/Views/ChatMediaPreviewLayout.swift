import UIKit

enum ChatMediaPreviewLayout {
    static func rows(count: Int) -> [Int] {
        guard count > 1 else { return [] }
        for threes in stride(from: count / 3, to: 0, by: -1) {
            let remaining = count - 3 * threes
            if remaining % 2 == 0 {
                return Array(repeating: 3, count: threes) + Array(repeating: 2, count: remaining / 2)
            }
        }
        return count % 2 == 0 ? Array(repeating: 2, count: count / 2) : []
    }

    static func frames(count: Int, width: CGFloat) -> [CGRect] {
        if count == 1 { return [CGRect(x: 4, y: 4, width: max(0, width - 8), height: max(0, width - 8))] }
        var y: CGFloat = 0
        var result: [CGRect] = []
        for row in rows(count: count) {
            let side = width / CGFloat(row)
            for column in 0..<row {
                result.append(CGRect(x: CGFloat(column) * side + 2, y: y + 2,
                                     width: max(0, side - 4), height: max(0, side - 4)))
            }
            y += side
        }
        return result
    }

    static func height(count: Int, width: CGFloat) -> CGFloat {
        count == 1 ? width : rows(count: count).reduce(0) { $0 + width / CGFloat($1) }
    }
}
