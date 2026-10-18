import ActivityKit
import Foundation

struct ActivityProvider: Codable, Hashable {
    let provider: Provider
    let windows: [QuotaWindow]
    let fetchedAt: Double?
    let notice: String
    var plan: String? = nil
    var nextRefreshAt: Double? = nil
    var refreshing: Bool? = nil

    var planLabel: String {
        let raw = (plan ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = ["pro": "Pro", "plus": "Plus", "prolite": "Pro Lite", "pro_lite": "Pro Lite",
                      "team": "Team", "business": "Business", "enterprise": "Enterprise", "free": "Free", "max": "Max"]
        return labels[raw.lowercased()] ?? String(raw.prefix(16))
    }
}

struct QuotaActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let claude: ActivityProvider
        let codex: ActivityProvider

        var isRefreshing: Bool { claude.refreshing == true || codex.refreshing == true }
        var nextRefresh: Date {
            let dates = [claude, codex].filter { $0.fetchedAt != nil || $0.notice != "尚未連接" }
                .map { $0.nextRefreshAt ?? 0 }
            return Date(timeIntervalSince1970: dates.min() ?? 0)
        }
    }
    let startedAt: Date
}
