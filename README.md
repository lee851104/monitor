# Token Bar — iPhone 額度卡片

給 iPhone 13 的 Claude Team / Codex 訂閱額度檢視器。手機直接查詢；點鎖定畫面卡片開 App 刷新，不需要電腦持續開機。

**已通過 GitHub macOS 建置：21 項資料層、7 項打包及 11 項 iOS 原生測試，並產生未簽署 IPA。仍需透過 AltStore 簽署安裝；真實帳號登入及 iPhone 13 即時動態尚待實機檢查。**

## 功能與限制

- 顯示來源實際回傳的 5 小時、每週等額度與重置時間，Pro / Plus 不寫死窗口。
- Claude 多組織需要明確選擇 Team，切換空間會清除舊數字。
- 兩家各自登入、刷新、登出；每家顯示最後成功讀取時間。
- App 前景約每 60 秒嘗試刷新，手動刷新至少間隔 5 秒；限流依來源要求等待。
- 即時動態在 iPhone 13 鎖定畫面呈現，點擊開 App 刷新。它不是永久通知，最多運作八小時，也可能被系統提前結束。到期回 App 重新開啟。
- 卡片不能在背景每分鐘查詢。超過五分鐘或到達重置時間標為待更新，不能因倒數結束就假定額度已恢復。
- 最低 iOS 17；目標使用者裝置為 iPhone 13 / iOS 26.3.1，尚待該裝置實測。
- 不使用 App Groups、推播或共用 Keychain，降低免費側載所需權限；免費簽署保留 extension 的相容性仍須實機確認。

## 第一步：在 GitHub 免費編譯

本專案儲存庫：[lee851104/monitor](https://github.com/lee851104/monitor)。已經上傳後，直接從下方第 4 步開始。

需要 GitHub 帳號。公開 repository 可使用免費標準 macOS runner；私人 repository 有免費額度上限，請不要為本專案啟用付費超額。

1. 解壓 `TokenBar-iOS-source.zip`。裡面 `TokenBar-iOS` 是獨立的 repository 根目錄。
2. 在 GitHub 建立一個空白 repository，例如 `token-bar-ios`，不要建立 README。公開範圍由你自行決定；不要上傳任何登入 Cookie、token 或 Apple 簽署檔。
3. 將 `TokenBar-iOS` **裡面的內容**上傳至 repository 根目錄，必須包含 `.github/workflows/build-ios.yml`。不要把外層 ZIP 或整個 `D:\token_bar` 上傳。若 Windows 隱藏 `.github`，開啟檔案總管的隱藏項目顯示；也可使用 GitHub Desktop 加入解壓後的資料夾後發布。
4. 開啟 repository 的 **Actions → Build iPhone app → Run workflow**。若剛推送到 main，它也會自動啟動。
5. 必須等這次執行為綠色成功，再下載 **Artifacts → TokenBar-iPhone-unsigned**。
6. 解壓 artifact，取得 `TokenBar-unsigned.ipa`。這個檔案還沒有你的 Apple 簽名，不能直接點它安裝。

此 workflow 不需要 Apple 帳號、憑證、Claude 或 ChatGPT secret。它執行 Node 測試、Python 打包測試、iOS 模擬器原生測試，最後編譯真機版本。若建置失敗，保留 Actions 錯誤紀錄；不要把未完成產物當成可安裝版本。

來源 ZIP 會包含 GitHub 建置設定，但不含現有 Windows 專案、帳號資訊、簽署檔、Git 內部資料或 build 快取。

## 第二步：用 Windows 免費側載

依照 [AltStore 官方 Windows 安裝文件](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) 安裝 **AltServer / AltStore Classic**，不要使用網路販售的企業憑證。

1. Windows 安裝官方文件要求的 Apple 驅動／iTunes／iCloud，啟動 AltServer。
2. iPhone 用 USB 連線、解鎖並信任電腦；使用你自己的 Apple 帳號將 AltStore 安裝至手機。Apple 帳號只填在 AltServer / AltStore，不要給聊天機器人或放到 GitHub。
3. 依 iPhone 提示信任開發者，並開啟「設定 → 隱私權與安全性 → 開發者模式」（可能需要重新啟動）。
4. 將 `TokenBar-unsigned.ipa` 放到 iPhone 的「檔案」App。
5. AltStore → **My Apps → ＋** 選擇 IPA。若詢問是否移除 App Extensions，選 **保留**；移除 `TokenBarLiveActivity` 就沒有卡片。
6. 若出現 App ID／安裝數限制，請核對 [AltStore App IDs](https://faq.altstore.io/altstore-classic/app-ids)。主程式和卡片 extension 會各使用一個 App ID；不要反覆改 Bundle ID 重裝。

免費側載有三個 App 的裝置限制（包含 AltStore），以及七天簽署期限。安裝失敗不代表應該購買付費帳號；先保留錯誤訊息確認原因。

## 第三步：登入與開卡片

1. 開 Token Bar，按「連接 Claude」，在 App 內顯示的官方網站登入。完成後按「完成並查詢」。如果是公司 SSO，登入頁可能拒絕嵌入式瀏覽器；本版沒有繞過驗證的機制。
2. 如果有多個空間，選擇你要監控的 Team。對照 Claude 官方用量頁確認是你自己的限制。
3. 連接 Codex，以你的 ChatGPT 帳號登入，按「完成並查詢」。
4. 至少取得一家的數字後，按「開啟額度卡片」。如需要，去「設定 → Token Bar」允許即時動態。
5. 鎖定手機查看卡片；也請測試你在解鎖時下拉通知中心的顯示方式。iOS 決定卡片呈現位置，不能保證永久固定。
6. 點卡片會開啟 App，重新查詢兩家；確認「讀取於」時間更新後可回到原本工作。

登入 Cookie 留在本機 WebKit。程式只對官方網站 GET 組織清單、登入狀態和額度；不發送模型訊息、不兌換重置、不代付費。Codex 的 session token 只在隔離的網頁執行環境中用於官方額度請求，不返回 Swift、CI 或第三方。

**資料來源不是穩定公開 API。** Claude Team 權限、Cloudflare、SSO、ChatGPT 網頁登入格式都可能阻止讀取。若收到登入／網站驗證／權限／格式錯誤，App 會明示；不以假資料或 token 計數代替真實訂閱額度。真實帳號尚未在此開發環境驗證。

## 每七天續簽

在到期前（建議第六天）開啟 Windows 的 AltServer，讓手機與它連線，再到 AltStore → My Apps → **Refresh All**。依 [AltStore Getting Started](https://faq.altstore.io/altstore-classic/your-altstore) 確認剩餘天數已恢復。

日常查額度時電腦可以關機。Token Bar 裡的「我剛完成續簽」只記錄提醒日期，不會替 App 簽名，也不會自動知道真正的憑證到期日。

## 開發與檢查

Windows（Node 22+、Python 3.10+，無第三方套件）：

```powershell
cd D:\token_bar\ios
node --test tests/quota.test.cjs
python -m unittest discover -s tests -p 'test_*.py' -v
python scripts/package_source.py
```

macOS（Xcode、XcodeGen）：

```sh
xcodegen generate
xcodebuild test -project TokenBar.xcodeproj -scheme TokenBar \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

模擬器名稱以 `xcrun simctl list devices available` 為準。真機未簽署 archive 和 IPA 指令見 `.github/workflows/build-ios.yml`。

請依 [實機檢查表](docs/device-checklist.md) 驗證。開發紀錄在 [progress.md](docs/progress.md)。

## 資料來源參考

- [Apple 即時動態](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Apple 免費 Personal Team 限制](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [CodexBar Claude 網頁資料來源](https://github.com/steipete/CodexBar/blob/main/docs/claude.md)
- [CodexBar Codex 用量介面](https://github.com/steipete/CodexBar/blob/main/docs/codex-oauth.md)
- [GitHub 標準 runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

本專案是獨立自用工具，不隸屬 Anthropic、OpenAI 或 Apple。
