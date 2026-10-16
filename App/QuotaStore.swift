import Foundation
import Combine

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var states: [Provider: ProviderState]
    @Published private(set) var signingReminder: Date
    let activities = ActivityController()
    private(set) var sessions: [Provider: BrowserSession]
    private var generations: [Provider: Int] = [.claude: 0, .codex: 0]
    private let defaults = UserDefaults.standard

    init() {
        states = Dictionary(uniqueKeysWithValues: Provider.allCases.map {
            ($0, ProviderState(enabled: UserDefaults.standard.bool(forKey: "connected." + $0.rawValue)))
        })
        sessions = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, BrowserSession(provider: $0)) })
        signingReminder = UserDefaults.standard.object(forKey: "renewedAt") as? Date ?? Date()
        if UserDefaults.standard.object(forKey: "renewedAt") == nil {
            UserDefaults.standard.set(signingReminder, forKey: "renewedAt")
        }
    }

    var organizationID: String? { defaults.string(forKey: "claude.organization") }

    func markRenewed() {
        signingReminder = Date()
        defaults.set(signingReminder, forKey: "renewedAt")
    }

    func connect(_ provider: Provider) async {
        generations[provider, default: 0] += 1
        states[provider]?.isRefreshing = false
        states[provider]?.enabled = true
        states[provider]?.invalidateIdentity()
        defaults.set(true, forKey: "connected." + provider.rawValue)
        await activities.update(states: states)
        await refresh(provider)
    }

    func beginLogin(_ provider: Provider) {
        activities.invalidateIdentity()
        generations[provider, default: 0] += 1
        states[provider]?.isRefreshing = false
        states[provider]?.invalidateIdentity()
        states[provider]?.error = .login
    }

    func selectOrganization(_ id: String) async {
        guard states[.claude]?.organizations.contains(where: { $0.id == id }) == true else { return }
        activities.invalidateIdentity()
        generations[.claude, default: 0] += 1
        states[.claude]?.isRefreshing = false
        states[.claude]?.invalidateIdentity()
        defaults.set(id, forKey: "claude.organization")
        await activities.update(states: states)
        await refresh(.claude)
    }

    func disconnect(_ provider: Provider) async {
        activities.invalidateIdentity()
        generations[provider, default: 0] += 1
        states[provider] = ProviderState(enabled: false)
        states[provider]?.isRefreshing = true
        defaults.set(false, forKey: "connected." + provider.rawValue)
        if provider == .claude { defaults.removeObject(forKey: "claude.organization") }
        // Remove private numbers from an already ended/stale activity as well.
        await activities.stop()
        await sessions[provider]?.clearLogin()
        sessions[provider] = BrowserSession(provider: provider)
        states[provider]?.isRefreshing = false
    }

    func refreshAll(automatic: Bool = false) async {
        // Each service remains independently refreshable; failures never cancel the other.
        async let claude: Void = refresh(.claude, automatic: automatic)
        async let codex: Void = refresh(.codex, automatic: automatic)
        _ = await (claude, codex)
    }

    func startActivity() async {
        await activities.start(currentStates: { self.states })
    }

    func refresh(_ provider: Provider, automatic: Bool = false) async {
        guard states[provider]?.canRefresh(at: Date(), automatic: automatic) == true,
              let browser = sessions[provider] else { return }
        let generation = generations[provider, default: 0]
        states[provider]?.isRefreshing = true
        let result = await browser.collect(organization: provider == .claude ? organizationID : nil)
        guard generation == generations[provider] else { return }
        if result.code == .login || result.status == "selectOrganization" {
            activities.invalidateIdentity()
        }
        states[provider]?.apply(result, provider: provider, now: Date())
        if provider == .claude, result.status == "ok", let selected = result.snapshot?.organizationID {
            defaults.set(selected, forKey: "claude.organization")
        }
        await activities.update(states: states)
    }
}
