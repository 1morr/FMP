# 06 — 文件品質（面向 E）

> 唯讀審查；證據均含 `file:line`。標 `對抗驗證` 者已覆核。成熟度評分：**3 / 5**。

## 1. 現狀摘要

- **好：** 文件分層設計本身良好——根 `AGENTS.md` 當權威邊界、子目錄 `AGENTS.md` 接力細節、`docs/` 為人類讀者地圖、`CLAUDE.md` 純 `@AGENTS.md` 不重複；`docs/README.md` 是合格文件地圖；hard boundary 有靜態測試守門（`source_ownership_phase3_test.dart`）而非僅靠文字。
- **壞：** 多處具體內容已與程式碼飄移：`pubspec.yaml` description 漏 Netease、`docs/development.md` 把 Isar collection 註冊位置寫錯、根 `AGENTS.md` 未區分兩個同名 `NeteaseSource`、`.serena/memories/update_system.md` 明顯過時且與權威規則矛盾。

## 2. 發現清單

### E1　`pubspec.yaml` description 漏掉 Netease，與專案定位及其他文件矛盾
- 嚴重度：🟡 Medium　工作量：S　動作：**rewrite**
- 證據：`pubspec.yaml:2`（`"Flutter Music Player - 跨平台音乐播放器，支持 Bilibili 和 YouTube 音源"`，未提及 Netease）；對照 `README.md:8`（副標明確「整合 Bilibili、YouTube 與網易雲音樂音源」）、`AGENTS.md:27-29`（Project Overview 列三音源）。
- 影響：`description` 是套件中繼資料的單一真實來源，會出現在 IDE 套件資訊與自動產生文件中；只寫兩源會讓新貢獻者誤以為不支援 Netease。
- 建議：`pubspec.yaml:2` 補 Netease（例：「跨平台音樂播放器，支援 Bilibili、YouTube 與網易雲音樂音源」），與 `README.md:8`/`AGENTS.md:27-29` 對齊。

### E2　`docs/development.md` 把 Isar collection 註冊位置寫成 `database_provider.dart`，實際在 `database_catalog.dart`
- 嚴重度：🟡 Medium　工作量：S　動作：**rewrite**
- 證據：`docs/development.md:69`（「以下 collection 注册在 `lib/providers/database/database_provider.dart`」）；實際 `lib/providers/database/database_catalog.dart:127-145`（`_collection<>()` 註冊並彙出 `fmpDatabaseSchemas`）；`database_provider.dart:295-298`（`openFmpDatabase()` 只 `Isar.open(fmpDatabaseSchemas,...)` 消費 catalog）；權威 `lib/data/AGENTS.md:57-59` 明定「catalog-owned」。
- 影響：新貢獻者依 development.md 改 collection 註冊會找錯檔案。
- 建議：改寫為「注册在 `database_catalog.dart`；`database_provider.dart` 只負責 open/遷移/default repair」，與 `lib/data/AGENTS.md:57-59`、`lib/providers/AGENTS.md:68-70` 對齊。

### E3　`.serena/memories/update_system.md` 多處過時且與程式碼及 AGENTS.md 矛盾，違反「記憶只放狹窄補充」政策 — 對抗驗證 **confirmed（維持 High）**
- 嚴重度：🔴 High　工作量：S　動作：**delete（或 rewrite）**
- 證據：
  - `.serena/memories/update_system.md:10-11`（列 `lib/providers/update_provider.dart` 與 `lib/ui/widgets/update_dialog.dart`——**兩檔均不存在**；真實路徑為 `lib/providers/system/update_provider.dart`、`lib/ui/widgets/dialogs/update_dialog.dart`，見 `docs/build-and-release.md:336-338`）
  - `:47-49`（描述 portable updater「生成 `fmp_updater.bat`，等待後 `xcopy` 覆蓋當前目錄」，無備份/回滾）；實際 `lib/services/update/update_service.dart:824-869`（`_buildPortableUpdaterBatch` 建立 `fmp_update_backup` 目錄、`robocopy /MIR` 備份、`robocopy /E` 覆蓋、`if errorlevel 8 goto rollback` 從備份回滾）
  - `:292-297`（Android `_platformChannel.invokeMethod('canRequestPackageInstalls')`，memory 的 Android 段未提此檢查）
  - 權威 `lib/services/AGENTS.md:55-68` 明定 portable 必須 robocopy+備份+rollback、Android 必須 `canRequestPackageInstalls`；`AGENTS.md:45-47` 明定 memories 不得重複核心規則。
- 影響：memory 會被 agent 直接採信——錯路徑導致去找不存在的檔案、xcopy 描述讓人誤以為便攜更新無回滾保護；明確違反 repo 自己訂的記憶政策。
- 建議：**刪除** `.serena/memories/update_system.md`（內容已被 `lib/services/AGENTS.md` Update System 段與 `docs/build-and-release.md` 完整且更正確地涵蓋）；若保留為狹窄筆記，先修正三個路徑與 robocopy/backup/rollback/canRequestPackageInstalls 描述並補「權威來源為 `lib/services/AGENTS.md`」。

### E4　根 `AGENTS.md` 把 `neteaseSourceProvider` 列為「NeteaseSource singleton」卻未區分兩個同名類別
- 嚴重度：🟢 Low　工作量：S　動作：**rewrite**
- 證據：`AGENTS.md:128`（Key providers 列 `neteaseSourceProvider - NeteaseSource singleton`）；實際 `lib/providers/lyrics/lyrics_provider.dart:30` 提供 `lib/services/lyrics/netease_source.dart:25` 的歌詞層 `NeteaseSource`（與 `lib/data/sources/netease_source.dart:125` 的 data source adapter **同名不同類別**）；`lib/data/sources/AGENTS.md:144-147` 明禁 runtime 消費具體 source provider。
- 影響：新貢獻者可能誤以為這就是 data source 的 Netease 單例、或試圖直接消費它，正好踩到具體 source 邊界。
- 建議：補限定詞——此 provider 對應歌詞層 `NeteaseSource`（與 data source adapter 同名但不同類別），並提醒 data source 的 `NeteaseSource` 不可被 runtime 直接消費。

### E5　`docs/development.md` 路由表遺漏 `/settings/home-ranking`
- 嚴重度：🟢 Low　工作量：S　動作：**rewrite**
- 證據：`docs/development.md:130`（設定路由表列 audio/lyrics-source/download-manager/user-guide/account/account/*-login/developer，未列 home-ranking）；實際 `lib/ui/router.dart:243`（`path: 'home-ranking'` 落在 settings 子路由）。
- 建議：路由表補 `/settings/home-ranking`。

### E6　`docs/history/refactoring-log.md` 封存註解仍把 `.serena/memories/` 稱為現行規則來源
- 嚴重度：🟢 Low　工作量：S　動作：**rewrite**
- 證據：`docs/history/refactoring-log.md:3`（封存說明寫「当前规则以 AGENTS.md 和 .serena/memories/ 中的聚焦记忆为准」，把 memories 抬升為現行規則來源）；與 `AGENTS.md:45-47`、`docs/README.md:32` 對 memories 的「狹窄補充、可能過時」定位不一致（E3 即為其過時實例）。
- 建議：改為「現行規則一律以 `AGENTS.md`（含子目錄）與 `docs/` 為準；`.serena/memories/` 僅為狹窄補充且可能過時，不視為權威」。

### E7　`AGENTS.md`（英文）與 `docs/`（簡中）語言混用且根 README/AGENTS 互指時缺「語言/讀者」標示
- 嚴重度：🟢 Low　工作量：M　動作：**merge（補說明）**
- 證據：`AGENTS.md:7-23`（英文）；`docs/development.md`、`docs/build-guide.md`、`docs/build-and-release.md`（簡中）；`README.md`（繁中）；所有子目錄 `AGENTS.md`（英文）。
- 影響：對同時讀兩層的 agent 與貢獻者造成輕度摩擦，搜尋 key term 需中英轉換。非正確性問題。
- 建議：不強制統一語言，但在 `docs/README.md` 補一行「`AGENTS.md` 系列刻意用英文以與程式碼/commit 對齊；`docs/` 與 README 面向中文讀者」使分層動機明確。

### E8　`docs/development.md` 歌詞系統概覽／資料模型表對 `LyricsMatch`/`LyricsTitleParseCache` 較 AGENTS.md 簡略且未交叉連結
- 嚴重度：🟢 Low　工作量：S　動作：**merge**
- 證據：`docs/development.md:83-84`（模型表列兩 collection 簡述）；權威 `lib/data/AGENTS.md:30-32,68-70`（標註 LyricsTitleParseCache「cleared on startup, ephemeral runtime cache」）；`lib/services/lyrics/lyrics_auto_match_service.dart:96`（預設源順序與 AGENTS 一致）。
- 影響：摘要文件可能讓人誤把 ephemeral 的 `LyricsTitleParseCache` 當耐用資料。
- 建議：development.md 該行補「（運行期暫存，啟動時清空，非耐用資料）」並交叉連結 `lib/data/AGENTS.md`。

## 3. 具體建議（add / merge / delete / rewrite 清單）

| 動作 | 對象 | 對應 |
|------|------|------|
| **rewrite** | `pubspec.yaml:2` | E1 |
| **rewrite** | `docs/development.md:69` | E2 |
| **delete**（優先） | `.serena/memories/update_system.md` | E3 |
| **rewrite** | `AGENTS.md:128` | E4 |
| **rewrite** | `docs/development.md:130` | E5 |
| **rewrite** | `docs/history/refactoring-log.md:3` | E6 |
| **merge** | `docs/README.md`（補語言/讀者說明） | E7 |
| **merge** | `docs/development.md:83-84` | E8 |

## 4. 本面向優先級 Top 3

1. **E3** — 刪除/重寫過時且違反政策的 `.serena/memories/update_system.md`（唯一 High，且會主動誤導 agent）
2. **E2** — 修正 `docs/development.md` collection 註冊位置（onboarding 直接被誤導）
3. **E1** — 修正 `pubspec.yaml` description 補 Netease（套件中繼資料單一真相）
