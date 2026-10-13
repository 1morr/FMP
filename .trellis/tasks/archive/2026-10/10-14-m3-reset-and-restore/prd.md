# 備份、從備份還原、重設資料與重啟（M3b PR 14b）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（implement.md §14、design §12.2）。依據 ADR 0025 §決定 8、9，ADR 0010，ADR 0012。PR 14a（#240）已做唯讀的資料庫瀏覽與檢查。

## 已確認的事實（主對話在 Android 模擬器上實測，2026-10-14）

暫停播放（media session 還在）時按返回鍵回到桌面：行程還活著（pid 不變）。再開 App，Android 只把原本的 task 帶回前景（`am start` 回 "Activity not started, its current task has been brought to the front"），log 的 `App started` 筆數沒增加，**`main()` 沒重跑**。所以 Android 不能只靠 `SystemNavigator.pop`（design §12.2 預先標出的風險成立）。

## 要做的

1. **備份**（`lib/data/`）：`VACUUM INTO` 把資料庫複製到資料目錄的 `backups/fmp-<UTC 時間>.db`（檔名用不含冒號的時間格式，Windows 檔名不准冒號）。回傳檔案路徑。`backups/` 不存在就建立。列出備份：時間、大小，最新的在前。
2. **從備份還原**：列出 `backups/` → 選一個 → 確認對話框 → 關閉資料庫 → 原本的 `fmp.db` 改名留著（例如 `fmp.db.before-restore-<時間>`）→ 以備份檔複製成 `fmp.db` → 重啟。
3. **重設資料**（ADR 0025 §決定 9，順序固定）：
   1. 備份；**備份失敗就停下、什麼都不清**，顯示錯誤。
   2. 對話框列出備份路徑（家目錄以 `~` 顯示，沿用 PR 11 的 `homeRelativePath`），二次確認（例如要再按一次或勾選確認）。Android 的對話框寫明清空後 App 會關閉、要手動重開。
   3. 清空：`SecureStorage.deleteAll()`、登入 WebView 的 `clearAll()`（平台沒有 WebView 就略過）、快取（`CacheStore.clear()`）、資料庫（關閉後刪檔；下次啟動重建）。**不動** log 檔、`backups/`。
   4. 重啟。
4. **重啟**（平台層 `lib/platform/app_restart/`，`AppRestarter.restart()`；`PlatformCapabilities` 加 `restartsItself`：Windows 真，Android 假）
   - **Windows**：以 `Platform.resolvedExecutable` 啟動新行程（detached，參數帶 `--fmp-restarted-from=<目前 pid>`，**不**沿用原本的命令列參數），接著結束目前行程。`windows/runner/main.cpp`：命令列有 `--fmp-restarted-from=<pid>` 時，先 `OpenProcess(SYNCHRONIZE, …)` 等那個行程結束（最多 10 秒），再建立單一實例的 mutex。Dart 端的參數解析要忽略這個參數。
   - **Android**：先停掉 audio_service（結束前景服務與 media session，用 `lib/platform/media_controls/` 既有的入口；沒有就在那裡加），再結束行程（`exit(0)`）。使用者重開時 `main()` 會重跑。
   - 結束行程前先把 log 檔的寫入佇列 flush 掉。
   - 為什麼不能只靠 `SystemNavigator.pop`，寫進 `app/AGENTS.md`（引用上面的實測）。
5. **UI**
   - Debug 頁「重設資料」區塊（ADR 0025 §決定 2 的表，最後一個）：說明範圍（清什麼、不動什麼）、「重設資料」按鈕。
   - 「資料庫」區塊加「從備份還原」（備份清單）與「立即備份」；「檢查」有問題時顯示「從備份還原」「重設資料」兩個按鈕（後者跳到重設區塊或開同一個流程）。
   - i18n 三個語言（slang）。
6. 文件：`app/AGENTS.md`（備份與還原、重設、重啟各一條，寫出閘門）、`.trellis/spec/app/{data,platform,ui}/index.md` 視需要。

## 驗收（測試）

- 備份：`VACUUM INTO` 的檔可以開啟，各表筆數與原資料庫相同；檔名沒有冒號。
- 重設：備份失敗時**不清空**（資料庫、secure storage、快取都還在）；成功時資料庫是空的（重新開啟後只有預設資料）、`SecureStorage` 為空、WebView `clearAll` 被呼叫、log 檔還在、`backups/` 還在；之後 `CredentialStore` 為空且請求不帶憑證（ADR 0012 §如何確認的「重設所有資料」）。
- 還原：還原後的資料等於備份；原檔改名留著。
- 重啟：Windows 以正確的參數啟動新行程後結束（以假的 process launcher 測）；Android 先停 audio_service 再結束（以假的實作測呼叫順序）；結束前 log 已 flush。
- `main.cpp` 的等待：至少以 Windows 實機驗（C++ 沒有單元測試框架時寫明沒有自動閘門）。
- widget：二次確認（第一次按不會清）、取消不清、備份失敗顯示錯誤且不清、Android 的對話框有「手動重開」說明、檢查有問題時出現兩個按鈕。
- guideline：新區塊與對話框寬 1000、窄 400，淺色深色。
- 每個新閘門雙向變異驗證並回報。
- 驗證清單：`dart format`、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`；動到 lint 時跑 lint 的測試與 sentinel；`flutter build windows --flavor dev --debug` 能建置。

## 實機（主對話做）

- 動到 `windows/` 與 `lib/platform/`：Android 模擬器與 Windows 都驗。
- 兩平台：重設資料（先備份）→ 重開後是空的、log 出現新的 `App started` → 從備份還原 → 資料回來、要重新登入。Android 確認重開時 `main()` 重跑、通知列的媒體控制消失。

## 不做

- 自動修復損壞的資料庫（ADR 0025 否決）。
- M4 的匯出格式（E16）。
- Android 自動重啟自己（design：手動重開）。
