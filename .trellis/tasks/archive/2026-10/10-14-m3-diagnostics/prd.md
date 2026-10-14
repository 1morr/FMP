# 診斷包（M3b PR 15）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（implement.md §15、design §12.4、§12.3 的「匯出 log 檔」）。依據 ADR 0025 §決定 3、10（含 2026-10-08 的 `file_picker` 更正），ADR 0011 §決定 3、6，ADR 0009。

## 要做的

1. **家目錄的遮蔽**（M1 待辦 13）
   - `Redactor` 加帶替換字串的登記（例如 `registerReplacement(value, replacement)`），家目錄換成 `~`（Finamp 的已知值替換）。路徑分隔符兩種寫法都要遮（Windows 的 `\` 與 JSON 跳脫後的 `\`，以及 `/`）。
   - 在 `main()` 寫 `App started` **之前**登記，`dataDirectory` 因此在 log 檔與診斷包都是 `~\…`。家目錄在平台層讀（`AppInfo.homeDirectory` 已有；若它在 `App started` 之後才讀得到，就把讀家目錄的部分提前，或另給一個平台層的讀取函式）。Android 沒有家目錄（`null`）就不登記。
2. **組裝**（`lib/app/diagnostics/`）
   - 產生時組裝一次：版本、flavor、平台與系統版本、語系、各插件的 id／版本／啟用、各音源是否登入（是／否）、非敏感設定摘要（各設定組的欄位；`plugin_dev_folder` 只寫有無）。**不含**帳號名稱、硬體識別、歌單內容。
   - 輸出 `diagnostics.txt`（人讀的純文字）與 `diagnostics.json`；兩者來自同一份資料。整份再經一次 `Redactor`。
   - zip：`archive`（lock 已有 4.3.0，改成直接依賴，查 pub.dev 目前 stable）在 isolate 壓，內容 `diagnostics.txt`、`diagnostics.json`、目前的 log 檔（`fmp.jsonl`；輪替的舊檔一併放進去，名稱照舊）。讀 log 檔前先 flush `LogFile` 的寫入佇列。
3. **平台層**
   - `lib/platform/files/`：`FileDialogs` 加 `saveFile(name, bytes)`（`file_picker` 13.x 的 `saveFile(bytes:)`；桌面是存檔對話框、Android 走 SAF），使用者取消回 `null`。
   - `lib/platform/share/`：`share_plus`（design 寫 13.3.1，查 pub.dev 目前 stable，用最新 stable 並回報），`shareFiles(paths)`；`PlatformCapabilities.shareFiles`（Android、Windows 真；Windows 的最低版本照 share_plus 文件，實機確認）。`share_plus` 只准在 `lib/platform/`（lint `fmp_layer_imports`，注意它以套件家族前綴比對，`share_plus_*` 也算）。
4. **UI**
   - Debug 頁「概覽」的診斷包：「複製」（純文字摘要進剪貼簿）、「存檔」（`fmp-diagnostics-<時間>.zip`，檔名不含冒號）、「分享」（只在 `shareFiles` 為真的平台顯示）。
   - 第一次匯出（存檔或分享）先跳「送出前請檢查」提醒，與 GitHub 回報**共用** `report_reminder_dismissed`（沿用 PR 13 的對話框與 setter）。
   - Log 區塊加「匯出 log 檔」：走同一個存檔／分享管道，zip 內只有 log 檔（`fmp-logs-<時間>.zip`）。
5. **暫存**：分享用的 zip 寫在快取目錄的固定子目錄，分享結束後刪；殘留的由啟動維護清單（`lib/app/startup_maintenance.dart`）的新項目「診斷包暫存」刪掉。
6. i18n 三個語言（slang）；`app/AGENTS.md`（家目錄遮蔽、診斷包、分享、暫存各寫出閘門）、`.trellis/spec/app/{platform,logging,ui}/index.md` 視需要。

## 驗收（測試）

- ADR 0011 的遮蔽測試加四種：診斷包（txt、json、zip 裡的 log）不含假憑證、假簽名網址、帳號名稱（假的顯示名稱）、家目錄的使用者名稱（假的家目錄，例如 `C:\Users\FAKE_USER`）。
- 家目錄替換：`App started` 的 `dataDirectory` 寫成 `~\…`（以測試組 `main` 的那段或抽出的函式驗）；`\`、`\`、`/` 三種寫法都換掉；短於下限或空的家目錄不登記（避免把一般文字切碎）。
- zip 可以解開、三類檔案都在、檔名正確；壓縮在 isolate（以測試確認呼叫路徑即可）。
- 未宣告 `shareFiles` 的平台不顯示「分享」（widget）。
- 存檔取消時不提示成功、不留暫存；第一次匯出跳提醒、「不再提醒」與 GitHub 回報共用。
- 啟動維護清單刪掉殘留的暫存 zip，不碰別的檔。
- 「匯出 log 檔」的 zip 只有 log 檔。
- guideline：概覽的診斷包區與提醒對話框寬 1000、窄 400，淺色深色。
- 每個新閘門雙向變異驗證並回報。
- 驗證清單：`dart format`、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`；lint 改了就跑 `packages/fmp_lints` 的 `dart test` 與 `dart run tool/lint_sentinel.dart`；`flutter build windows --flavor dev --debug`。

## 實機（主對話做）

- 動到 `lib/platform/` 與原生依賴：Android 模擬器與 Windows 都驗。
- Windows：存檔 → 以 `Expand-Archive` 打開，三類檔都在，`dataDirectory` 是 `~\…`，內容沒有使用者名稱；分享開出系統分享視窗（不實際送出）。
- Android：分享到檔案 App 一次（或存檔走 SAF），打開 zip 確認內容。

## 不做

- GitHub 回報附檔（ADR 0023：內容不進網址，使用者自己貼）。
- 健康檢查與插件開發工具（PR 16）。
