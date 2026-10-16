# 進度 — 2026-10-17-token-bar-ios

- 使用者已授權依前述規格開發與免費七天續簽，不再要求重複核准。
- workspace 根目錄不是 Git repository，既有 vendor-review 是另一個 Windows 專案；以獨立 ios/ 資料夾隔離，不改動舊專案。
- 本機有 Node/Python，沒有 Swift、Xcode、gh。iOS build 需要 macOS CI，目前沒有已授權的 GitHub 發布目的地。
- 決定：卡片刷新採 deep link 開 App，避免承諾無法驗證的背景網路執行；沒有 App Groups 或推播 entitlement。
- 決定：使用官方網頁登入工作階段，避免第三方 OAuth client 冒用與手動複製 token。
- Task 1/2 共用 JSON snapshot，Task 2/3 共用工程 target 與 bundle 路徑；後續依測試驗證。

## 實作結果

- Task 1：完成。先建立介面 stub，21 項 Node 測試有 20 項失敗；補齊真實產品使用的 JS 資料層後 21/21 通過。唯一原先通過的是空結果測試，後續格式/缺欄位測試確保不掩蓋錯誤。
- Task 2：SwiftUI、WebKit、Team 選擇、冷卻/退避、個別錯誤、登入清除、前景更新、ActivityKit 卡片與 deep link 刷新已實作。11 項原生測試已寫，因 Windows 沒有 Swift/Xcode，尚未執行，不宣稱通過。
- Task 3：7 項 Python 測試先因缺少打包功能失敗，實作後 7/7 通過。可產生只含本專案程式的 source ZIP；CI 包含模擬器測試、真機 archive、未簽署 IPA 與 SHA-256。
- 獨立 reviewer 首輪發現：到期卡片保留舊身分；非同步重啟可能發布舊快照或重複卡片。已加入身分同步失效/移除到期卡片、ActivityOperationGate、等待後重新讀取狀態及更新合併。第二輪未發現新的重要問題。
- 檢查補充：登出清除 WebKit 資料期間禁用登入，避免新登入與舊資料清除重疊。
- 未改動根目錄既有 openspec、build-tools 或 vendor-review Windows 程式。

## 尚待外部驗證（不是完成）

- 首次 CI 已成功編譯 Swift，但 Xcode 16.4 / iOS 18.5 模擬器因缺少 `libswiftWebKit.dylib` 在測試啟動前崩潰。對照 [WebKit 293831](https://bugs.webkit.org/show_bug.cgi?id=293831) 後，將 CI 固定到 runner 已提供的 Xcode 26.3 / iOS 26.2，保留 iOS 17 部署目標。

- 使用者提供／建立 GitHub repository 後執行 macOS workflow；目前沒有遠端目的地，也未上傳任何程式。
- Xcode 編譯、11 項 native tests、未簽署 IPA 尚未由 Apple 工具產生。
- Claude Team / ChatGPT 真實登入、官方用量比對、iPhone 13 卡片呈現及七天續簽，均未實測。
- 本機通過的 28 項測試只證明資料層與打包工具的行為，不能代替上述驗證。
