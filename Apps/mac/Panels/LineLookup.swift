import Foundation
import HyperCore

extension Array where Element == OutlineItem {
    /// caret 줄 이하의 마지막 항목 id (이진 탐색, line 오름차순 전제)
    func lastIndexedLine(atOrBefore line: Int) -> Int? {
        var lo = 0, hi = count - 1, ans: Int?
        while lo <= hi { let mid = (lo + hi) / 2; if self[mid].line <= line { ans = self[mid].id; lo = mid + 1 } else { hi = mid - 1 } }
        return ans
    }
}

extension Array where Element == TimelineItem {
    func lastIndexedLine(atOrBefore line: Int) -> Int? {
        var lo = 0, hi = count - 1, ans: Int?
        while lo <= hi { let mid = (lo + hi) / 2; if self[mid].line <= line { ans = self[mid].id; lo = mid + 1 } else { hi = mid - 1 } }
        return ans
    }
}
