import Foundation
import Combine

/// 每日统计：记录每天完成了多少个专注周期 / 休息周期。
struct DayStats: Codable, Identifiable {
    var dateKey: String
    var focusCycles: Int
    var breakCycles: Int
    var focusSeconds: Int

    var id: String { dateKey }
}

/// 统计数据持久化。
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    @Published private(set) var days: [DayStats] = []

    private let defaults = UserDefaults.standard
    private let key = "com.eyetimer.stats.v1"
    private let calendar = Calendar.current

    private init() {
        load()
    }

    private func dateKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func load() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([DayStats].self, from: data) {
            days = decoded.sorted { $0.dateKey < $1.dateKey }
        } else {
            days = []
        }
    }

    private func save() {
        // 只保留最近 120 天
        if days.count > 120 {
            days = Array(days.suffix(120))
        }
        if let data = try? JSONEncoder().encode(days) {
            defaults.set(data, forKey: key)
        }
    }

    /// 记录一次完成的专注周期
    func recordFocusCycle(seconds: Int) {
        mutate { day in
            day.focusCycles += 1
            day.focusSeconds += seconds
        }
    }

    /// 记录一次完成的休息
    func recordBreakCycle() {
        mutate { day in
            day.breakCycles += 1
        }
    }

    private func mutate(_ change: (inout DayStats) -> Void) {
        let key = dateKey(for: Date())
        if let idx = days.firstIndex(where: { $0.dateKey == key }) {
            change(&days[idx])
        } else {
            var day = DayStats(dateKey: key, focusCycles: 0, breakCycles: 0, focusSeconds: 0)
            change(&day)
            days.append(day)
            days.sort { $0.dateKey < $1.dateKey }
        }
        save()
    }

    var today: DayStats {
        let key = dateKey(for: Date())
        return days.first(where: { $0.dateKey == key })
            ?? DayStats(dateKey: key, focusCycles: 0, breakCycles: 0, focusSeconds: 0)
    }

    /// 最近 n 天（含今天），按时间正序
    func recentDays(_ n: Int) -> [DayStats] {
        let todayKey = dateKey(for: Date())
        var map: [String: DayStats] = [:]
        for d in days { map[d.dateKey] = d }
        var result: [DayStats] = []
        for offset in stride(from: n - 1, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let k = dateKey(for: date)
            result.append(map[k] ?? DayStats(dateKey: k, focusCycles: 0, breakCycles: 0, focusSeconds: 0))
        }
        _ = todayKey
        return result
    }
}
