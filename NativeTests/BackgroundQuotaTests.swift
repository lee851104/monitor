import XCTest
import WebKit
@testable import TokenBar

final class BackgroundQuotaTests: XCTestCase {
    @MainActor
    func testBackgroundClaudeUsesSelectedTeamAndReturnsOnlyQuota() async throws {
        let org = "11111111-1111-4111-8111-111111111111"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QuotaURLProtocol.self]
        QuotaURLProtocol.responses = [
            "/api/organizations": (200, "application/json", "[{\"uuid\":\"\(org)\",\"name\":\"Work\",\"analytics_subscription_plan\":\"claude_team\"}]"),
            "/api/organizations/\(org)/usage": (200, "application/json", "{\"five_hour\":{\"utilization\":88,\"resets_at\":null},\"seven_day\":{\"utilization\":35,\"resets_at\":null}}")
        ]
        QuotaURLProtocol.requests = []
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: ".claude.ai", .path: "/", .name: "sessionKey", .value: "test-only", .secure: "TRUE"]))
        let client = NativeQuotaClient(session: session)
        let result = await client.collect(provider: .claude, organization: org, cookies: [cookie])
        XCTAssertEqual(result.snapshot?.plan, "Team")
        XCTAssertEqual(result.snapshot?.windows.map(\.remainingPercent), [12, 65])
        XCTAssertEqual(QuotaURLProtocol.requests.count, 2)
        XCTAssertEqual(QuotaURLProtocol.requests.first?.value(forHTTPHeaderField: "Cookie"), "sessionKey=test-only")
        XCTAssertTrue(QuotaURLProtocol.requests.allSatisfy { $0.url?.host == "claude.ai" && $0.httpMethod == "GET" })
    }

    @MainActor
    func testBackgroundChallengeDoesNotTurnHTMLIntoQuota() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QuotaURLProtocol.self]
        QuotaURLProtocol.responses = ["/api/organizations": (403, "text/html", "<html>verification</html>")]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let result = await NativeQuotaClient(session: session).collect(provider: .claude, organization: nil, cookies: [])
        XCTAssertEqual(result.code, .challenge)
        XCTAssertNil(result.snapshot)
    }

    @MainActor
    func testBackgroundCodexKeepsTokenOutOfQuotaResult() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QuotaURLProtocol.self]
        QuotaURLProtocol.responses = [
            "/api/auth/session": (200, "application/json", "{\"accessToken\":\"test-only-token\"}"),
            "/backend-api/wham/usage": (200, "application/json", "{\"plan_type\":\"plus\",\"rate_limit\":{\"primary_window\":{\"used_percent\":12,\"limit_window_seconds\":18000}}}")
        ]
        QuotaURLProtocol.requests = []
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let result = await NativeQuotaClient(session: session).collect(provider: .codex, organization: nil, cookies: [])
        XCTAssertEqual(result.snapshot?.plan, "plus")
        XCTAssertEqual(result.snapshot?.windows.first?.remainingPercent, 88)
        XCTAssertEqual(QuotaURLProtocol.requests.count, 2)
        XCTAssertNil(QuotaURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(QuotaURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-token")
        XCTAssertTrue(QuotaURLProtocol.requests.allSatisfy { $0.url?.host == "chatgpt.com" && $0.httpMethod == "GET" })
        let json = String(decoding: try JSONEncoder().encode(result.snapshot), as: UTF8.self)
        XCTAssertFalse(json.contains("test-only-token"))
    }

    @MainActor
    func testBackgroundRateLimitPreservesRetryAfter() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QuotaURLProtocol.self]
        QuotaURLProtocol.responses = ["/api/organizations": (429, "application/json", "{}")]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let result = await NativeQuotaClient(session: session).collect(provider: .claude, organization: nil, cookies: [])
        XCTAssertEqual(result.code, .rateLimited)
        XCTAssertEqual(result.retryAfter, 120)
        XCTAssertNil(result.snapshot)
    }

    func testCookieScopeCannotLeakToAnotherServiceOrPath() throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: ".claude.ai", .path: "/api", .name: "sessionKey", .value: "test-only", .secure: "TRUE"]))
        XCTAssertTrue(NativeQuotaClient.cookie(cookie, matches: URL(string: "https://claude.ai/api/organizations")!))
        for url in ["https://chatgpt.com/api/auth/session", "https://evilclaude.ai/api/organizations", "http://claude.ai/api", "https://claude.ai/apix"] {
            XCTAssertFalse(NativeQuotaClient.cookie(cookie, matches: URL(string: url)!))
        }
    }
}

private final class QuotaURLProtocol: URLProtocol {
    static var responses: [String: (Int, String, String)] = [:]
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        guard let url = request.url, let entry = Self.responses[url.path],
              let response = HTTPURLResponse(url: url, statusCode: entry.0, httpVersion: nil,
                  headerFields: ["Content-Type": entry.1, "Retry-After": "120"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(entry.2.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
