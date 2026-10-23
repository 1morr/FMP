# M5 驗收紀錄

2026-10-23，`main` @ 9da89414（PR 0–7 全部合併後）。主對話執行，擁有者授權讀取使用者資料夾（「如有需要可以直接從用戶文件夾中獲取」）並委託主對話驗收（決定 6）。本檔只記筆數與結果，不記歌單名稱、曲目、帳號名稱或 cookie。

## 1. 真實資料副本完整匯入（design §8.2）

### 做法

- 把擁有者的舊資料庫（`Documents\FMP\fmp_database.isar`，5 MB）與舊憑證檔（`%APPDATA%\com.personal\fmp\flutter_secure_storage.dat`）複製到 `<暫存目錄>/legacy-real/`；複製前記下兩個原檔的雜湊與修改時間。
- 以同一份副本的另一份複本跑 `tool/legacy_counts.dart`，得到基準筆數（與規劃時 `isar-copy-spike.md` 相同）。
- **Windows**：主 checkout 建 dev（`flutter build windows --flavor dev --debug`）；原有的 `userdata-dev` 備份到 `<暫存目錄>` 後清空；以 `--fmp-legacy-dir=<暫存目錄>/legacy-real` 啟動。
- **Android 模擬器**（Medium_Phone，`-no-audio`，只動 `com.personal.fmp.dev`）：`pm clear` 後把資料庫副本推進 dev 的 `files/legacy-copy/`，帶參數啟動。dev 讀不到 prod 的沙盒，不讀憑證（design §8.2）。
- 匯入後以唯讀方式讀新資料庫的筆數與 `legacy_imports.summary_json`。

### 筆數

| 舊 collection | 基準（`legacy_counts`） | 匯入摘要：讀到 → 寫入 | 新表的列數（Windows） | 說明 |
|---|---:|---|---:|---|
| Track | 1195 | tracks 1210 → 1210 | tracks 1210 | 1195 首加上播放歷史快照補出的 15 首（`Track` 裡沒有的鍵）；單 P 去 cid 後沒有重複 |
| Playlist | 1 | 1 → 1 | playlists 1（`imported`）、playlist_remote 1、legacy_playlist_ids 1 | 唯一的 B 站收藏夾認得出網址 |
| （歌單項目） | — | 1195 → 1195 | playlist_entries 1195 | |
| PlayQueue | 1 | queue 1195 → 1195 | queue_entries 1195、player_state 1 | 隨機、循環全部、播放位置照舊 |
| PlayHistory | 443 | 443 → 443 | play_history 443 | |
| RadioStation | 0 | 0 → 0 | radio_stations 0 | |
| Account | 2 | 2 → 2 | accounts 2（`active`） | Windows；Android 0（不讀憑證，見下） |
| Settings | 1 | — | source_settings 3 | 沒有匯入的設定：搜尋歷史（`unimportedSettings: [searchHistory]`） |
| SearchHistory | 2 | 不匯入 | — | design §11 第 3 條；#309 |
| DownloadTask、LyricsMatch | 1、1 | 不匯入 | — | 留給 M6、M7（design §1.2） |

- 每個 collection 都是「讀到＝寫入」，沒有略過，也沒有註記（`skipped`、`notes` 皆空）。
- `PRAGMA integrity_check` = ok，`foreign_key_check` 沒有列（兩平台）。
- **Android** 的筆數與 Windows 相同；差別只在帳號：0 列，`reloginPlatforms = [bilibili, netease]`（dev 的 Android 不讀舊憑證，舊帳號列是登入中，所以列為需要重新登入；PR 4 的規則）。

### 憑證與登入（Windows，真實連線）

- 舊憑證：bilibili `found`、youtube `missing`、netease `found`（真的以 DPAPI 解開）；`failedCredentials: []`，沒有需要重新登入的平台。
- 結果對話框：歌單 1、曲目 1210、播放歷史 443、電台 0、帳號 2、沒有匯入的設定「搜尋歷史」、「安裝音源」提示。
- 從首次引導只安裝 bilibili 1.10.0、netease 1.7.0（安裝確認框列出兩個插件與網域）。
- 確認登入：設定 › 帳號，兩個帳號都顯示「歌單」「登出」；各開一次帳號的歌單頁，都列出歌單、沒有登入或錯誤提示。
- **真實請求**（以 log 的網路紀錄統計，共 58 次）：
  - 不帶憑證：GitHub 官方 index 與插件檔 13 次；排行榜與歌單頁的封面 34 次（hdslb、music.126.net；其中 1 次網路錯誤）。
  - 帶憑證（`credentials` 皆為真），排行榜（首頁一裝好插件就自動載入）：bilibili `x/web-interface/nav` ×2、`wbi/view`、`ranking/v2`；netease `api/v6/playlist/detail`、`api/v3/song/detail`。全部 200。
  - 帶憑證，確認登入：bilibili `x/v3/fav/folder/created/list` ×2；netease `api/nuser/account/get`（第一次 NetworkError、重試 200）、`api/linux/forward`（使用者歌單）。全部 200。
  - 原定 2 個帶憑證的請求，實際 11 次（10 個請求，其中 1 個網路錯誤後重試）：排行榜在裝好插件時就自動載入（既有行為），歌單頁每個平台也不只一個請求。沒有寫入操作。
- B 站的 refresh token（design §8.2、§11 第 10 條，擁有者已接受）：這次沒有觸發刷新（`refresh: onStartup` 在下次啟動時才跑）。dev 下次啟動若換了 cookie，舊版的 B 站會被登出一次。

### 原檔與副本

- 驗收後兩個原檔的雜湊與修改時間都與複製前相同。
- `<暫存目錄>` 的副本（`legacy-real/`、計數用的複本、Android 抽出的資料庫）都已刪除；模擬器的 dev 資料已 `pm clear`。

## 2. 兩平台端到端

| 項目 | Windows | Android 模擬器 |
|---|---|---|
| 首次啟動匯入、結果對話框、「知道了」後不再出現 | 真實資料副本（本檔 §1）；合成資料（PR 6） | 真實資料副本（本檔 §1）；合成資料（PR 6，主對話） |
| 「安裝音源」開首次引導 | 真實資料副本（本檔 §1） | PR 6 看到按鈕；沒有點 |
| 失敗頁三個按鈕 | PR 6（壞檔；重試、匯出診斷、以空白資料啟動） | PR 6（壞檔的失敗頁、以空白資料啟動） |
| 設定頁「從舊版匯入…」舊版資料庫 | PR 7（合成資料：本機歌單被換掉、插件保留、自動備份與 `before-import-` 檔、重啟後結果對話框） | 沒驗：dev 的「找得到舊資料庫」要帶參數重開，與首次啟動同一條讀取與轉換；換上的部分由 JSON 那次涵蓋 |
| 設定頁「從舊版匯入…」舊版備份檔 | PR 7（佇列清空、主題照備份） | PR 7（經系統檔案選擇器；手動重開後結果對話框） |

細節在各 PR 的描述（#316、#317）與 `implement.md`「留下的後續」。

## 3. 測試（ADR 0010 §如何確認、design §9）

| 項目 | 測試 |
|---|---|
| 舊 schema 凍結 | `test/legacy_import/legacy_schema_test.dart` |
| 讀取器不寫舊檔、沒有設定列就失敗 | `test/legacy_import/legacy_database_reader_test.dart` |
| 舊 migration 補做 | `test/legacy_import/legacy_settings_migration_test.dart` |
| 轉換器的對照（曲目、歌單、網址、佇列、歷史、電台、外部來源、帳號、設定） | `test/legacy_import/legacy_converter_test.dart`、`remote_playlist_url_test.dart`、`legacy_account_converter_test.dart`、`legacy_settings_converter_test.dart`、`play_history_limit_test.dart`；端到端 `legacy_converter_import_test.dart` |
| 暫存庫驗證失敗時不換上、刪暫存 | `test/data/import/staging_import_test.dart` |
| 首次啟動中途失敗不留半套資料 | `test/app/first_launch_import_test.dart` |
| 設定頁的取代保留插件與登入、表的歸類閘門 | `test/data/import/staging_import_replace_test.dart`、`test/data/database/database_backups_test.dart` |
| 舊 JSON 備份 | `test/legacy_import/legacy_backup_reader_test.dart` |
| 舊憑證（Windows 唯讀、Android 選項） | `test/platform/legacy_credential_reader_test.dart`；`integration_test/legacy_credentials_test.dart`（CI Windows） |
| 憑證往返 | `test/legacy_import/legacy_credentials_roundtrip_test.dart` |
| `lib/legacy_import/` 只被 `lib/main.dart` 引用 | `packages/fmp_lints/test/rules/layer_imports_test.dart`、`tool/lint_sentinel.dart` |
| prod 不讀 `--fmp-legacy-dir`、真實舊位置被拒 | `test/platform/legacy_data_locator_test.dart` |

## 4. 擁有者日常試用

- Windows 的 dev 資料留在主 checkout 的 `app/build/windows/x64/dev/runner/Debug/userdata-dev/`（以 dev 的 `fmp.exe` 啟動即可；不要再帶 `--fmp-legacy-dir`，已有 `fmp.db` 也不會重新匯入）。已安裝 bilibili、netease，兩個帳號是登入狀態。
- 原本的 `userdata-dev`（M4 測試留下的）備份在 `<暫存目錄>/userdata-dev-backup-accept/`；dev 的 secure storage 裡 bilibili、netease 的憑證已被匯入的舊憑證取代。
- 清建置目錄（`flutter clean`）會一併刪掉這份資料；要長期試用，先把 `userdata-dev` 複製到別處。

## 5. 驗收時發現的

- #318：裝完插件的第一輪封面因允許網域未更新而失敗（18 筆 `Host not allowed: i0.hdslb.com`，同一秒；之後同網域都成功）。與匯入無關。
- 原定「每個平台一次請求」不夠精確：裝好插件時首頁的排行榜會帶憑證自動載入（`browse_as_logged_in` 照舊值為開）。
