# 00 — FMP 成熟度審查總覽

> 唯讀審查（不修改任何原始碼）。本審查由六面向深度調查 + 對抗式驗證兩階段構成：先以並行 subagents 分頭調查 A–F 六面向（D 另以子系統並行掃描 + 彙整），再對所有 Critical/High 發現派獨立 agent 重讀原始碼覆核，避免誇大或誤報。所有發現均附 `file:line` 證據。
>
> 行動計畫：[01-action-plan](01-action-plan.md) — 含 2026-07 **執行成果**：29 項完成、4 筆查證撤回、剩餘藍圖（22 commits，皆 analyze + test 全綠）
>
> 詳細報告：[02-memory](02-memory.md) · [03-consistency](03-consistency.md) · [04-simplicity](04-simplicity.md) · [05-architecture](05-architecture.md) · [06-documentation](06-documentation.md) · [07-maturity-gaps](07-maturity-gaps.md)

## 1. 各面向成熟度評分（1–5）

| 面向 | 分數 | 一句話 |
|------|------|--------|
| **A** 記憶體與資源占用 | **4** | 自律性高、dispose/上限/虛擬化齊備；唯 `LyricsTitleParseCache` 無淘汰、下載 `.part` 不清理為短板。 |
| **B** 程式碼邏輯統一性 | **3** | 音源層乾淨；歌詞/匯入/更新子系統各自 `new Dio`、自有 exception、`debugPrint`，一致性在音源層之外崩掉。 |
| **C** 程式碼簡潔度 | **3** | 路徑/part/generated 處理規範；但 UI 巨型 State（900–1250 行）、`_startDownload` 267 行、dead CancelToken 路徑待拆。 |
| **D** 架構與新增音源可擴充性 | **3** | 核心抽象（SourceManager + narrow capability + auth 邊界）優秀；外圍層殘留三源硬編碼，部分會靜默失效。 |
| **E** 文件品質 | **3** | 分層設計良好且有靜態測試守門；但多處與程式碼飄移、一份 memory 會主動誤導。 |
| **F** 其他成熟度缺口 | **3** | CI/release/簽章/安全邊界工程化不錯；缺 coverage、integration 測試，Isar 鎖在低活躍的 v3。 |

**整體：核心抽象層達業界水準（A=4 拉高分數），外圍層的「三源硬編碼 + 子系統各自為政 + 一份誤導 memory + 測試/依賴追蹤缺口」是拉低均分的主因。**

## 2. 對抗驗證結果摘要（審查紀律）

驗證階段正確地**降級或撤回了多個被誇大的發現**，體現證據導向：

| Finding | 原嚴重度 | 驗證後 | 原因 |
|---------|----------|--------|------|
| A1（下載 task 啟動不裁剪） | High | **撤回（誤報）** | 啟動自動清理**已存在**於 `download_service.dart:194-200` |
| B1 / B2 | High | Medium | 屬一致性債、非 runtime 高風險（主音源路徑仍正確） |
| C1 / C2 | High | Medium | 純 code smell、無功能風險；player/search 其實已部分拆分 |
| D2 / D3 | High | Medium | 關鍵 switch 為 exhaustive（有編譯保護），「編譯器抓不到」標題偏誇大 |
| D5 | High | Low | enum 封閉型別下非靜默越界，屬 DRY 負擔 |
| **E3** | High | **High（維持）** | memory 路徑錯、xcopy 描述錯，且違反記憶政策 |
| F1（Isar archived/EOL） | High | Medium | **核心主張更正**：v3 是上游官方建議的生產版本，並非 archived |

> 其餘 Medium/Low 發現未個別對抗驗證（驗證僅覆蓋 Critical/High），以原評級呈現並在文中標註。

## 3. 跨面向 Top 10 優先改善清單

由各面向 Top 3 合併、依「驗證後嚴重度 → 影響 → 工作量（速勝優先）」排序：

| # | 項目 | 面向 | 嚴重度 | 工作量 | 動作 |
|---|------|------|--------|--------|------|
| **1** | **E3** 刪除/重寫過時且違反政策的 `.serena/memories/update_system.md` | E | 🔴 High | S | delete/rewrite |
| **2** | **D8** 修 `play_history_page` 把 netease 誤顯示為 YouTube 圖示（**現存可見 bug**，改用 `getImportSourceIcon`） | D | 🟡 Medium | S | 一行修 |
| **3** | **E1 + E2** 修正文件飄移：`pubspec.yaml` description 補 Netease、`docs/development.md` collection 註冊位置改指 `database_catalog.dart` | E | 🟡 Medium | S | rewrite |
| **4** | **D-隱性 bug 叢（D1+D4+D7+D13）** 以 `registeredSourceTypes` 為單一真相收斂會靜默失效的 hardcode：`SourceManager.dispose` 改 Disposable、`homeRankingSourceIds` 衍生、`loadVideoPagesForTrack` 改能力判斷、下載副檔名/頭像目錄資料驅動 | D | 🟡 Medium | M | 重構方案 4 核心 |
| **5** | **B1** 歌詞/匯入子系統 Dio 統一改走 `SourceHttpPolicy`/`HttpClientFactory`，刪裸 `new Dio()` | B | 🟡 Medium | M | 一致性主線 |
| **6** | **B2** 歌詞源 exception 改 `extends SourceApiException` 並用 `classifyDioError` | B | 🟡 Medium | L | 統一錯誤語義 |
| **7** | **F1** Isar 依賴衛生：AGENTS.md 註記 v3 為刻意凍結選擇 + 追蹤上游（修正「archived」誤判） | F | 🟡 Medium | L | 戰略性追蹤 |
| **8** | **A3 + A5** 資源治理：`LyricsTitleParseCache` 加 LRU/上限、下載 `.part` 啟動期孤兒掃描 + `_cleanupActiveTask` 刪 temp | A | 🟡 Medium | M | 防 mem/disk 單調上升 |
| **9** | **C2** `_startDownload` 拆三階段 + `_abortFinalizationCleanup` 單行化（267 行→~80 行編排） | C | 🟡 Medium | M | 可維護性 |
| **10** | **F3 + F5** 補 integration/golden 測試 + 把安全邊界測試從 static-rule 字串比對改為真實行為驗證 | F | 🟡 Medium | M | 防回歸/防繞過 |

> 速勝（本周可做）：#1、#2、#3 — 三件均工作量 S，合計清掉一份誤導文件、一個現存可見 bug、兩處文件飄移。
>
> 戰略性（本季）：#4 + #6 — 落實 D 的「漸進式重構」與歌詞統一語義；#7 追蹤依賴。

## 4. 「目前架構是否需要重構以支援新音源？」一頁結論

**需要「中幅重構」，但不要「推翻重寫」。**

- **不需要動的核心：** `SourceManager` + narrow capability（`AudioStreamSource`/`SearchSource`/`RankingSource`…）+ 共用 quality fallback（`audio_stream_quality_fallback.dart`）+ `MediaHandoff`/`SourceHttpPolicy` 嚴守的 auth 邊界（憑證不送 CDN byte）。新音源只要實作所需介面並加入 `SourceManager` 建構清單，就能被搜尋（透過 All）、串流、下載自動發現——**這部分已是業界水準**，推翻只會破壞已驗證邊界。
- **需要收斂的外圍：** 往外每一層的三源硬編碼。分兩類風險——
  - **(A) exhaustive switch**（`useAuthForPlay`、`AudioStreamConfig.fromSettings`、`SourceHttpPolicy` 三 switch、`AccountServiceAuthLoader`）：補 enum 值後編譯強制改，**相對安全**。
  - **(B) 字串/具名欄位 hardcode**（`homeRankingSourceIds`、per-source Settings 欄位、UI ChoiceChip/帳號卡/串流優先級、`allDirectSources`、`download_path_utils` 副檔名與頭像對映、`imageHeadersForUrl` host 白名單）：**編譯器抓不到，漏改會靜默失效**（新源 id 被 normalize 丟棄、頭像誤歸 youtube、搜尋 chip 不出現、排行榜 tab 不長出）。
- **新增第 4 音源現況成本：** 需同步改 8–12 個分散檔案、橫跨 enum/Settings/schema migration/source adapter/HTTP policy/UI/i18n（詳 [05-architecture.md](05-architecture.md) §2 的 14 步觸點清單）。
- **推薦方案（漸進式，方案 4）：** 以 `SourceManager.registeredSourceTypes` 為單一真相，先消除會靜默失效與實際可見 bug 的字串 hardcode（D1/D4/D7/D8/D9/D13），exhaustive switch 類暫留給編譯器保護；UI 清單式列舉（D5/D6）改遍歷 `registeredSourceTypes` 留待未來。工作量 M、不改 schema 邊界、不破壞 auth 安全模型、回歸風險低。**勿推翻 `SourceManager`/Capability 核心抽象。**

## 5. 一句話給決策者的風險摘要

> **FMP 的核心（音源/音訊/auth 邊界）已達業界成熟水準，無架構性危機；阻礙成熟度的是外圍的「三源硬編碼 + 子系統各自為政的 Dio/錯誤處理 + 一份會主動誤導 agent 的 memory + 缺整合測試與凍結依賴追蹤」——這些都是中低風險、可漸進修復的工程債，建議優先清掉三件速勝（誤導文件、history 圖示 bug、文件飄移）並展開 D 的漸進式重構。**

---

### 審查方法與限制

- **方法：** Step 0 先讀 root/CLAUDE.md 與六份 scoped `AGENTS.md` 建立心智模型；以 ripgrep 全庫掃描 + 對關鍵檔（`audio_provider.dart`、`youtube_source.dart`、`download_service.dart`、`source_provider.dart`、`source_capabilities.dart`、`source_http_policy.dart`、CI/release workflow）逐行取證；D 面向以六子系統並行掃描後彙整。
- **對抗驗證：** 所有 Critical/High 發現派獨立 agent 重讀原始碼試圖推翻，1 筆撤回、6 筆降級、1 筆核心主張更正、1 筆維持。
- **限制：** Medium/Low 發現未逐筆對抗驗證；效能/記憶體結論基於靜態程式碼推論而非實測（A 面向部分標「待確認」）；未實際執行測試套件驗證覆蓋率數字。
- **範圍：** 唯讀，未修改任何原始碼，未 commit/push。產出僅本目錄七份報告。
