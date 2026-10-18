import AppIntents

struct RefreshQuotaIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "更新額度"
    static var description = IntentDescription("在背景查詢 Claude 與 Codex 額度。需要登入時請開啟 Token Bar。")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if TOKENBAR_APP
        await QuotaStore.shared.refreshFromActivity()
        #endif
        return .result()
    }
}
