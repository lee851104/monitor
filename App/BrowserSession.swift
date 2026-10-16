import Foundation
import Combine
import WebKit

/// The official site's cookie jar stays in WebKit. Only sanitized quota leaves it.
@MainActor
final class BrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let provider: Provider
    let webView: WKWebView
    @Published private(set) var currentHost = ""
    @Published private(set) var pageLoading = false
    private var navigationFailed = false
    private static let script: String? = Bundle.main.url(forResource: "quota-core", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    init(provider: Provider) {
        self.provider = provider
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func openLogin() {
        if webView.url == nil || navigationFailed {
            loadHome()
        }
    }

    func loadHome() {
        navigationFailed = false
        pageLoading = true
        webView.load(URLRequest(url: provider.home, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
    }

    func collect(organization: String?) async -> QuotaResult {
        guard let script = Self.script else { return .failure(.format) }
        if webView.url == nil || navigationFailed { loadHome() }
        // A bounded wait permits login redirects but never runs our reader on an identity provider.
        for _ in 0..<100 {
            if !pageLoading && !webView.isLoading { break }
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return .failure(.network) }
        }
        guard !Task.isCancelled, !navigationFailed, !pageLoading, !webView.isLoading else {
            return .failure(.network)
        }
        guard webView.url?.scheme == "https", webView.url?.host == provider.host else {
            return .failure(.login)
        }
        do {
            let body = script + "\nreturn await QuotaCore.collect(provider, organization);"
            let raw = try await webView.callAsyncJavaScript(body,
                arguments: ["provider": provider.rawValue, "organization": organization as Any? ?? NSNull()],
                in: nil, contentWorld: .defaultClient)
            guard let dictionary = raw as? [String: Any] else { return .failure(.format) }
            let data = try JSONSerialization.data(withJSONObject: dictionary)
            return try JSONDecoder().decode(QuotaResult.self, from: data)
        } catch {
            // Never display WK errors or provider bodies: they may contain URLs or session material.
            return .failure(.network)
        }
    }

    func clearLogin() async {
        webView.stopLoading()
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let domains = provider == .claude ? ["claude.ai", "anthropic.com"] : ["chatgpt.com", "openai.com"]
        let matches = records.filter { record in
            domains.contains { record.displayName == $0 || record.displayName.hasSuffix("." + $0) }
        }
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matches)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pageLoading = true
        navigationFailed = false
        currentHost = webView.url?.host ?? provider.host
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoading = false
        currentHost = webView.url?.host ?? provider.host
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pageLoading = false
        navigationFailed = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Cancelled navigation is normal when an OAuth page redirects.
        if (error as NSError).code != NSURLErrorCancelled {
            pageLoading = false
            navigationFailed = true
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == "https" ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, navigationAction.request.url?.scheme == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
