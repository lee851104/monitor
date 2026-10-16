import Foundation

enum Provider: String, CaseIterable, Codable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var title: String { self == .claude ? "Claude" : "Codex" }
    var host: String { self == .claude ? "claude.ai" : "chatgpt.com" }
    var home: URL {
        URL(string: self == .claude ? "https://claude.ai/settings/usage" : "https://chatgpt.com/codex/settings/usage")!
    }
}

struct QuotaWindow: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetAt: Double?
    let windowSeconds: Double?
    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    var resetDate: Date? { resetAt.map(Date.init(timeIntervalSince1970:)) }
}

struct ProviderSnapshot: Codable, Hashable {
    let provider: Provider
    let windows: [QuotaWindow]
    let fetchedAt: Double
    let plan: String
    let organizationID: String?
    let accountLabel: String

    var fetchedDate: Date { Date(timeIntervalSince1970: fetchedAt) }
    var staleDate: Date {
        let reset = windows.compactMap(\.resetDate).min() ?? .distantFuture
        return min(fetchedDate.addingTimeInterval(300), reset)
    }
    func isStale(at date: Date) -> Bool {
        date >= staleDate || fetchedDate.timeIntervalSince(date) > 60
    }
}

struct Organization: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

enum QuotaError: String, Codable {
    case login, forbidden, rateLimited, challenge, server, network, format, selectOrganization

    var message: String {
        switch self {
        case .login: "請登入後再刷新"
        case .forbidden: "沒有讀取權限，請確認帳號或團隊"
        case .rateLimited: "服務暫時限流，請等倒數結束"
        case .challenge: "請開啟登入畫面，完成網站驗證"
        case .server: "服務暫時無法回應"
        case .network: "連線失敗，請稍後刷新"
        case .format: "無法辨識額度資料，請查看官方用量頁"
        case .selectOrganization: "請選擇要查看的團隊或個人空間"
        }
    }
    var shortMessage: String {
        switch self {
        case .login: "請登入"
        case .forbidden: "權限不足"
        case .rateLimited: "暫時限流"
        case .challenge: "需網站驗證"
        case .server: "服務異常"
        case .network: "連線失敗"
        case .format: "格式變更"
        case .selectOrganization: "請選團隊"
        }
    }
    var stopsAutomaticRefresh: Bool {
        [.login, .forbidden, .challenge, .format, .selectOrganization].contains(self)
    }
}

struct QuotaResult: Decodable {
    let status: String
    var snapshot: ProviderSnapshot? = nil
    var organizations: [Organization]? = nil
    var code: QuotaError? = nil
    var retryAfter: Double? = nil

    static func success(_ snapshot: ProviderSnapshot) -> Self {
        Self(status: "ok", snapshot: snapshot)
    }
    static func failure(_ code: QuotaError) -> Self {
        Self(status: "error", code: code)
    }
}

struct ProviderState {
    var enabled: Bool
    var snapshot: ProviderSnapshot?
    var organizations: [Organization] = []
    var error: QuotaError?
    var isRefreshing = false
    var nextAllowedRefresh = Date.distantPast
    private var failures = 0

    init(enabled: Bool) { self.enabled = enabled }

    func canRefresh(at date: Date, automatic: Bool) -> Bool {
        enabled && !isRefreshing && date >= nextAllowedRefresh &&
            (!automatic || error?.stopsAutomaticRefresh != true)
    }

    mutating func invalidateIdentity() {
        snapshot = nil
        error = nil
    }

    mutating func apply(_ result: QuotaResult, provider: Provider, now: Date) {
        isRefreshing = false
        if let options = result.organizations { organizations = options }
        if result.status == "ok", let measurement = result.snapshot, measurement.provider == provider {
            snapshot = measurement
            error = nil
            failures = 0
            nextAllowedRefresh = now.addingTimeInterval(5)
        } else if result.status == "selectOrganization" {
            snapshot = nil
            error = .selectOrganization
            nextAllowedRefresh = now
        } else {
            let issue = result.code ?? .format
            error = issue
            if issue == .login { snapshot = nil }
            failures += 1
            let delays: [Double] = [60, 120, 300, 900]
            let delay = issue == .rateLimited ? max(1, result.retryAfter ?? 60)
                : delays[min(failures - 1, delays.count - 1)]
            nextAllowedRefresh = now.addingTimeInterval(delay)
        }
    }

    func activitySummary(provider: Provider) -> ActivityProvider {
        ActivityProvider(provider: provider, windows: Array((snapshot?.windows ?? []).prefix(2)),
                         fetchedAt: snapshot?.fetchedAt,
                         notice: !enabled ? "尚未連接" : error?.shortMessage ?? (snapshot == nil ? "尚無資料" : ""))
    }
}
