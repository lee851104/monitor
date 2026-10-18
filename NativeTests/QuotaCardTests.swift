import XCTest
import SwiftUI
@testable import TokenBar

final class QuotaCardTests: XCTestCase {
    func testOldActivityPayloadStillDecodesAndDoesNotInventAPlan() throws {
        let json = #"{"provider":"claude","windows":[],"fetchedAt":null,"notice":"尚未連接"}"#
        let summary = try JSONDecoder().decode(ActivityProvider.self, from: Data(json.utf8))
        XCTAssertEqual(summary.planLabel, "")
        XCTAssertNil(summary.refreshing)
    }

    func testPlanAndCooldownAreIncludedWithoutAccountIdentity() throws {
        var state = ProviderState(enabled: true)
        state.apply(.success(ProviderSnapshot(provider: .codex, windows: [], fetchedAt: 100,
            plan: "prolite", organizationID: "private-org", accountLabel: "private-name")), provider: .codex,
            now: Date(timeIntervalSince1970: 100))
        let summary = state.activitySummary(provider: .codex)
        XCTAssertEqual(summary.planLabel, "Pro Lite")
        XCTAssertEqual(summary.nextRefreshAt, 105)
        let json = String(decoding: try JSONEncoder().encode(summary), as: UTF8.self)
        XCTAssertFalse(json.contains("private-org"))
        XCTAssertFalse(json.contains("private-name"))
    }

    @MainActor
    func testCardRendersAtPhoneWidthsWithinSystemHeight() throws {
        let now = Date().timeIntervalSince1970
        let claude = ActivityProvider(provider: .claude, windows: [
            QuotaWindow(id: "five_hour", label: "5 小時", usedPercent: 88, resetAt: now + 10140, windowSeconds: 18000),
            QuotaWindow(id: "seven_day", label: "每週", usedPercent: 35, resetAt: now + 86400, windowSeconds: 604800)
        ], fetchedAt: now, notice: "", plan: "Team")
        let codex = ActivityProvider(provider: .codex, windows: [
            QuotaWindow(id: "primary_window", label: "每週", usedPercent: 43, resetAt: now + 604800, windowSeconds: 604800)
        ], fetchedAt: now, notice: "", plan: "prolite")
        for width in [320.0, 366.0] {
            let content = QuotaActivityAttributes.ContentState(claude: claude, codex: codex)
            let view = QuotaCardView(content: content, isStale: false)
                .frame(width: width).background(Color(red: 0.067, green: 0.098, blue: 0.133))
                .environment(\.colorScheme, .dark).environment(\.locale, Locale(identifier: "zh_TW"))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.height, 160, accuracy: 1)
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = "quota-card-\(Int(width))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
