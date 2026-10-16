# Token Bar iPhone 設計

使用者已同意：iPhone 13、iOS 26.3.1，只有 Windows，免費自用，可每七天續簽；日常查詢不依賴電腦。Claude 是 Team 席次；Codex 目前 Pro，以後可能 Plus。以手動刷新換取可預期的新鮮度。

## 功能

- 原生 SwiftUI App，最低 iOS 17；兩個服務分別登入、刷新、登出。
- 使用 App 內的官方網站登入；登入 Cookie 留在 iOS WebKit 儲存區。查詢僅送官方服務，沒有中繼伺服器、分析、模型呼叫或 API key。
- Claude 列出可用組織，明確選擇 Team；不在多組織時擅自選第一個。
- 顯示實際回傳的用量百分比、重置時間、每個服務最後成功更新時間。未回傳的限制不捏造為 0%；Pro/Plus 切換依回傳資料。
- 一張 ActivityKit 即時動態卡片同時顯示兩個服務，點擊開 App 立即刷新。卡片本身沒有背景輪詢。App 前景每 60 秒嘗試刷新，也提供手動刷新；429 時遵守冷卻。
- 卡片以 Activity content 傳遞數字，不使用 App Groups、推播、共用 Keychain，降低免費簽署要求。到期需使用者重新開啟。
- 失敗保留舊量測並明確顯示錯誤與原時間；登入失效、登出或改組織則清除舊量測。沒有帳號時沒有假資料。

## 交付與界線

- Windows 可測試實際使用的 JavaScript 資料層；SwiftUI/ActivityKit 由 macOS CI 編譯、測試，產出未簽署 IPA，再交 AltStore 簽署安裝。
- 不讀取本機已登入的 Claude、Codex 憑證，不替使用者登入，不把登入資料放進原始碼、CI 或產物。
- 不宣稱能永久釘選通知、不宣稱背景每分鐘更新。即時動態最長八小時；iPhone 13 用鎖定畫面版面。
- 官方內部網頁端點可能變動、Cloudflare/SSO 可能拒絕嵌入式瀏覽器；須實機驗證登入與 Team 額度。
- 這台 Windows 無 Apple SDK，不能把本機資料層測試說成 iOS 編譯或實機驗證。

## 技術決定

SwiftUI + WebKit + ActivityKit + WidgetKit。登入只用 WebKit 官方網站，不冒用其他 App 的 OAuth client。JavaScript 純函式與網頁查詢程式是產品資源，Node 原生測試直接載入相同檔案。XcodeGen 產生 Xcode 工程，CI 執行模擬器測試和真機架構未簽署建置。
