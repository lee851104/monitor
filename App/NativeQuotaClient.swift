import Foundation
import JavaScriptCore

/// Background reads use existing cookies in memory, sent only to their original service.
/// No cookie/token is stored in defaults, shared with the widget, or logged.
@MainActor
final class NativeQuotaClient {
    private let session: URLSession
    private struct Failure: Error {
        let code: QuotaError
        var retryAfter: Double? = nil
    }

    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        self.session = session ?? URLSession(configuration: config, delegate: NoQuotaRedirect(), delegateQueue: nil)
    }

    func collect(provider: Provider, organization: String?, cookies: [HTTPCookie]) async -> QuotaResult {
        do {
            let now = Date().timeIntervalSince1970
            if provider == .claude {
                let raw = try await request(provider, path: "/api/organizations", cookies: cookies)
                let selection = try parse("claudeSelection", arguments: [raw, organization as Any? ?? NSNull()])
                guard selection["status"] as? String == "ready",
                      let selected = selection["selected"] as? [String: Any],
                      let id = selected["id"] as? String, UUID(uuidString: id) != nil else {
                    return try decode(selection)
                }
                let data = try await request(provider, path: "/api/organizations/\(id)/usage", cookies: cookies)
                return try decode(parse("claudeUsage", arguments: [data, selection, now]))
            }
            let raw = try await request(provider, path: "/api/auth/session", cookies: cookies)
            guard let auth = raw as? [String: Any], let token = auth["accessToken"] as? String, !token.isEmpty else {
                return .failure(.login)
            }
            var headers = ["Authorization": "Bearer \(token)"]
            if let account = Self.accountID(token) { headers["ChatGPT-Account-Id"] = account }
            let data = try await request(provider, path: "/backend-api/wham/usage", cookies: cookies, headers: headers)
            let snapshot = try parse("parseCodex", arguments: [data, now])
            return try decode(["status": "ok", "snapshot": snapshot])
        } catch let failure as Failure {
            return QuotaResult(status: "error", code: failure.code, retryAfter: failure.retryAfter)
        } catch {
            return .failure(.network)
        }
    }

    private func request(_ provider: Provider, path: String, cookies: [HTTPCookie],
                         headers: [String: String] = [:]) async throws -> Any {
        guard !Task.isCancelled, let url = URL(string: "https://\(provider.host)\(path)"),
              url.scheme == "https", url.host == provider.host else { throw Failure(code: .network) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let scoped = cookies.filter { Self.cookie($0, matches: url) }
        for (key, value) in HTTPCookie.requestHeaderFields(with: scoped) { request.setValue(value, forHTTPHeaderField: key) }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure(code: .network) }
        let isJSON = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().contains("application/json")
        switch response.statusCode {
        case 200..<300: break
        case 300..<400, 401: throw Failure(code: .login)
        case 403: throw Failure(code: isJSON ? .forbidden : .challenge)
        case 429:
            let header = response.value(forHTTPHeaderField: "Retry-After") ?? ""
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let seconds = Double(header) ?? formatter.date(from: header)?.timeIntervalSinceNow ?? 60
            throw Failure(code: .rateLimited, retryAfter: seconds.isFinite ? max(1, seconds) : 60)
        case 500...599: throw Failure(code: .server)
        default: throw Failure(code: .format)
        }
        guard isJSON else { throw Failure(code: .challenge) }
        guard data.count <= 2_000_000, let json = try? JSONSerialization.jsonObject(with: data) else {
            throw Failure(code: .format)
        }
        return json
    }

    nonisolated static func cookie(_ cookie: HTTPCookie, matches url: URL) -> Bool {
        guard let host = url.host?.lowercased(), url.scheme == "https",
              cookie.expiresDate.map({ $0 > Date() }) ?? true else { return false }
        let domain = cookie.domain.lowercased()
        let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        guard host == bare || (domain.hasPrefix(".") && host.hasSuffix("." + bare)) else { return false }
        let path = url.path.isEmpty ? "/" : url.path
        return path == cookie.path || (path.hasPrefix(cookie.path) &&
            (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
    }

    private func parse(_ function: String, arguments: [Any]) throws -> [String: Any] {
        guard let url = Bundle.main.url(forResource: "quota-core", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8), let context = JSContext() else {
            throw Failure(code: .format)
        }
        context.evaluateScript(source)
        let result = context.objectForKeyedSubscript("QuotaCore")?.objectForKeyedSubscript(function)?.call(withArguments: arguments)
        if let exception = context.exception {
            let code = exception.objectForKeyedSubscript("code")?.toString() ?? "format"
            throw Failure(code: QuotaError(rawValue: code) ?? .format)
        }
        guard let object = result?.toDictionary() as? [String: Any] else { throw Failure(code: .format) }
        return object
    }

    private func decode(_ dictionary: [String: Any]) throws -> QuotaResult {
        do { return try JSONDecoder().decode(QuotaResult.self, from: JSONSerialization.data(withJSONObject: dictionary)) }
        catch { throw Failure(code: .format) }
    }

    private static func accountID(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = claims["https://api.openai.com/auth"] as? [String: Any],
              let id = auth["chatgpt_account_id"] as? String,
              id.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil else { return nil }
        return id
    }
}

private final class NoQuotaRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
