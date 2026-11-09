import CoreLocation
import Foundation

/// Picks the fastest order to visit trip stops.
enum TripOptimizer {
    /// `times[i][j]` is the travel time from place i to place j; place 0 is the start and
    /// 1…n are the stops. Returns the stop numbers (1…n) in the order to visit them.
    static func bestOrder(times: [[Double]], keepLastFixed: Bool) -> [Int] {
        let n = times.count - 1
        guard n > 1 else { return Array(1 ... max(1, n)).filter { $0 <= n } }
        let fixedEnd = keepLastFixed ? n : nil
        let free = (1 ... n).filter { $0 != fixedEnd }

        func cost(_ order: [Int]) -> Double {
            var total = 0.0, from = 0
            for stop in order + (fixedEnd.map { [$0] } ?? []) {
                total += times[from][stop]
                from = stop
            }
            return total
        }

        if free.count <= 8 {
            // Try every order (8! = 40,320 at most), pruning anything already worse.
            var best = free, bestCost = cost(free)
            var current: [Int] = []
            var used = Set<Int>()
            func search(_ from: Int, _ soFar: Double) {
                if soFar >= bestCost { return }
                if current.count == free.count {
                    let total = soFar + (fixedEnd.map { times[from][$0] } ?? 0)
                    if total < bestCost { bestCost = total; best = current }
                    return
                }
                for s in free where !used.contains(s) {
                    used.insert(s); current.append(s)
                    search(s, soFar + times[from][s])
                    current.removeLast(); used.remove(s)
                }
            }
            search(0, 0)
            return best + (fixedEnd.map { [$0] } ?? [])
        }

        // Many stops: nearest neighbor, then 2-opt improvements.
        var order: [Int] = []
        var left = Set(free), from = 0
        while let next = left.min(by: { times[from][$0] < times[from][$1] }) {
            order.append(next); left.remove(next); from = next
        }
        var improved = true
        while improved {
            improved = false
            for i in 0 ..< order.count - 1 {
                for j in i + 1 ..< order.count {
                    var candidate = order
                    candidate[i ... j].reverse()
                    if cost(candidate) + 0.5 < cost(order) {
                        order = candidate
                        improved = true
                    }
                }
            }
        }
        return order + (fixedEnd.map { [$0] } ?? [])
    }

    /// Reads a Valhalla matrix response in either the older nested or newer columnar format.
    static func parseMatrix(_ json: String, count: Int) -> [[Double]]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        var times = Array(repeating: Array(repeating: Double.infinity, count: count), count: count)
        if let rows = obj["sources_to_targets"] as? [[[String: Any]]] {
            for (i, row) in rows.enumerated() where i < count {
                for (j, cell) in row.enumerated() where j < count {
                    if let t = cell["time"] as? Double { times[i][j] = t }
                }
            }
        } else if let cols = obj["sources_to_targets"] as? [String: Any],
                  let durations = cols["durations"] as? [[Any]]
        {
            for (i, row) in durations.enumerated() where i < count {
                for (j, cell) in row.enumerated() where j < count {
                    if let t = cell as? Double { times[i][j] = t }
                }
            }
        } else {
            return nil
        }
        // Unreachable pairs get a big but finite cost so the search still works.
        return times.map { $0.map { $0.isFinite ? $0 : 1e7 } }
    }

    /// Fallback when no routing engine is around: straight-line distance at ~45 km/h.
    static func straightLineTimes(_ points: [CLLocationCoordinate2D]) -> [[Double]] {
        points.map { a in
            points.map { b in
                CLLocation(latitude: a.latitude, longitude: a.longitude)
                    .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 12.5
            }
        }
    }
}
