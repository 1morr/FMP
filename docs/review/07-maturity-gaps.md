# 07 — 其他成熟度缺口（面向 F，業界水準必檢）

> 唯讀審查；證據均含 `file:line`。標 `對抗驗證` 者已覆核。成熟度評分：**3 / 5**。

## 1. 現狀摘要

- **好：** CI 有 analyze+test+雙平台 build smoke，release 流程含簽章、checksum manifest、versionCode from tag；安全邊界（URL/SSRF 政策、hotkey 修飾鍵驗證、帳號標頭不送到 CDN byte、logger 脫敏）皆有實作且大部分有測試覆蓋。
- **壞：** 依賴鎖在 Isar 3.x（上游低活躍，需追蹤）；CI 未收集 coverage、缺 integration/golden/scenario 測試；backup import 對外部 JSON 採嚴格 `DateTime.parse`；部分關鍵安全測試僅用 static-rule 字串比對而非真正行為驗證。

## 2. 發現清單

### F1　依賴 Isar 3.1.0+1 — 對抗驗證 **partially，High→Medium（核心主張更正）**
- 嚴重度：🟡 Medium　工作量：L
- 證據：`pubspec.lock:728-751`（`isar`/`isar_flutter_libs`/`isar_generator` 皆解析為 `3.1.0+1`）；`pubspec.yaml:22-23,96`（直接依賴 `isar ^3.1.0+1`、`isar_flutter_libs ^3.1.0+1`、dev `isar_generator ^3.1.0+1`）；全庫無任何 AGENTS.md/docs 註記 Isar 為凍結狀態。
- **驗證更正（重要）：** 原發現稱「Isar 3.x 上游已 archived / EOL」**與事實不符**——`github.com/isar/isar` 並非 archived，官方 README 明確標示「ISAR V4 IS NOT READY FOR PRODUCTION USE ... please use the v3 stable version」。亦即**堅守 v3 正是上游官方建議的生產路徑**，並非偏離行為；v4 目前無 stable、且官方明說不適合生產、且缺乏 v3→v4 遷移工具，「遷移至 Isar 4」現階段不可行。
- 影響：真正的風險是「長期、中低度」——v3 維護低活躍（社群公認 recently unmaintained），未來若遇 Flutter/NDK/arm64-Win 架構變遷，native libs 可能無人補丁；但**目前無任何實際崩壞，且不存在可走的升級路徑**。
- 建議：短期至少在 AGENTS.md 註記此依賴為「凍結狀態，堅守 v3 符合上游官方建議」並追蹤上游動態；release 前確認目標平台 native libs 可用；「遷移 Isar 4」改為「待 v4 stable 且提供遷移工具後再評估」。可考慮評估替代（drift/sqflite/objectbox）作為長期選項。

### F2　CI 不收集測試覆蓋率，無法量化回歸與關鍵路徑覆蓋
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`.github/workflows/ci.yml:1-95`（validate job 只跑 `flutter analyze` + `flutter test`，未加 `--coverage`、未產生 lcov、未上傳 codecov/coveralls）；`test/performance/startup_benchmark_test.dart`（有效能基準但無覆蓋率量化）。
- 影響：無法量化覆蓋率，新增程式碼可能長期無測試而不自知，回歸風險隨程式碼增長上升（最大檔 `audio_provider.dart` 3411 行）。
- 建議：CI 改 `flutter test --coverage` 並上傳 coverage 報告（codecov 或 artifact），PR 顯示 diff 覆蓋率；對 `audio_provider`/`download_service`/`youtube_source` 等大檔設定最低覆蓋閘門。

### F3　缺 integration / golden / 端到端 scenario 測試，關鍵播放恢復與下載鏈僅單元覆蓋
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`test/scenarios/offline_scenarios_test.dart:11-40`（唯一 scenario 測試只驗 `ErrorHandler.wrap` 對 `DioException` 分類，不涉及真實音訊/下載/匯入）；`.github/workflows/ci.yml`（無 golden、無 integration、無 emulator）；`test/services/audio/playback_recovery_coordinator_test.dart`（recovery 有單元測試，但無 end-to-end：串流失敗→重試→換來源→播放整鏈未演練）。
- 影響：跨元件整合缺陷（`AudioController`↔`StreamResolutionService`↔`MediaHandoff` 互動）易於改版後回歸而無測試捕捉。
- 建議：新增 integration 測試——fake 後端模擬串流失敗→驗證 `PlaybackRecoveryCoordinator` 完整重試與換源；download→isolate→complete→DB transaction 端到端 scenario；評估關鍵頁面加 golden 防視覺回歸。

### F4　Backup import 對外部 JSON 採嚴格 `DateTime.parse` / `as String` 轉型，缺結構化錯誤回報
- 嚴重度：🟡 Medium　工作量：S　[未個別驗證]
- 證據：`lib/services/backup/backup_data.dart:57`（`exportedAt: DateTime.parse(json['exportedAt'] as String)`——無 `tryParse`，格式異常即 `FormatException`）；`:200-215`（`PlaylistBackup.fromJson` 用 `name: json['name'] as String` 非可空強轉、`DateTime.parse(lastRefreshed)`）。
- 影響：使用者匯入損壞或非本應用產生的備份檔時，會在還原中段拋未預期例外，可能已部分寫入 DB 後失敗留下不一致狀態。
- 建議：備份還原改兩階段——先全檔寬容解析（`DateTime.tryParse`、欄位缺失給預設/跳過、收集錯誤清單），全部通過後再批次寫入；或以 transaction 包裹並驗證整體後才 commit，UI 回報具體失敗欄位。

### F5　Source policy / radio 的安全測試多為 static-rule 字串比對，未驗證實際 HTTP 行為
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`test/services/radio/radio_source_http_policy_usage_test.dart:7-32`（以 `readAsStringSync` 讀原始碼後 `contains`/`isNot(contains)` 比對字串，而非實際呼叫 live client 驗證標頭）；`test/data/sources/source_http_policy_usage_test.dart`（同類 static-rule 比對，確保程式碼「沒寫死 Referer 字串」，但未驗證 `mediaHeaders` 在真實請求的輸出）。
- 影響：重構字串寫法（如改用常數組合）即可繞過斷言，使「帳號憑證不進 CDN byte 請求」這條硬邊界形同虛設，安全回歸不被測試捕捉。
- 建議：針對 `SourceHttpPolicy.mediaHeaders` 與 `media_handoff._prepareHeaders` 補真實單元測試——給定 netease CDN URL 時斷言輸出 headers 不含 Cookie/Authorization；此為行為測試，重構不會誤判也不漏判。

### F6　更新資產 SHA256 在 manifest 缺漏時為選用，未強制為必要失敗
- 嚴重度：🟡 Medium　工作量：S　[未個別驗證]
- 證據：`lib/services/update/update_service.dart:463-486`（`checksumManifestAvailable` 為 bool，`checksumUrl==null` 時 `assetSha256s` 為空 map，`selectedAsset` 仍可選用）；`:106,143-149`（`assetSha256` 為 `String?` 可 null，`UpdateInfo` 允許無 checksum 的資產）。
- 影響：若 GitHub release 的 `checksums.sha256` 缺漏或被刪，更新流程可能退化為不驗 checksum 即安裝 APK/exe，繞過供應鏈完整性保護。
- 建議：明確政策——release 資產若對應 checksum 缺失則視為更新不可用（return null 或拋錯），UI 顯示原因；下載完成後安裝前**必須** sha256 比對通過才放行，缺 hash 一律拒絕。

### F7　logger 在 release 模式仍以 `debugPrint` 全量輸出至主控台並保留原始 stackTrace
- 嚴重度：🟢 Low　工作量：S　[未個別驗證]
- 證據：`lib/core/logger.dart:55-62,221-232`（release 仍 `debugPrint(fullMessage)` 到 console，`LogEntry` 含原始 `stackTrace`，落到行動 logcat/桌面事件日誌）；`lib/ui/pages/settings/log_viewer_page.dart`（log viewer 供使用者查看，未見對 release 是否含敏感資料的審視）。
- 影響：release 裝置上可能留存含來源 URL/請求脈絡的訊息（cookie/token 已脫敏，但 redact 清單外的 query 參數、軌跡資料未脫敏）。
- 建議：release 將最小級別提到 info、關閉 `debugPrint`（或改寫檔案且僅本機）、評估緩衝在 release 縮減；審視未涵蓋的敏感欄位（如 AI apiKey、netease eparams）是否加入 redact 清單。

### F8　Windows 發布以多段正規取代 patch 生成的 ISS 腳本，脆弱且難追蹤
- 嚴重度：🟢 Low　工作量：M　[未個別驗證]
- 證據：`.github/workflows/release.yml:220-280`（Windows 用 `inno_bundle` 生成 ISS 後以 PowerShell 正規取代多處——移除 icelandic、補 DefaultGroupName、改 AppUserModelID、改 postinstall flags）；`:258-268`（以字串替換固定路徑條目，若 `inno_bundle` 改版改變輸出格式，補丁會靜默失效）。
- 影響：打包正確性依賴對 `inno_bundle` 特定輸出格式的字串假設；上游改版或翻譯變動時，正規取代可能不再命中，導致安裝時 AppUserModelID/群組設定無聲失效（影響 SMTC/工作列識別）。
- 建議：將 InnoSetup 需求以自維護的 `.iss` 模板取代對生成輸出的後處理補丁；或在 CI 增加斷言步驟，編譯後檢查 ISS/輸出含預期 AppUserModelID 與 DefaultGroupName，補丁未命中即 fail。

## 3. 具體建議（可驗收）

1. **測試覆蓋可視化（F2 + F3）：** CI 加 `--coverage` 並上傳；新增 1 條 integration 測試覆蓋「串流失敗→重試→換源」整鏈。驗收：PR 可見 diff 覆蓋率；播放恢復整鏈有自動化演練。
2. **安全測試行為化（F5）：** 補 `SourceHttpPolicy.mediaHeaders`/`MediaHandoff._prepareHeaders` 真實行為測試。驗收：netease CDN URL 輸出 headers 斷言無 Cookie/Authorization，且重構字串寫法不會繞過。
3. **備份還原韌性（F4）：** 兩階段寬容解析 + transaction。驗收：匯入損壞 JSON 失敗時不留部分寫入、UI 回報具體欄位。
4. **更新完整性（F6）：** checksum 缺失即拒絕。驗收：移除 manifest 中某 asset 的 sha256 → 該 asset 更新不可用。
5. **依賴衛生（F1）：** AGENTS.md 註記 Isar 凍結狀態 + 追蹤上游。驗收：文件明確記載 v3 為刻意選擇。

## 4. 本面向優先級 Top 3

1. **F1** — Isar 依賴衛生（正確定性為「上游低活躍但 v3 為官方建議」，建立追蹤與凍結註記）
2. **F3** — 補 integration/golden 測試（關鍵鏈路目前僅單元切片）
3. **F5** — 安全邊界測試改為真實行為驗證（防字串重構繞過）
