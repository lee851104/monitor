import SwiftUI
import WebKit

private struct OfficialWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct LoginView: View {
    @ObservedObject var session: BrowserSession
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "lock.shield")
                    Text(session.currentHost.isEmpty ? session.provider.host : session.currentHost)
                        .lineLimit(1).font(.caption.monospaced())
                    Spacer()
                    if session.pageLoading { ProgressView() }
                    Button { session.loadHome() } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                    }.accessibilityLabel("重新載入官方用量頁")
                }.padding(.horizontal)
                Text("在官方網站完成登入後，按右上角「完成並查詢」。登入資料只留在這台手機。")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 8)
                if session.provider == .claude {
                    Text("建議用 Email 驗證登入；Google 登入可能拒絕 App 內瀏覽器。")
                        .font(.caption).foregroundStyle(.orange).padding(.horizontal).padding(.bottom, 8)
                }
                OfficialWebView(webView: session.webView)
            }
            .navigationTitle("\(session.provider.title) 登入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("稍後") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成並查詢") { dismiss(); onComplete() }
                }
            }
            .onAppear { session.openLogin() }
        }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("第一次使用") {
                    Text("1. 分別連接 Claude 與 Codex，在官方網站登入。")
                    Text("2. Claude 有多個空間時，選擇你的 Team。")
                    Text("3. 核對額度後按「開啟額度卡片」，再鎖定手機查看。")
                }
                Section("刷新與顯示") {
                    Text("卡片的更新按鈕會在背景嘗試查詢兩個服務，不切換到 App。若網站要求重新登入或驗證，請點卡片其他位置開 App。背景查詢仍可能被系統或網站限制。")
                    Text("App 開在前景時約每分鐘嘗試更新。手動刷新至少間隔五秒，遇到服務限流會延長等待。")
                    Text("即時動態最多運作八小時，可能被系統提前結束；到期回 App 重新開啟。卡片不是永久通知。")
                    Text("百分比是訂閱額度，不是剩餘 token 數。沒有回傳的限制不會顯示；到重置時間也要刷新才確認恢復。")
                }
                Section("登入問題") {
                    Text("網站可能要求驗證，或拒絕內嵌瀏覽器／公司 SSO。請先在登入畫面完成驗證；如果仍被拒絕，本版無法保證支援你的登入方式。")
                    Text("額度來源是網站內部唯讀介面，可能隨服務改版而失效。Team 權限也可能不提供用量。")
                }
                Section("隱私") {
                    Text("只查詢官方網站的登入狀態、組織清單與額度。沒有模型請求、分析追蹤、第三方同步或付款操作。")
                    Text("Cookie 由 iOS WebKit 保存。背景查詢時只在本機記憶體取用，並傳回其所屬官方服務；不寫入共享檔案或傳給卡片。額度快照只在記憶體與系統即時動態中顯示。")
                    Text("登出會清除該服務的 WebKit 資料並關閉額度卡片。鎖定畫面可看到額度，請自行決定是否開啟。")
                }
                Section("免費安裝") {
                    Text("免費側載每七天要用 iloader 或 AltStore 續簽。電腦只需在安裝和續簽時開機，查額度時不需要。不要移除即時動態 extension。")
                }
            }
            .navigationTitle("使用說明")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
