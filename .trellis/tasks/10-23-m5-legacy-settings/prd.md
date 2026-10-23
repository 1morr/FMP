# 設定的轉換

## 目標

M5 PR 5（上層 `implement.md` § 5；design §5.9、§1.3、§9「轉換器」）：轉換器加設定段，把舊 `Settings` 裡新版有落腳處的值轉成 `ImportBundle` 的設定組、`source_settings.browse_as_logged_in` 與 `layout_state`；沒有落腳處、但使用者改過的舊設定列進摘要的「不匯入的設定」。

範圍、做法都已由擁有者核准（2026-10-23，design §11 第 2、5 條）。計畫沒涵蓋、會改變行為、範圍或對外介面的決定，停下回報，不自行拍板。

## 現況（以程式碼為準）

- `lib/legacy_import/legacy_snapshot.dart`（PR 1）：`LegacySettings`，建構子預設等於舊版欄位的初始值；讀取器已在 `schemaVersion < 4` 時補做舊 migration 與 `repairSettingsInvariants`。缺欄時是 Isar 型別預設（`minLong`、NaN、false）。轉換器不改這個物件。
- `lib/legacy_import/legacy_converter.dart`（PR 3）：分段轉換，設定段還沒有；`play_history_limit.dart` 已有播放歷史上限的換算（PR 3），沿用。
- `lib/data/import/import_bundle.dart`（PR 2）：`appearance`、`network`、`playback`（既有的設定值型別，欄位空＝不寫）、`browseAsLoggedIn: Map<String, bool>`、`layout`；`ImportSummary.unimportedSettings: List<String>`。
- 新版各設定的選項與預設在 `lib/settings/`；舊版的預設在舊專案 `lib/data/models/settings.dart`（凍結，只讀）。
- 上層 `implement.md`「留下的後續」：`network.cacheLimitMebibytes` 一律留空（ADR 0016 §決定 3）。

## 需求

1. **通則**（design §5.9）：
   - 只寫使用者在舊版改過的值（不等於舊版預設）；等於舊預設、或不在合法值域（型別預設、`minLong`、NaN、不認得的字串）的，新版欄位留空。
   - 不在新版選項裡的值取最接近的選項（等距取大的）；播放歷史上限照 PR 3 的換算。
   - 舊預設以舊專案 `Settings` 的欄位初始值為準，在測試裡註明來源檔。
2. **對照表**：照 design §5.9 的表逐列實作（主題、語言、音質、格式優先、記住位置、兩個倒帶秒數、歷史上限、自動捲到目前曲目、Windows 的輸出裝置、電台與排行的刷新間隔、`useAuthForPlay` → `browse_as_logged_in`、詳細面板展開與寬度）。
   - `browse_as_logged_in` 例外：三個音源都照舊值寫（舊預設與新預設不同，design §5.9 最後一段）；舊版 v3→v4 強制打開的 B 站值照現值。
   - 輸出裝置只在 Windows 匯入（以平台判斷由呼叫端給，轉換器保持純函式）。
   - `layout_state` 只在資料庫來源寫（`source == database`），面板寬度夾在 ≤ 1600。
3. **不匯入的設定**（design §1.3）：主色、字型、每音源串流優先、快取上限、首頁排行的順序與停用、側欄展開、搜尋歷史——**只有使用者改過的才列**進 `summary.unimportedSettings`（穩定的英文識別字，PR 6 的結果對話框以它查翻譯）。快取上限的 `cacheLimitMebibytes` 斷言為空。
4. **測試**：每一列對照各一例（改過的值、等於舊預設、型別預設、不在選項內取最接近）、`browse_as_logged_in` 三個音源、輸出裝置只在 Windows、版面只在資料庫來源、不匯入清單只列改過的。另外：PR 1 的合成舊庫（設定改過幾項）→ 讀取器 → 轉換器 → `StagingImport.write`＋`verify` 通過，讀回的設定等於期望。
5. **文件**：`app/AGENTS.md` § 舊資料匯入加「設定只寫改過的值」與它的閘門。

## 不做

帳號與憑證（PR 4，與本 PR 平行，同樣改 `legacy_converter.dart`：只加自己的段落，不動其他段）、M6–M8 的設定（下載、歌詞、AI、桌面）、UI。

## 驗收

- 測試全綠；`dart run build_runner build --delete-conflicting-outputs` 後沒有實質變動、`dart format --output=none --set-exit-if-changed lib test tool`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`。
- 回報：改了哪些檔、每個舊設定的舊預設與來源行號、計畫沒涵蓋而做了判斷的地方。
