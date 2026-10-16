import XCTest
@testable import TokenBar

final class QuotaStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_195_200)

    private func measurement(reset: Double? = nil) -> ProviderSnapshot {
        ProviderSnapshot(provider: .claude, windows: [
            QuotaWindow(id: "five_hour", label: "5 小時", usedPercent: 25,
                        resetAt: reset, windowSeconds: 18000)
        ], fetchedAt: now.timeIntervalSince1970, plan: "", organizationID: "team-a", accountLabel: "Team")
    }

    func testNetworkFailurePreservesOriginalMeasurementTime() {
        var state = ProviderState(enabled: true)
        state.apply(.success(measurement()), provider: .claude, now: now)
        state.apply(.failure(.network), provider: .claude, now: now.addingTimeInterval(90))
        XCTAssertEqual(state.snapshot?.fetchedAt, now.timeIntervalSince1970)
        XCTAssertEqual(state.snapshot?.windows.first?.usedPercent, 25)
        XCTAssertEqual(state.error, .network)
    }

    func testLoginFailureRemovesPreviousAccountsNumbers() {
        var state = ProviderState(enabled: true)
        state.apply(.success(measurement()), provider: .claude, now: now)
        state.apply(.failure(.login), provider: .claude, now: now)
        XCTAssertNil(state.snapshot)
        XCTAssertFalse(state.canRefresh(at: now.addingTimeInterval(300), automatic: true))
        XCTAssertTrue(state.canRefresh(at: now.addingTimeInterval(300), automatic: false))
    }

    func testRateLimitCannotBeBypassedByManualRefresh() {
        var state = ProviderState(enabled: true)
        state.apply(QuotaResult(status: "error", code: .rateLimited, retryAfter: 120),
                    provider: .claude, now: now)
        XCTAssertFalse(state.canRefresh(at: now.addingTimeInterval(119), automatic: false))
        XCTAssertTrue(state.canRefresh(at: now.addingTimeInterval(120), automatic: false))
    }

    func testSelectingTeamClearsOldSnapshotWithoutDroppingCooldown() {
        var state = ProviderState(enabled: true)
        state.apply(.success(measurement()), provider: .claude, now: now)
        state.nextAllowedRefresh = now.addingTimeInterval(120)
        state.invalidateIdentity()
        XCTAssertNil(state.snapshot)
        XCTAssertEqual(state.nextAllowedRefresh, now.addingTimeInterval(120))
    }

    func testSuccessfulRefreshOfOneProviderDoesNotAcceptAnotherProvidersSnapshot() {
        var state = ProviderState(enabled: true)
        state.apply(.success(measurement()), provider: .codex, now: now)
        XCTAssertNil(state.snapshot)
        XCTAssertEqual(state.error, .format)
    }

    func testStaleAtResetBoundaryWithoutInventingRemainingQuota() {
        let snapshot = measurement(reset: now.timeIntervalSince1970 + 20)
        XCTAssertFalse(snapshot.isStale(at: now))
        XCTAssertTrue(snapshot.isStale(at: now.addingTimeInterval(20)))
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 75)
    }

    func testFiveMinuteStalenessAndFutureDeviceClock() {
        let snapshot = measurement()
        XCTAssertTrue(snapshot.isStale(at: now.addingTimeInterval(300)))
        XCTAssertTrue(snapshot.isStale(at: now.addingTimeInterval(-120)))
    }

    func testActivityPayloadOmitsOrganizationIdentityAndFitsSystemLimit() throws {
        var state = ProviderState(enabled: true)
        state.apply(.success(measurement()), provider: .claude, now: now)
        let content = QuotaActivityAttributes.ContentState(
            claude: state.activitySummary(provider: .claude),
            codex: ProviderState(enabled: false).activitySummary(provider: .codex))
        let data = try JSONEncoder().encode(content)
        XCTAssertLessThan(data.count, 3500)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("team-a"))
        XCTAssertFalse(json.contains("accountLabel"))
    }

    func testRealJavascriptResultDecodesWithoutDateStrategy() throws {
        let data = Data(#"{"status":"ok","snapshot":{"provider":"codex","windows":[{"id":"primary_window","label":"每週","usedPercent":0,"resetAt":null,"windowSeconds":604800}],"fetchedAt":1792195200,"plan":"pro","organizationID":null,"accountLabel":""}}"#.utf8)
        let result = try JSONDecoder().decode(QuotaResult.self, from: data)
        XCTAssertEqual(result.snapshot?.windows.first?.remainingPercent, 100)
        XCTAssertEqual(result.snapshot?.plan, "pro")
    }

    func testTwoStartTapsCannotPublishTwoActivities() {
        var gate = ActivityOperationGate()
        let first = gate.begin()
        XCTAssertNotNil(first)
        XCTAssertNil(gate.begin())
        gate.finish(first!)
        XCTAssertNotNil(gate.begin())
    }

    func testIdentityChangeCancelsAnAwaitingStartAndOldCompletionCannotUnlockNewStart() {
        var gate = ActivityOperationGate()
        let old = gate.begin()!
        gate.invalidate()
        XCTAssertFalse(gate.accepts(old))
        let current = gate.begin()!
        gate.finish(old)
        XCTAssertTrue(gate.accepts(current))
        XCTAssertNil(gate.begin())
        gate.finish(current)
        XCTAssertFalse(gate.isBusy)
    }
}
