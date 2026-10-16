import ActivityKit
import Foundation

struct ActivityProvider: Codable, Hashable {
    let provider: Provider
    let windows: [QuotaWindow]
    let fetchedAt: Double?
    let notice: String
}

struct QuotaActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let claude: ActivityProvider
        let codex: ActivityProvider
    }
    let startedAt: Date
}
