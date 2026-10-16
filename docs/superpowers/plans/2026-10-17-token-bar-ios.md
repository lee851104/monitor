# Token Bar iPhone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立可免費側載、手機直接查詢 Claude/ Codex 額度的 iPhone App 與即時動態。
**Architecture:** SwiftUI 主程式管理兩個 WebKit 官方登入工作階段；同一份 JavaScript 程式處理唯讀網頁請求和資料驗證。量測透過 ActivityKit 傳給 extension，不依賴 App Group 或電腦常駐。
**Tech Stack:** Swift 5、iOS 17+、WebKit、ActivityKit、Node 原生 test、XcodeGen、GitHub Actions。
**Spec:** ../../design.md（實際檔案：ios/docs/design.md）

## Global Constraints

- 只做官方服務唯讀額度查詢；不呼叫模型、不消耗重置券、不匯出憑證。
- 介面與操作文件用繁體中文。
- 每個服務各自保留更新時間與錯誤，缺少資料不能視為零用量。
- 免費簽署不使用 App Groups、推播或共用 Keychain。
- 不將未驗證的 iOS 建置、登入或通知卡片描述為已成功。

## Review Focus

- 多 Claude 組織須選擇，切換不能沿用舊組織量測。
- Pro 缺少五小時欄位時不補假資料，週窗口須按時長命名。
- 401、403、429、HTML challenge 與離線的區分、舊時間保留。
- WebKit 導航離開官方 origin 時禁止執行資料請求。
- 打包必須含主程式、extension、JS 資源，不能放入個資或既有 Windows 專案。

### Task 1: 可測試的唯讀資料層
**Files:** App/Resources/quota-core.js, tests/quota.test.cjs, package.json
**Interfaces:** `QuotaCore.parseClaude/parseCodex(payload, timestamp)`, `QuotaCore.collect(provider, organization, environment)`，回傳可 JSON 編碼的結果與白名單錯誤。
- [ ] 寫測試：零值、缺少窗口、週窗口為 primary、畸形數字、重置時間、多組織、錯誤狀態、origin 防護。
- [ ] `node --test tests/*.test.cjs` 確認缺少功能失敗。
- [ ] 實作解析與 GET 查詢；只傳出量測與組織名稱，不傳出 session/token。
- [ ] 執行資料層全套測試。

### Task 2: 手機 App 與即時動態
**Files:** App/*.swift, Shared/*.swift, Widget/*.swift, NativeTests/*.swift, project.yml
**Interfaces:** `ProviderSnapshot` 與 `QuotaActivityAttributes.ContentState` 在 app/extension 共享編譯；不共享檔案或憑證。
- [ ] 寫 Swift 測試確認快照解碼、卡片刷新過期與隱私邊界；由 macOS workflow 執行。
- [ ] 實作官方登入 WebKit、組織選擇、個別刷新/登出、冷卻、前景刷新和全域連結刷新。
- [ ] 實作緊湊卡片、重置資訊與過期/錯誤提示，開始/停止活動。
- [ ] 準備模擬器測試與真機編譯指令，列出本機無 Apple SDK 的驗證限制。

### Task 3: Windows 交付與驗證
**Files:** .github/workflows/build-ios.yml, scripts/package_ipa.py, scripts/package_source.py, scripts/prepare-source.ps1, README.md, docs/device-checklist.md
- [ ] 先寫打包工具測試，缺少 App/extension/resource 時必須失敗。
- [ ] 實作無憑證的未簽署 IPA 打包與可上傳原始碼 ZIP。
- [ ] CI 執行 Node 測試、模擬器測試、真機建置並上傳產物；未提供 GitHub 帳號授權前不代為發布。
- [ ] 跑全套 Windows 可執行測試與產物檢查，請獨立 reviewer 檢查。
- [ ] 更新完成紀錄，交付原始碼產物和具體安裝步驟；缺少 iOS 編譯或實機結果要明說。
