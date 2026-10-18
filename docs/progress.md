# 進度 — 2026-10-17-token-bar-ios

## 2026-10-18：0.2.0 卡片更新

- 使用者已確認 0.1.0 透過 Windows iloader 免費側載成功，Claude Team 與 Codex 額度可讀取。
- 核准版面：左右並排、Claude 星芒／OpenAI 結形標誌、實際方案標籤、剩餘進度條、44 點高的更新按鈕。原生卡片收斂在 160 點高。
- 背景更新改用 LiveActivityIntent 在 App 程序執行；以 WebKit 現有 Cookie 在記憶體發出官方 HTTPS GET，拒絕重新導向，沿用資料解析、冷卻與身分切換保護。
- 獨立審查發現初始化順序及鎖屏按鈕可能永久停用問題，均已修正；按鈕始終可點，請求冷卻由 App 狀態處理。
- 本機 24 項 Node、7 項 Python 測試通過。GitHub 執行原生測試、真機 archive 與卡片渲染，結果以各次 Actions 紀錄為準。
- 真實帳號的鎖屏背景更新、登入 Cookie 在背景的可用性與更新後側載，仍需實機確認。下方為舊版開發紀錄。

- 使用者已授權依前述規格開發與免費七天續簽，不再要求重複核准。
- workspace 根目錄不是 Git repository，既有 vendor-review 是另一個 Windows 專案；以獨立 ios/ 資料夾隔離，不改動舊專案。
- 本機有 Node/Python，沒有 Swift、Xcode；使用 GitHub macOS CI。GitHub CLI 已下載到 workspace 的 build-tools，沒有放進程式碼。
- 決定：卡片刷新採 deep link 開 App，避免承諾無法驗證的背景網路執行；沒有 App Groups 或推播 entitlement。
- 決定：使用官方網頁登入工作階段，避免第三方 OAuth client 冒用與手動複製 token。
- Task 1/2 共用 JSON snapshot，Task 2/3 共用工程 target 與 bundle 路徑；後續依測試驗證。

## 實作結果

- Task 1：完成。先建立介面 stub，21 項 Node 測試有 20 項失敗；補齊真實產品使用的 JS 資料層後 21/21 通過。唯一原先通過的是空結果測試，後續格式/缺欄位測試確保不掩蓋錯誤。
- Task 2：SwiftUI、WebKit、Team 選擇、冷卻/退避、個別錯誤、登入清除、前景更新、ActivityKit 卡片與 deep link 刷新已實作。11 項原生測試已在 GitHub macOS / iOS 模擬器通過。
- Task 3：7 項 Python 測試先因缺少打包功能失敗，實作後 7/7 通過。可產生只含本專案程式的 source ZIP；CI 包含模擬器測試、真機 archive、未簽署 IPA 與 SHA-256。
- 獨立 reviewer 首輪發現：到期卡片保留舊身分；非同步重啟可能發布舊快照或重複卡片。已加入身分同步失效/移除到期卡片、ActivityOperationGate、等待後重新讀取狀態及更新合併。第二輪未發現新的重要問題。
- 檢查補充：登出清除 WebKit 資料期間禁用登入，避免新登入與舊資料清除重疊。
- 未改動根目錄既有 openspec 或 vendor-review Windows 程式；build-tools 新增 GitHub CLI 與本次建置日誌。

## CI 驗證與尚待實機驗證

- 首次 CI 已成功編譯 Swift，但 Xcode 16.4 / iOS 18.5 模擬器因缺少 `libswiftWebKit.dylib` 在測試啟動前崩潰。對照 [WebKit 293831](https://bugs.webkit.org/show_bug.cgi?id=293831) 後，將 CI 固定到 runner 已提供的 Xcode 26.3 / iOS 26.2，保留 iOS 17 部署目標。

- 已上傳到使用者提供的空白公開儲存庫 lee851104/monitor。
- [第二次 CI](https://github.com/lee851104/monitor/actions/runs/38944054700) 已通過 21 項 Node、7 項 Python、11 項 native tests；Xcode 26.3 成功 archive 真機 App，產生未簽署 IPA。
- 第二次 CI 的可選截圖因測試後模擬器已關機而失敗；已在截圖前加入 bootstatus -b，重新執行以取得畫面驗證。
- Claude Team / ChatGPT 真實登入、官方用量比對、iPhone 13 卡片呈現及七天續簽，均未實測。
- 上述測試不會登入真實帳號，不能代替實機登入、側載及即時動態的驗證。
