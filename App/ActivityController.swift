import ActivityKit
import Combine
import Foundation

@MainActor
final class ActivityController: ObservableObject {
    @Published private(set) var isActive = false
    @Published var message: String?
    @Published private var gate = ActivityOperationGate()
    private var pendingStates: [Provider: ProviderState]?
    private var isUpdating = false
    var isTransitioning: Bool { gate.isBusy }

    init() { synchronize() }

    func synchronize() {
        isActive = Activity<QuotaActivityAttributes>.activities.contains {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    private func content(_ states: [Provider: ProviderState]) -> ActivityContent<QuotaActivityAttributes.ContentState> {
        let state = QuotaActivityAttributes.ContentState(
            claude: states[.claude]!.activitySummary(provider: .claude),
            codex: states[.codex]!.activitySummary(provider: .codex))
        let oldestExpiry = states.values.compactMap { $0.snapshot?.staleDate }.min()
            ?? Date().addingTimeInterval(60)
        return ActivityContent(state: state, staleDate: oldestExpiry)
    }

    func start(currentStates: @MainActor () -> [Provider: ProviderState]) async {
        message = nil
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "請在 iPhone 設定 → Token Bar 開啟「即時動態」。"
            return
        }
        guard currentStates().values.contains(where: { $0.snapshot != nil }) else {
            message = "請先登入並成功讀取至少一個服務的額度。"
            return
        }
        guard let ticket = gate.begin() else { return }
        defer { gate.finish(ticket); synchronize() }
        for activity in Activity<QuotaActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard gate.accepts(ticket) else { return }
        // Read after the await. A refresh or identity change may have happened meanwhile.
        let states = currentStates()
        guard states.values.contains(where: { $0.snapshot != nil }) else { return }
        pendingStates = nil
        do {
            _ = try Activity.request(attributes: QuotaActivityAttributes(startedAt: Date()),
                                     content: content(states), pushType: nil)
            synchronize()
        } catch {
            message = "無法開啟卡片。請確認即時動態權限及側載時有保留 extension。"
        }
    }

    func update(states: [Provider: ProviderState]) async {
        pendingStates = states
        guard !isUpdating, !gate.isBusy else { return }
        isUpdating = true
        defer { isUpdating = false; synchronize() }
        while let latest = pendingStates {
            pendingStates = nil
            let generation = gate.generation
            for activity in Activity<QuotaActivityAttributes>.activities {
                guard gate.accepts(generation), !gate.isBusy else { break }
                if activity.activityState == .active || activity.activityState == .stale {
                    await activity.update(content(latest))
                }
            }
        }
    }

    func stop() async {
        gate.invalidate()
        pendingStates = nil
        for activity in Activity<QuotaActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        synchronize()
    }

    /// Synchronously cancels pending publication, then dismisses even ended cards.
    func invalidateIdentity() {
        gate.invalidate()
        pendingStates = nil
        let previous = Activity<QuotaActivityAttributes>.activities
        isActive = false
        Task {
            for activity in previous {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            synchronize()
        }
    }
}
