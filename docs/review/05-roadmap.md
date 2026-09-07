# 05 — 總體路線圖與決策彙整

- **審查日期**：2026-09-02
- **HEAD**：`d4401cbe`（工作樹乾淨）
- **範圍**：不重新審查程式碼。輸入是 `docs/review/01`–`04` 四份報告，本輪只做**綜合、排序與決策**。
  只在四份報告互相矛盾、或在報告寫成之後樹上已經變動時回頭查證（查證記錄見 §8）。
- **本輪未修改任何專案檔案**，除了這一份報告。

> 標記約定沿用前四輪：**【事實】**＝有指令輸出或 `file:line` 佐證；**【推論】**＝由事實推導；
> **【建議】**＝行動提案，附成本（S/M/L）、風險、可逆性。

---

## 目錄

1. [現況：四份報告在說同一件事](#1-現況四份報告在說同一件事)
2. [重寫 vs 漸進重構：最終結論](#2-重寫-vs-漸進重構最終結論)
3. [總體路線圖](#3-總體路線圖)
4. [七＋五個項目的一段式摘要](#4-七五個項目的一段式摘要)
5. [決策清單](#5-決策清單)
6. [Quick wins 彙整](#6-quick-wins-彙整)
7. [10 個 issue 的處置](#7-10-個-issue-的處置)
8. [驗證記錄：本輪查證了什麼](#8-驗證記錄本輪查證了什麼)

---

## 1. 現況：四份報告在說同一件事

### 1.1 四份報告的獨立結論收斂到同一個形狀【推論】

四輪是分開做的，範圍不重疊，但結論的形狀一致：

| 輪次 | 範圍 | 該輪對「重寫 vs 漸進」的結論 |
|---|---|---|
| 01 | 文檔體系、目錄結構、測試資產 | 「**沒有任何一個模組建議重寫**」（§6） |
| 02 | 播放核心、音源層 | 「播放核心：漸進重構，不重寫」；`AudioController` 是**搬移不是重寫**（§8） |
| 03 | 資料層、狀態管理、平台、授權 | 「**本輪範圍內沒有任何一塊我建議重寫**」（§10） |
| 04 | UI / UX、佈局、設計語言 | 「漸進重構。這個模組沒有需要重寫的理由」（§11） |

**四輪一致的診斷是同一句話**：這個 repo 的問題不是「結構錯了」，而是三件事的疊加 ——
**（a）邊界畫在錯的位置**（`services/` ↔ `providers/`、repository 邊界外 152 個呼叫點、
視窗級斷點餵給容器寬度）、**（b）少了三個具體機制**（URL 快取、逾時預算、schema 版本號）、
**（c）文檔比程式碼腐爛得快**（76 條 AGENTS.md 斷言抽驗 83% 正確、`CONTEXT.md` 在
`c09aec10` 之後就過時了）。這三種病都是漸進重構能解的。

### 1.2 健康度證據（反對重寫的一手事實）【事實】

- 測試套件：**78.3% 是真正的行為測試、0 檔無法理解**，乾淨環境 3/3 全綠（01 §2.6、§1.2）。
- 音源層抽象**已經是 capability-based**：11 個窄介面、`SourceManager` 幾乎無 switch、
  三個 adapter 零 `UnsupportedError`（02 §2.1）。
- 資料層乾淨：11 個 collection、188 個持久化屬性、**零 `IsarLink`**、窄查詢面 —— 沒有任何
  Isar 專屬語意需要翻譯（03 §10）。
- 備份格式**有版本號 + 前向相容閘門**，且刻意排除裝置局部欄位（03 §1.4、§13）。
- CI 已 SHA 釘選 actions、有 checksum manifest、Zip-slip 防護、ISS patch 迴歸閘門（03 §4.2–4.3）。
- UI 實測 **340dp 到 1700dp 全部正常降級，無 overflow、無崩潰**（04 §7.2b）。

### 1.3 但有兩個地方在「往反方向長」【事實，本輪查證】

1. **`audio_provider.dart` 從 2,998 行長到 3,429 行**（+431）。02 §8.1(A) 的
   `PlaybackEndReason` 已經落地並刪掉約 120 行字串比對（`rg "_isStringNetworkError"` 現在
   零命中），淨值仍然是**變大**。god class 沒有停止生長。
2. **`Settings` 從 57 欄位長到 67 欄位**，而 03 §D13 要刪 6 個死欄位、04 §P1-3 要加 3 個、
   02 §D6 要把每源欄位改成 map。三個方向同時作用在同一個 collection 上。

這兩件事直接決定了路線圖的兩個排序決定（Phase 4 與 Phase 3c）。

### 1.4 報告寫成之後樹上已經變動的部分【事實，本輪逐項複驗】

02 的第八輪實際改了碼。以下是**已經完成、不要再照著做**的：

| 項目 | 狀態 | 證據 |
|---|---|---|
| 02 §8.1(A) `PlaybackEndReason` / `endReasons` | ✅ **已落地** | `audio_service.dart:29` `Stream<PlaybackEndReason> get endReasons`；`audio_types.dart:80,96,107` 有 `EndedPrematurely` / `TransportFailed` / `OutputDeviceFailed`；`_isStringNetworkError` / `_isStringMediaOpenError` 全庫零命中 |
| 02 §6.3 階段 2（型別化錯誤） | ✅ **等於已完成** | 同上。**02 的階段編號在本輪之後要重編** |
| issue #41 | ✅ **已修**（`056f20c3`） | `OutputDeviceFailed` 就是它要的型別化訊號 |
| 02 §7.4 步驟 3（排行榜快取註冊表化） | ✅ **已完成**（`583eef90`） | `ranking_cache_service.dart` 從約 500 行降到 **288 行**；`SourceType.bilibili\|youtube\|netease` 命中數 **0**；`:271` 改成 `for (final sourceType in manager.registeredSourceTypes)` |
| 02 Q24 / Q32 / Q33 / Q34 | ✅ 已修（`ecbaeb91` / `d0282a25`） | 見 02 §12.21–12.22 |
| 02 D8（Netease 媒體憑證路徑） | ✅ 已刪除（`c09aec10`，淨刪 547 行） | 見 02 §9 的 D8 段 |

以下是**仍然成立**的（本輪回頭確認）：

| 項目 | 狀態 | 證據 |
|---|---|---|
| 02 P0-1 串流解析零快取 | ❌ **仍然開著** | `stream_resolution_service.dart` 的 `resolvePrimary()` 只查本地檔就直接 `_resolveRemotePrimary`；`hasValidAudioUrl` 在該檔只出現在 `:220` 的預取去重守衛裡，不在解析路徑上 |
| 02 P0-2 播放載入無逾時 | ❌ **仍然開著** | `rg "timeout" lib/services/audio/playback_request_session.dart` **零命中** |
| 01 P0-1 / P0-2（`test/performance/` 與 `test/demo/bilibili_info_test.dart`） | ❌ 仍然開著 | 兩個 benchmark 仍是 `*_test.dart`；`test/demo/bilibili_info_test.dart` 仍在 |
| 01 決策點 1（`docs/adr/`） | ❌ 仍是**本機空目錄且未進版控** | `git ls-files docs/adr` 零輸出 |
| 03 P2-3 / 04 P3-1 死依賴 | ❌ 仍在 pubspec | `dynamic_color:15`、`riverpod_annotation:19`、`flutter_reorderable_list:53`、`logger:77`、`uuid:79`、`intl:82` |
| 03 §9.4 授權 | ❌ 仍是 GPL-3.0，且無 `NOTICE` | `LICENSE` 首行是 GNU GPL v3；`ls NOTICE THIRD_PARTY*` 無檔案 |
| 依賴天花板 | ❌ 仍在 | `pubspec.lock`：`analyzer 5.13.0`、`isar 3.1.0+1`、`slang 3.32.0` |

---

## 2. 重寫 vs 漸進重構：最終結論

### 2.1 結論

**全面採用漸進重構（strangler fig），不重寫任何模組。**
但要把「漸進」講精確 —— 這個 repo 需要的是**四條互相獨立的絞殺路徑**，不是一條：

| # | 絞殺對象 | 絞殺方式 | 每一步的驗收 |
|---|---|---|---|
| **S1** | `lib/services/` + `lib/providers/` 兩個頂層目錄 | 一次搬一個 feature 進 `lib/features/<name>/`，配一條可 `rg` 的機械規則 | `flutter analyze` 全綠（Dart 無動態 import，這是完整驗證） |
| **S2** | `AudioController`（3,429 行） | 一次抽一個責任叢集成協作者（E→B→D→C），controller 只留投影與轉發 | `test/services/audio` 全綠 + 兩平台實機 |
| **S3** | 每源硬編碼（`SourceType` enum、`Settings` 具名欄位） | 一次收一個維度進 registry。**排行榜快取已經做完，這是活的先例** | 新增第四個內建源時只需要加一個 adapter |
| **S4** | 形狀猜測式 migration（`_hasLegacy*Signature`） | `Settings.schemaVersion` + 具名遷移步驟；舊啟發式降級成一次性的「推斷 v0」入口 | v0→v1 遷移測試 |

`isar` → `isar_community` **不是**絞殺，是 drop-in 替換（85 個 import 行，資料遷移實測為零）。
`isar` → drift 才會需要 Immich 式的雙寫共存絞殺 —— 那是明確保留的長期選項，不是現在。

### 2.2 唯二值得「局部重寫」的地方（兩者都 ≤ 120 行）

1. **`responsive_scaffold.dart` 的 `_buildDetailPanelContainer`**（`:342-460`）—— 它是
   04 的 P0-1 / P1-3 / P1-4 / P2-5 的共同宿主，`Stack` + `OverflowBox` + `AnimatedContainer`
   + 手刻拖動 + 半透明遮罩疊在一起。連同 04 §10.1 一起重寫這一個方法，其餘不動。
2. **migration 機制**（03 §10）—— 這是四份報告裡唯一一處「換掉現有做法」而不是「改進現有做法」。

### 2.3 反對重寫的具體代價（三份報告各自舉證）

- **播放核心**：`audio_provider.dart` 承載 seek 穩定化視窗、supersede 世代、premature completion、
  Mix load-more 競態 —— 這些是踩過坑才有的程式碼，重寫會把它們全部變成未知數（02 §8）。
- **UI**：`lib/ui/AGENTS.md` 有整段「Page Conventions —— 這些是刻意的，不要修」；播放頁 backdrop
  預載、route transition 剪裁、Windows 拖動區、桌面歌詞子視窗的 channel 注入都是坑的解法（04 §11）。
- **Agent 指令體系**：1,313 行裡記錄了大量無法從程式碼推導的 rationale（buffer profile 數值、
  YouTube 縮圖 4:3 黑邊、AXTree 假 API）。重寫會丟掉這些（01 §6）。

### 2.4 一句話

> 這個 codebase 不是「爛到要重寫」，而是**卡在一個停更的依賴上，而那個依賴同時是整個 build
> 生態的天花板**（03 §10 原句）。優先處理依賴，其餘按 P0→P1 走，每一步都留下可運作、可發版的 repo。

---

## 3. 總體路線圖

### 3.0 全域規則（每個 Phase 都適用）

1. **每個 commit 結束時 repo 必須可跑可測可發版。** 不拿能動的產品換做一半的複雜度。
2. **每個 Phase 結束時跑一次完整驗收**（`flutter analyze` + `flutter test` + 該 Phase 對應的實機驗證）。
3. **使用者可見的變更一律走 `.claude/skills/verify-on-device/SKILL.md`**，Android 模擬器為必要平台。
4. **持久化格式的破壞性變更、對外介面變更（含 pubspec）必須先問。**
5. **不為想像中的未來需求加抽象層** —— 特別是 03 §9.1 引的 Immich 反向教訓：他們用 20+ 個 PR
   把預先加的 `domain/interfaces/` 整層刪掉了。

### 3.1 相依與平行關係圖

```text
Phase 0  止血與真相同步  ────────────────────────────────────┐  （與所有 Phase 平行）
                                                            │
Phase 1  播放體驗（P0-1/P0-2/P0-3 剩餘）  ──┐               │
                                            │               │
Phase 5  UI/UX（5a 止血 → 5b token → 5c/5d/5e/5f/5g）──┐    │
                                            │           │   │
Phase 7  授權與揭露（NOTICE / qq_music_sign / MIT）─────┼───┤
                                            │           │   │
Phase 2  依賴天花板（slang 4 → isar_community）  ★阻塞  │   │
   │                                        │           │   │
   ▼                                        │           │   │
Phase 3  狀態層與資料層治理                 │           │   │
   3a Riverpod 3（legacy）                  │           │   │
   3b schemaVersion                         │           │   │
   3c ★單一批次 Settings schema 變更 ───────┼───────────┘   │
   3d repository 邊界收斂                   │               │
   3e 備份守門 / TrackKey / 匯入原子性      │               │
   │                                        │               │
   ▼                                        ▼               │
Phase 4  AudioController 拆分（E→B→D→C）◄──┘               │
   │                                                        │
   ▼                                                        │
Phase 6  目錄結構重構（features/）◄─────────────────────────┘
   │        （必須等 1/4/5 的程式碼變動穩定下來）
   ▼
Phase 9  音源插件化（9.1 內建介面統一 → 9.2 flutter_js → 9.3 介面凍結+提示詞 → 9.4 信任模型）
            ↑ 前置的 SourceType 字串化 + Settings map 化併進 Phase 3c

Phase 8  平台擴展 —— ❌ 已決定不做（只做 Android + Windows）
            但「50 處 Platform.isWindows 重新分類」保留在 Phase 4/6 內
```

**可平行的**：Phase 0 與全部；Phase 1 ∥ Phase 5a/5b/5f/5g ∥ Phase 7；Phase 3a ∥ Phase 3c–3e（前提是 3c 先落地）。
**硬阻塞**：Phase 2 → Phase 3；Phase 3c → Phase 5c；Phase 3c → Phase 9.1；Phase 3a → Phase 4 的 `Notifier` 改寫部分。

---

### Phase 0 — 止血與真相同步

**目標**：移除 CI 上唯二的結構性紅燈、修掉使用者看得到的靜默失敗、刪死依賴、讓文檔與程式碼一致。
**涉及模組**：`test/`、`.github/`、`docs/`、`AGENTS.md` ×7、`CONTEXT.md`、`lib/main.dart`、`lib/i18n/`、少量 UI 單行。
**依賴**：無。可立刻開始，與任何 Phase 平行。
**規模**：**S**（約 1–2 個工作日，拆成 5 個 PR）。

| 批次 | 內容 | 對應 Quick win |
|---|---|---|
| **0a** CI / 測試衛生 | 3 個檔名改動（`test/performance/*_test.dart` → `*_benchmark.dart`、`test/demo/bilibili_info_test.dart` → `*_demo.dart`）、`timeout-minutes`、CI path filter、`dependabot.yml` 加 `groups`、刪 `test/widget_test.dart`、併 `lyrics_window_layout_test.dart`、`flutter pub run` → `dart run` | 01#1,2,13,14,18,19；03 Q48,Q49 |
| **0b** 文檔真相 | AGENTS.md 13 條錯誤斷言、`CONTEXT.md` 的 Netease allowlist（已被 `c09aec10` 刪除）、`docs/README.md` 的 `/qa`、capability 5→11、buffer profile 描述、`verify-on-device/SKILL.md` 補 6 條實測限制、`refactoring-log.md` banner | 01#3,5,6,7,8,9,10,11,12,17；02 Q12,Q13,Q14,Q26,Q30；03 Q37,Q38 |
| **0c** 使用者可見單行 | `player_page.dart:488` 的 artist fallback（正在播放時顯示「選擇一首歌曲開始播放」）、shuffle 圖示、設定頁副標題漏網易雲、`radio_player_page.dart:219`、8 個 tooltip、`semanticFormatterCallback`、狀態列 `AnnotatedRegion` | 04 Q1,Q2,Q4,Q8,Q9,Q10,Q11,Q12,Q13 |
| **0d** 死依賴與死碼 | 刪 6 個直接依賴（`dynamic_color` / `riverpod_annotation` / `flutter_reorderable_list` / `logger` / `uuid` / `intl`）、刪 `SourceManager` 5 個死方法 + 2 個死 provider、`WindowsSmtcHandler.enable/disable/dispose`、`mobilePlayerBufferSizeBytes`、3 個無呼叫方的 `watch*` | 01 決策點7；02 Q9,Q10；03 Q35,Q36,Q42 |
| **0e** 安全與韌性 | `maxSizeMiB: 64 → 2048`、`MediaKit.ensureInitialized()` 包 try/catch、`_preloadThemeSettings()` 的空 catch 補 log、`AndroidManifest` 加 `allowBackup="false"`、log 遮蔽補裸 `csrf`、Bilibili/Netease `logout()` 清 WebView cookie、下載 isolate redirect 補 URL policy、`youtube_stream_test_page` 的 Cookie 探測加 `kDebugMode` gate | 01#15；03 Q40,Q41,Q43,Q44,Q45,Q46,Q53 |

**驗收**：
- `flutter analyze` 全綠；`flutter test` 連跑 3 次全綠。
- **CI 不再對 Bilibili 生產 API 發請求**（`rg "api.bilibili.com" $(rg --files -g '*_test.dart' test/)` 零命中）。
- 預設測試套件內**零 wall-clock 絕對毫秒斷言**。
- 實機：模擬器切 per-app locale 到 zh-TW，通知頻道名稱跟著變（P1-9 的驗收）。
- 76 條 AGENTS.md 斷言重新抽驗，錯誤數 0。

> ⚠️ **0d 需要決策**：依 `AGENTS.md` 的規則，改 pubspec 算對外介面變更。`intl` 要先確認不是
> `flutter_localizations` 版本解析所需（03 §14.2 未涵蓋這點）。

---

### Phase 1 — 播放體驗（tracer bullet）—— **已執行（2026-09-02）**

> 執行時的重核推翻了下表的部分估算、並把 D1／D2 兩個決策點定案，**見 §6.2**。
> 下表保留原樣以便對照。

**目標**：消滅每次播放固定多付的 1.25–1.74 秒、給載入路徑一個上界、修掉 YouTube 每次 20 秒的退化。
**涉及模組**：`lib/services/audio/`（`stream_resolution_service` / `playback_request_session` / `media_kit_audio_service`）、`lib/data/sources/`。
**依賴**：無（`PlaybackEndReason` 已落地，型別化錯誤的前置已具備）。
**規模**：**M**（約 3–5 個工作日）。可與 Phase 5、Phase 7 完全平行。

| 步 | 內容 | 成本 | 對應 |
|---|---|---|---|
| 1.1 | `resolvePrimary()` 開頭加 `hasValidAudioUrl` 短路（含 5 分鐘安全邊界，復活死掉的 `SourceManager.needsRefresh` 語意） | S | 02 Q1 / P0-1 |
| 1.2 | 預取改 `persist: true` 且不傳 `copy()`；`_executeQueueRestore` 補上預取 | S | 02 Q2,Q4 |
| 1.3 | `AudioStreamResult` 加 `cid`，`_applyStreamResult` 回寫 `track.cid`（消滅 Bilibili 每次多一次 `/x/web-interface/view`） | S | 02 Q3 / P1-5 |
| 1.4 | 讀真實過期時間：Bilibili 從 URL query 的 `deadline`（實測 7178s）、Netease 從 API 回的 `expi`（實測 1200s） | S | 02 Q5,Q6 |
| 1.5 | **逾時預算**：`_waitForRequestOperation` 加 `timeout`；media_kit 設 `network-timeout`；三層重試改共用總預算 | S–M | 02 P0-2 / D1,D2 |
| 1.6 | YouTube auth 升級改成「同一 streamType 先匿名、失敗再帶 auth」（現在是所有 streamType 匿名跑完才整批帶 auth，導致帶登入的 audio-only 路徑**結構上到不了**） | S | 02 Q17 / P0-3 |
| 1.7 | Netease `flag & 4` 誤判修正（未登入被說成「需要 VIP」）；`_shouldHandleTrackCompleted` 的 `duration == null` 不再直接放行 | S | 02 Q22,Q23 / P1-10 / P0-5 |
| 1.8 | `StreamResolutionService` / `AudioStreamManager` 補「開始／完成／耗時」三行 log（現在整條最慢的路徑**一行 log 都沒有**） | S | 02 Q25 |
| 1.9 | `stallsrv.py` / `holdsrv.py` 收進 `scripts/` 或 `test/manual/`，並在 `lib/services/audio/AGENTS.md` 指向它們 | S | 02 Q31 |

**驗收**（每一條都是可執行的）：
- 同一首歌連播 3 次，`AppLogger` 顯示 **1 次** API 往返而不是 3 次（對照 02 §12.2 的實測基準）。
- 用 1.9 的零位元組伺服器：兩平台都在預算內產生 `TransportFailed` 或 `EndedPrematurely`，
  **不再是 Windows 6.1 秒假成功 / Android 37.7 秒才拋**。
- YouTube 點擊→出聲在正常網路下 < 5 秒（對照現況實測 22.2s / 23.6s），且串流是 audio-only。
- 曲間靜默從實測 2.9s 降到 1.2–1.5s。
- 兩平台實機各跑一輪。

> ⚠️ **需要決策**：D1（T1/T2/T3 具體數值）與 D2（逾時之後跳歌／停下通知／換 fallback）。
> 我的傾向：T1=8s / T2=10s / T3=20s；逾時後先換 fallback 串流一次，仍失敗才停下並通知
> （介於 Auxio 的「直接跳」與 Finamp 的 `maxSkipsOnError:0` 之間）。

---

### Phase 2 — 依賴天花板（★阻塞 Phase 3）—— **已執行（2026-09-02）**

> 執行時的重核推翻了下表的兩條主張、補上五件沒寫到的事，**見 §6.3**。
> 下表保留原樣以便對照。

**目標**：把 analyzer 從 5.13.0 解到 10.x、解鎖 Riverpod 3、修 Android 16KB page size 對齊、
脫離停擺 14 個月的上游 `isar/isar`。
**涉及模組**：`pubspec.yaml`、`slang.yaml`、`lib/main.dart`、`lib/providers/locale_provider.dart`、
`lib/app.dart`、85 個檔案的 `package:isar` import、`test/` 40 份重複 helper。
**依賴**：Phase 0d（先刪 `riverpod_annotation` —— 實測它擋著 `flutter_riverpod` 拿到 3.4.2）。
**規模**：**M**（約 2–4 個工作日）。

**硬性順序**（03 §14.2 實測：兩者必須一起做，但要拆成兩個獨立 commit）：

| 步 | 內容 | 為什麼是這個順序 |
|---|---|---|
| 2.0 | 抽 `test/support/isar_test_harness.dart`，消掉 40 個測試檔各自複製的 `_resolveIsarLibraryPath()` | 它是**任何** Isar 變動的固定稅，先做掉 |
| 2.1 | ~~`slang_flutter` / `slang_build_runner` **3.32 → 4.19**~~ → 實際做法：`slang_flutter` 升 4.19 並**移除** `slang_build_runner`、改直接依賴 `slang` CLI（§6.3 #1） | `isar_community_generator ≥3.3.1` 依賴 `build ^4`，`slang_build_runner <4.8.0` 依賴 `build ^2.2.1` —— 不先升 slang，`flutter pub get` 就會 version solving failed |
| 2.2 | 修 slang 4 的呼叫點：~~`slang.yaml` 的 `output_file_name`~~（那個鍵沒變，要加的是 `lazy: false`，§6.3 #2–#3）、`main.dart` 與 `locale_provider.dart` 的 `setLocale`/`useDeviceLocale`（4.x 回傳 `Future`，同步版要 `-Sync` 後綴） | **與 Phase 0 的 P1-9 修法有交互作用**：0 期把 `useDeviceLocale()` 上移到 `AudioService.init()` 之前，這裡要改成 `useDeviceLocaleSync()`，否則會變成未 await 的 Future 而 `flutter analyze` 完全沉默 |
| 2.3 | `isar` / `isar_flutter_libs` / `isar_generator` → `isar_community*`，85 個 import 機械替換 | ~~純 `sed`~~ —— 還要改 Windows 動態庫檔名（`isar.dll` → `libisar.dll`）與 `flutter_window.cpp` 的 plugin header 路徑（§6.3 #5） |
| 2.4 | `pubspec.yaml` SDK 下限 `>=3.5.0` → `>=3.9.0` | `isar_community_generator` 3.3.2 的要求（Flutter >= 3.35.1） |
| 2.4b | 把 `intl` 加回直接依賴 | slang 4 生成碼直接 import 它（§6.3 #4） |
| 2.5 | `dart run build_runner build` + `dart run slang` | build_runner 2.15 已移除 `--delete-conflicting-outputs`（§6.3 #7） |

**驗收**：
- `flutter analyze` 全綠、完整測試套件全綠（**基準需要在 Phase 0 結束後重新量一次**，見 §8.3）。
- 重建 APK，`lib/*/libisar.so` 的 LOAD align 從 `0x1000` 變成 `0x4000`（4 個 ABI）。
- 拿**生產資料庫的副本**原地開啟，11 個 collection 逐項一致（03 §14.4 已預先實測過，這裡是複驗）。
- 實機：模擬器切 zh-TW，通知頻道名稱正確（確認 2.2 沒有把 P1-9 的修法弄壞）。
- `dart pub deps` 顯示 analyzer ≥ 10.x。

**風險與退路**：全部是 pubspec + import 的變動，`git revert` 兩個 commit 即可完全回退。
資料面實測風險為零（03 §14.4：11 collection 生成碼逐字相同、schema id hash 全同、真實 DB 副本原地讀寫成功）。

> **據實記錄的風險**：`isar_community` 是「有人維護」而非「活躍開發」—— 最後一次 commit
> 2026-07-03，最新 release 3.3.2 是 5 個月前，整個 fork 只有 5 個 release。它解決的是
> 「完全沒人管」，不是「回到活躍」。

---

### Phase 3 — 狀態層與資料層治理 —— **已執行（2026-09-03 / 04）**

> 執行時的重核推翻了 3c「合成一次批次才沒有邊際成本」的理由，並改變了
> auto-retry 的處理方式（改成 `ProviderScope` 一個全域關閉，不逐個 provider
> 決定），**見 §6.4** 與 ADR 0001／0002。下表保留原樣以便對照。

**目標**：把 migration 從不可證偽的形狀猜測換成版本號、一次做完所有 `Settings` schema 變更、
把 152 個 repository 邊界外呼叫點的 63% 收回去、升 Riverpod 3。
**涉及模組**：`lib/data/`、`lib/providers/`、`lib/services/backup/`、`lib/services/library/`。
**依賴**：Phase 2（硬阻塞）。
**規模**：**L**（約 8–12 個工作日）。

| 子階段 | 內容 | 成本 | 備註 |
|---|---|---|---|
| **3a** | Riverpod 2 → 3，走 `flutter_riverpod/legacy.dart`（35 個檔各加一行 import，**不做** 39 個 `StateNotifierProvider` 的改寫） | M（2–4 人日） | 三個行為變更要逐一處理：**out-of-view pause**（風險最高，音樂播放器不能在 UI 不可見時停）、**auto-retry 預設開啟**（26 個 `FutureProvider` + 7 個 `StreamProvider` 逐一決定）、**`UnmountedRefException`**（10 處 async-body `ref.read`）。**這三項 `flutter test` 涵蓋不到，必須實機驗背景播放、下載進度、Windows 最小化到 tray** |
| **3b** | `Settings.schemaVersion` + 具名遷移步驟；舊的 `_hasLegacy*Signature` 降級成一次性的「推斷 v0」入口 | M | 部分不可逆（欄位寫下去就回不去），但那正是要做的事 |
| **3c** | **★單一批次 `Settings` / model schema 變更** —— 一次 `build_runner`、一次 migration、一次備份格式更新、一次 `database_catalog` 同步 | M | 見下方展開 |
| **3d** | repository 邊界收斂：先收 `playlist_mutation_service`(39) / `backup_service`(36) / `data_integrity_service`(20)，這三個佔 152 個邊界外呼叫點的 **63%**；補 `AccountRepository`（唯一沒有 repository 的 collection） | M–L | **不要**再加一層 `abstract interface class Repository`（Immich 反向教訓） |
| **3e** | 備份欄位覆蓋守門測試、`TrackKey` value object（識別鍵公式重複 7 處且零守門測試，它同時是資料庫外鍵與備份格式）、備份匯入原子性（現在 9 次 `writeTxn` 無外層交易） | M | |

**3c 的批次內容（這是本輪最重要的排序決定）**：

```text
刪：5 個死的自訂色欄位、RadioStation.note、Track.sourceKey 的死索引
加：Settings.schemaVersion                          （3b）
加：detailPanelWidth / detailPanelExpanded / railExpanded  （04 P1-3，Phase 5c 的前置）
加：PlayHistory.trackKey 的 @Index()                （Q58，讓 6 個全表掃描變索引查詢）
改：preferredAudioDevice* 從死欄位變成真的會被讀寫  （issue #42）
改：SourceType 封閉 enum → 「內建常數 + 字串 id」雙軌    （★Phase 9.1 的前置）
改：每源具名欄位 → List<SourceSettingsEntry>（@embedded）（★Phase 9.1 的前置，02 D6）
同步：SettingsBackup / RadioStationBackup / database_catalog.dart
```

**理由**：這 7 件事各自都要 `build_runner` + 一次 migration + 備份格式同步 + `database_catalog`
同步 + 遷移測試。分開做 = 做 7 次。**合成一次 = 一次成本。**
最後兩項原本是 02 的 D6（「要不要做、什麼時候做」）—— 既然 Phase 9 已定案要做，
**它們在這裡做的邊際成本幾乎為零，單獨做則要再付一整輪 migration。**
而且它同時解掉 03 的 P2-15（死欄位進備份，在使用者之間搬運永遠為 null 的值）與 04 的 P1-3
（面板寬度每次啟動重置）。

**驗收**：
- `test/providers/database_migration_test.dart` 覆蓋 v0→v1，且「重跑兩次不覆蓋使用者設定」的既有斷言仍綠。
- 備份 round-trip 測試證明無欄位靜默遺失（新增的守門測試）。
- `rg "\bisar\.[a-z]|_isar\.[a-z]"` 在 repository 之外從 152 降到 < 60。
- 實機：Android 背景播放 5 分鐘不中斷、下載進度持續更新、Windows 最小化到 tray 後播放不停。

---

### Phase 4 — `AudioController` 拆分 —— **部分執行（2026-09-05 / 06）**

> 執行時的重核否決了下表之外追加的 F／G 兩步，並**推翻了下方的 ≤800 行驗收線**，
> **見 §6.5–§6.8**。下表保留原樣以便對照。
>
> ~~**本節列出但尚未開始的兩項**：`StateNotifier` → `Notifier` 改寫、
> `FmpAudioService.setQueue` / `supportsQueue`。~~
> **兩項都已於 2026-09-07 完成。** `Notifier` 改寫見 **§6.12**（Round A）：
> 43 個 legacy provider 全部改寫，`lib/` 已無 `flutter_riverpod/legacy.dart`。
> 佇列語意見 **§6.13**（Round B）：介面落在 `setNextMedia` /
> `advancedToNext`，不是原本寫的 `setQueue` / `supportsQueue`。
> **Phase 4 按本節的定義到此完成。**

**目標**：把 3,429 行、90+ 欄位的 god class 拆成「投影 + 轉發 + 接線」，目標 400–800 行。
**涉及模組**：`lib/services/audio/` 全部。
**依賴**：Phase 3a（`StateNotifier` → `Notifier` 的部分）。協作者抽取本身可以更早開始。
**規模**：**L**（約 8–15 個工作日）。

順序（02 §8.1，A 已完成，從 E 開始）：

| 步 | 抽出什麼 | 成本 | 為什麼是這個順序 |
|---|---|---|---|
| **E** | `QueueCommands`（`addToQueue` / `addNext` / `moveInQueue` / …，全是同一套樣板） | S | 最容易，當熱身，驗證拆分模式 |
| **B** | `NowPlayingPublisher` + `PlaybackCapabilities`（收掉 8 處 `_usesMobileAudioHandler` 平台分支） | S–M | **直接修掉 issue #40 的症狀一**：進電台時發 `canSkipNext: false` |
| **D** | `PlaybackObserver` ×3（`PlayHistoryObserver` / `LyricsAutoMatchObserver` / `MixPrefetchObserver`，搬走 33 處 `_mix*`） | M | 把副作用從播放路徑上摘下來，播放不再等它們 |
| **C** | `PlaybackSessionCoordinator`（`_context` 65 處 + `_pendingSeek` 22 處 + **Phase 1 的逾時預算收斂到這裡的單一 `budget`**） | M–L | 最大、最後做，因為它會動到 seek 與逾時語意 |

~~**同時做**：`AudioController` / `RadioController` 的 `StateNotifier` → `Notifier` 改寫
（03 §9.2 明說這屬於拆分計畫，不屬於 Riverpod 升級 —— 這兩個類別就佔了改寫工作量的一半以上）。~~
**已執行（2026-09-07，Round A）**，但不是「同時做」而是獨立的一輪 ——
`lib/providers/AGENTS.md` 當時有一條「do not start it opportunistically」與這裡
矛盾，四輪 Phase 4 因此都被禁止順手做它。**那條矛盾已一併移除，見 §6.12。**

~~**這裡也是佇列語意該落地的地方**：`FmpAudioService` 現在的開媒體介面一次只吃一個
媒體，沒有 `setQueue` / `supportsQueue`（02 §6.3 階段 4）。~~
**已於 2026-09-07 做掉（Round B，見 §6.13）**，但簽名不是原本寫的那兩個：
落地的是 `setNextMedia(PreparedPlaybackMedia?)` ＋
`Stream<PreparedPlaybackMedia> advancedToNext`。一次交一整份佇列做不到（串流
URL 逐首解析、簽名 1–2 小時到期、會被風控），能交給後端的只有**一個**前瞻項目；
`supportsQueue` 則是一個兩個後端都回 true 的布林，沒有加。這一項的阻礙確實一直是
FMP 自己的介面，不是套件版本。

**驗收**：
- ~~`audio_provider.dart` ≤ 800 行（目前 3,429）。~~ **這條已作廢，見 §6.8。**
  實際落點 2,573 行，而剩下的 2,573 行裡有 1,080 行是投影與 transport 命令 ——
  它們就是 `AudioController` 這個類別的定義，再抽協作者只會產出 15–26 個回呼的
  假邊界。**重述為：`AudioController` 不再持有任何可以獨立測試的規則。**
  要再往下需要改變控制器*是什麼*（拆 `PlayerState` 本身、或 `Notifier` 改寫），
  不是把東西搬出去。
- `test/services/audio` 全綠；每一步結束都重跑 Phase 1 的零位元組伺服器實驗當回歸。
- 實機：Windows 上電台播放時 SMTC 的 `IsNextEnabled` 為 `False`（用 WinRT 的
  `GlobalSystemMediaTransportControlsSessionManager` 直接讀，不截系統浮出視窗）。
- 兩平台各跑一輪完整播放流程（佇列、單曲循環、切歌、電台）。

---

### Phase 5 — UI / UX（與 Phase 1–4 平行）—— **已執行（2026-09-06 / 07）**

> 執行時的重核推翻了下表 5a 的兩個計數與 5b、5f 的三條說法（**§6.10**），
> 第二輪又推翻了八條（**§6.11**）。
> **5a / 5g** 在 `9557e03f`、`bcb76014`…`1c5a4e4d`、`0483bf8b`…`2421f73d`。
> **5b–5f** 在 `81d8fc1f`…`063a5b73`。Phase 5 到此收尾。

**目標**：修掉「播一首歌就少掉一個內容來源」的 P0、建立 design token 層、把面板與播放頁的版面決策改成有依據的。
**涉及模組**：`lib/ui/` 全部、`lib/core/constants/ui_constants.dart`。
**依賴**：5c 依賴 Phase 3c（面板持久化欄位）。其餘全部獨立。
**規模**：**M–L**（每個子項 S–M，合計約 8–12 個工作日）。

| 子階段 | 內容 | 成本 | 依賴 |
|---|---|---|---|
| ~~**5a** 止血（先做）~~ **已完成** | ① `home_page.dart:67-69` 改用容器級 `columnsFor(constraints.maxWidth)` —— **一行修法直接消滅 P0-1**（1280dp 平板一播歌就掉一個音源）② `download_manager_page.dart:343-350` 拆開 loading 與 error ③ ~~9 處~~ **10 處** `.when(error:)` 吞錯誤分兩類處理 ④ 桌面歌詞子視窗補「無歌詞」空狀態 | S–M | 無 |
| ~~**5b** Design token~~ **已完成** | `AppSpacing`(4/8/12/16/24/32) + `AppLayout`（獨立成 `lib/core/constants/app_layout.dart`，不 import Flutter，資料層才共用得到面板界限）+ `app_theme.dart` 的 `lightTheme`/`darkTheme` 收成一個私有建構器（~~85~~ **實際 −97/+27 行**）。~~+ `AppMotion`~~ **不建**，見 04-D11 | S | 無。**是 5c/5d 的前置** |
| ~~**5c** 面板與斷點~~ **已完成** | 面板改「像素下限 320 + 比例上限 40% + 24dp spacer 含 drag handle」；~~預設 `min(412, 視窗寬/4)`~~ **不需要**（渲染期的比例夾擠已經等價，見 §6.11）；斷點補 840 / 1600，`WindowClass` 與 `columnsFor` 分開 | M | **Phase 3c**（持久化欄位） |
| ~~**5d** 播放頁 P-A~~ **已完成** | 門檻改成 `WindowClass.expanded && height >= 520`；比例隨「有無歌詞」變（`lyricsPaneHasContentProvider`）；窄版封面補 `AppLayout.playerCoverMax` | S–M | 5b |
| ~~**5e** 導覽~~ **已完成** | 底部導覽 6 → 5，「設定」到導覽軌底部（`medium` 以上）＋首頁捲動內容頂端（`compact`） | S | 無 |
| ~~**5f** 無障礙~~ **已完成（縮到兩項）** | ① `mini_player.dart` 的手刻 seek bar 包 `Semantics(container:, slider:)` ~~② `semanticFormatterCallback` ③ 27 個缺 tooltip 的 `IconButton`~~ **兩條在開工時已經不成立**（§6.10）④ 一條 `meetsGuideline` 冒煙測試 | S | 無 |
| ~~**5g** 錯誤呈現~~ **已完成** | `ToastService` / `ErrorDisplay` 入口加 `userMessageFor(Object e)`，把已知例外映射成 i18n、未知的統一並把原文寫進 log（~~現在 9 個檔~~ **實際 33 個檔、約 54 個呼叫點**把 `e.toString()` 直接顯示給使用者） | ~~M~~ **L** | 無 |

**驗收**：
- **實機（Android 模擬器，手機 + 1280dp 平板橫向 + Windows 三種尺寸）**：
  1280dp 平板點一首歌播放後，首頁排行榜仍然是 3 個音源（現況會掉到 2 個）。
- Windows 1700dp 把面板拖到上限，首頁排行榜不變。
- 重啟 app 後面板寬度／展開狀態保持。
- TalkBack 可以操作迷你播放器的進度條。
- 新增一條迴歸測試：「視窗 1700 + 面板 500 → 內容區欄數」（這正是現在測不到的情境）。

---

### Phase 6 — 目錄結構重構（`features/`）

**目標**：取消 `services/` 與 `providers/` 兩個頂層目錄，合併為 `features/`，並用一條可 `rg` 的
機械規則取代已經漂移失效的散文規則。
**涉及模組**：移動 124 個檔案（`services/` 84 + `providers/` 40）+ 約 80 個檔案改 import + `test/`。
**依賴**：**必須等 Phase 1 / 4 / 5 的程式碼變動穩定下來**。
**規模**：**M**（純 rename/move，零行為變更；但改動面大）。

順序（tracer bullet，每一步一個 commit）：

```text
6.0  把相對 import 統一為 package:fmp/...        （獨立 commit，獨立驗證）
6.1  只搬 download（13 檔）                       ← 驗證 pattern 與 lint 規則
6.2–6.4  逐 feature 搬，每 1–2 個 feature 一個 commit
6.5  拆單檔目錄 + 更新 7 份 AGENTS.md + 新增 .claude/rules/ ×6 薄路由檔
```

**機械規則（寫進 `AGENTS.md` 與 CI）**：

```bash
# 在 lib/features/ 底下，只有 *_providers.dart 允許 import flutter_riverpod
rg -l flutter_riverpod lib/features | rg -v '_providers\.dart$'   # 必須為空
```

**⚠️ 本輪新查到的成本因子**：**179 個測試檔裡有 41 個（23%）在字串層引用 `lib/` 的路徑**
（`rg -l "'lib/" test/`）。這些測試會在檔案搬動時全部變紅，即使行為完全正確。
而 Phase 3e（備份守門測試）與 Phase 5g（靜態規則測試）都會**再增加**這類測試。

**因此需要一條跨 Phase 的紀律**（建議寫進 `test/` 的 AGENTS.md）：

> 新增的原始碼掃描型測試，路徑必須來自一個集中的常數（例如 `test/support/source_paths.dart`），
> 不得在測試檔內硬編 `'lib/ui/pages/...'` 字面值。

**驗收**：`flutter analyze` 全綠（Dart 無動態 import，這是完整驗證）；每個 commit 結束 repo 可跑；
`git revert` 單一 commit 即可回退。

---

### Phase 7 — 授權與揭露（可獨立，任何時候）

> **✅ 已於 2026-09-07 執行完畢。** 執行紀錄與四處與計畫不符的地方見 §6.14：
> `CHANGELOG.md` 不存在所以 7.3 的那一項作廢；驗收改由 `LicenseRegistry`
> 併進現有的「開源授權」頁而不是另做一頁；依賴數是 207 不是 206；
> 7.2 沒有照譜系 A 抄，改寫成用標準庫的獨立表達（89 行 → 44 行，
> golden 向量與 2000 組隨機交叉比對證明輸出逐字元不變）。

**目標**：補上現況即已缺的第三方授權揭露，並切換到 MIT。**（2026-09-02 已定案：切 MIT + 補 NOTICE）**
**規模**：MIT 本身全部是 **S**；`NOTICE` 是 **M**。
**順序是固定的**：7.1 → 7.2 → 7.3。7.2 是 7.3 的**硬前置**。

| 步 | 內容 | 成本 |
|---|---|---|
| 7.1 | **`NOTICE` / `THIRD_PARTY_LICENSES.md`** —— 涵蓋三件互相獨立的事：① libmpv / FFmpeg 的 LGPL-2.1/3-or-later（動態連結；讀原始建置腳本確認 `mpv.cmake` 是 `-Dgpl=false`、`ffmpeg.cmake` 是 `--disable-gpl --disable-nonfree --enable-version3`，**是 LGPL 不是 GPL**）② 協定常數來源（含 `SocialSisterYi/bilibili-API-collect` 的 **CC BY-NC 4.0**）③ 206 個 Dart 依賴的授權清單 | M |
| 7.2 | **重寫 `qq_music_sign.dart`**（約 30 行），照譜系 A（`AynaLivePlayer/miaosic`，**MIT**）的表達。它是全 repo 唯一一處判定為「結構明顯搬運」的程式碼 —— 不只常數相同，「跳過 t2 先算 t3 的順序」「手寫 base64 的 6 次迴圈 + 第 5 次特判」「連 `=` 都一起漏掉的過濾集」都與無可用授權的譜系 B 一致，這些不是演算法必然，是特定作者的表達選擇 | S |
| 7.3 | `LICENSE` 換 MIT 全文 + `README.md` / `README.zh-Hant.md` 各 2 處（badge + License 段）+ CHANGELOG 記一筆。**不需要**做檔頭清查（`rg "SPDX-License-Identifier"` 全庫 0 命中）、**不需要**改 pubspec（`publish_to: 'none'` 沒有 `license:` 欄位）、GitHub 的 license 標記會在 push 後自動重新索引 | S |
| 7.4 | 著作權人書面同意（就是你本人，留在 commit message 或 issue 裡備查）；順手在 `netease_crypto.dart` / `qq_music_sign.dart` 頂端加一行「參考公開逆向工程協定重新實作」的說明註解 | S |

> `netease_crypto.dart` 與 `bilibili_crypto.dart` **不需要動**（03 §D14）。

**驗收**：`showLicensePage()` 之外另有一個可從設定頁開啟的第三方授權頁；`rg "SPDX-License-Identifier"` 仍為 0（不需要逐檔加）。

---

### Phase 8 — 平台擴展 —— **已決定不做（2026-09-02）**

**決定：只做 Android + Windows。** Linux / macOS / iOS 全部不排期。

**但有一件事保留下來**：50 處 `Platform.isWindows` 重新分類成「真 Windows 專屬」與「桌面通用」。
這**不是**為了將來擴平台才做的 —— 它現在就有價值：`lib/core/utils/platform_utils.dart` 已經有
`isDesktopPlatform`，卻只用在約 9 處純 UI layout 判斷，所有系統整合功能都繞過它直接寫
`Platform.isWindows`（托盤、快捷鍵、自啟、SMTC 5 處、桌面歌詞、更新、字型 fallback）。
這正是 02 P1-7 說的抽象洩漏，Phase 4B 的 `NowPlayingPublisher` 會收掉其中 8 處。**這件事留在 Phase 4/6 內。**

**同時建議順手處理**：21 處指向不存在平台的分支（iOS 10 / Linux 6 / macOS 5，目前一行都跑不到）。
它們既不是資產也不是負債，但**會讓「還缺什麼」的判斷失真** —— 看起來已經支援了。
既然決定不擴平台，這些分支應該刪掉或加註「刻意保留的預留分支」。

**留檔供將來重新評估**（03 §4.5 的完整盤點仍然有效）：Linux 有 2 個硬阻塞（`flutter_inappwebview`
無 Linux 實作，而 YouTube 只有 WebView 一種登入方式；媒體控制要接 `audio_service_mpris`），
L（14–22 人日）；macOS 套件層硬阻塞 **0 個**，M（8–14 人日），門檻是 Mac 硬體 + Apple Developer $99/年；
iOS 技術上最簡單但 App Store Review Guideline 5.2.3 直接點名「download media from third-party
sources」，同類的 Spotube 從未上架。

---

### Phase 9 — 音源插件化（**已定案要做，且形狀已釘死**）

**你的動機是三個都要**：新增內建源更容易 ＋ 讓使用者自己加源 ＋ 降低法律風險。
並且指定了產品形狀：**FMP 提供一份提示詞，使用者把它丟給自己本地的 agent，由 agent 生成插件。**

這個形狀改變了三件事的優先級：**介面的穩定性**從「好事」變成「產品前提」；
**驗證套件**從「可選」變成「插件生成流程的一部分」；**沙箱與信任模型**從「之後再說」變成「不能省」。

#### 9.1 前置（已完成 1/3，剩下 2/3）

| 阻塞 | 狀態 | 內容 |
|---|---|---|
| `ranking_cache_service.dart` 的 49 處硬編碼 | ✅ **已完成**（`583eef90`） | 改成 `for (final sourceType in manager.registeredSourceTypes)`，該檔從約 500 行降到 288 行 |
| `SourceType` 封閉 enum | ✅ **已完成**（`0b93e61d`） | 換成 `SourceIds` 字串常數，i18n 走 slang flat map 有 fallback。磁碟格式逐位元不變，不需要 migration —— 「併進 3c 才沒有邊際成本」的理由是錯的，見 §6.4 #2 與 ADR 0001 |
| `Settings` 每源具名欄位 | ✅ **已完成**（`8ffa7d4f`） | 交付的是 `List<SourceSettingsEntry>`（`@embedded`）而不是 `Map` —— Isar 的 `@embedded` 只支援 `List`。schema v1 → v2，舊欄位只搬不刪所以降級無損。備份格式同步到 v4 |

做完這兩件事，**「新增第四個內建源」從「改 20 個檔案」變成「加一個 adapter」——
這個收益不需要真的做外掛化就先拿到了**（你的動機一，提前兌現）。

#### 9.2 執行環境：三選一，而且沒有兩全的選項【事實】

| 路線 | 已驗證的能力 | 沙箱 | 對「AI 生插件」的影響 |
|---|---|---|---|
| **`flutter_js`（QuickJS）** | **spike 實跑通**：fetch/XHR 橋接回 Dart（452ms 搜尋 / 384ms 取流）；**插件自帶 CryptoJS 4.2.0 可產出與 .NET 逐字元相同的 eapi params**（0.47ms/次，60KB）；Windows 桌面不需額外建置；Android 上 JS 行為與沙箱邊界與 Windows **完全相同**，QuickJS `.so` 每 ABI 僅 0.72–1.05 MB | **無正式權限模型**，但 QuickJS globals 是乾淨的（`require`/`process`/`std`/`os`/`WebAssembly` 全 undefined） | **最適合**：JS 是 AI 生成品質最高的語言，且能力上限足以覆蓋 Netease 的 search + getAudioStream（已實測） |
| **`dart_eval`** | 0.8.5（2026-05），⭐400 | **唯一有正式權限沙箱**（`runtime.grant()` + Filesystem/Network/ProcessRun） | **不支援 extension methods / generators / mixins，官方不建議載入外部 pub 套件** —— 直接卡死 DASH XML 解析與 HTTP，除非全部由宿主注入 |
| **WASM（`wasm_run`）** | Android + Windows 都支援 | 天然沙箱 | **插件必須用 Rust/C/Zig 寫** —— 與「讓使用者用 AI agent 生插件」的目標**直接衝突** |

**【建議】走 `flutter_js`，但要據實記錄兩筆債**：
1. **`flutter_js` 0.8.7 在 Android 上開箱即壞** —— `android/build.gradle:34` 寫死 `jvmTarget = 1.8`、
   `:5` 是 Kotlin 1.7.20，Flutter 3.47 另警告 KGP 未來會被拒。**要 fork 或送 upstream PR，這是排期時就要算進去的成本。**
2. **上游停滯**（0.8.7 約 2026-01）是本路線最大的風險。

**沒有兩全的選項**：`flutter_js` 能力完整但沒有正式沙箱；`dart_eval` 有沙箱但不能用 pub 套件。
選 `flutter_js` 就意味著**沙箱要靠「宿主注入的能力面」而不是靠 runtime 權限模型**來收斂 ——
插件拿不到 `dart:io`，只能透過宿主給的 `http.get/post`（走 `SourceHttpPolicy`）。這正好是 9.3 的設計。

#### 9.3 介面草案（約 10 個必實作方法 + 6 個注入能力，Mihon `HttpSource` 同級）

```text
插件必須實作（對應生產真正用到的 8 個 capability）：
  meta:            { id, name, iconUrl, version, minAppVersion }
  urls:            parseTrackId(url) / isPlaylistUrl(url) / parsePlaylistId(url)
  search(query, page, pageSize)              -> SearchResult
  getTrackInfo(id, auth)                     -> Track
  getAudioStream(id, {cid, quality, auth})   -> AudioStreamResult
  getTrackDetail(id, auth)                   -> VideoDetail        [可選]
  getRanking(request)                        -> List<Track>        [可選]
  parsePlaylist(url, page, auth)             -> PlaylistParseResult[可選]
  mapError(rawResponse)                      -> SourceErrorKind

宿主注入給插件（插件不得自帶）：
  http.get/post(url, headers, body)          ← 走 SourceHttpPolicy，插件不碰 cookie 原文
  crypto.aesEcb / aesCbc / rsaOaep / sha1 / md5
  webviewLogin({url, successCookieNames})    ← 回傳 opaque token，插件看不到憑證
  storage.get/set(key)                       ← 命名空間隔離
  log.debug/warn
```

**必須留在宿主、不能下放的**（02 §7.3 逐條取證）：Netease eapi/weapi 加密、Bilibili RSA-OAEP
correspondPath、YouTube SAPISIDHASH、WebView 登入（platform channel）、憑證持久化。
**其中 `youtube_explode_dart` 的 signature cipher / n-sig 解密是唯一無法拆解的整體依賴** ——
所以 **YouTube 明說留在宿主，不進插件系統**：那段解密會隨 YouTube 改版而變，而 02 §3.a 顯示
**它現在就已經在退化**（P0-3，每次播放 20 秒 + 退化成含視訊的 muxed 串流）。交給插件作者維護
只會讓壞掉時沒人能修。

#### 9.4 「AI 生插件」流程要交付什麼

這是你指定的形狀，它有三個**不能省**的產出物（02 §7.3 的兩條但書就是在講這個）：

| 產出物 | 內容 | 為什麼不能省 |
|---|---|---|
| **提示詞範本** | 完整的注入能力簽章（不是摘要，是逐字簽章）＋ 介面契約 ＋ 明確禁止事項（不得 `import` 任何套件、不得碰 `dart:io`/`fetch` 以外的網路） | 沒有完整簽章，AI 生出來的插件會自己 import 不存在的套件。這是實測過的失敗模式 |
| **3 個真實範例插件** | 三個內建源各一份的「插件版」實作 | AI 靠 few-shot 對齊 API 形狀；三個範例同時也是介面是否真的夠用的證明 |
| **一組可跑的驗證套件** | 對插件跑 schema 驗證 + 契約測試（search 回得出結果、getAudioStream 回得出可播 URL、mapError 覆蓋已知錯誤碼），**在載入前就跑** | 使用者不會讀插件原始碼。驗證套件是「AI 生的東西能不能用」的唯一把關點 |

**額外的風險（要在 UI 上誠實揭露）**：AI 生成的插件會透過注入能力接觸到帳號憑證的**使用**
（不是原文 —— `webviewLogin` 回 opaque token、`http` 走 `SourceHttpPolicy`）。
即使如此，一個惡意或出錯的插件仍然可以把搜尋結果導到任意 URL。**信任模型抄 Mihon**
（repo 級簽章金鑰 + 逐版本 TOFU + 可撤銷），不抄 Spotube／Mangayomi 的「靠使用者自己小心」——
FMP 的插件風險等級比漫畫源高。

#### 9.5 排期與依賴

```
Phase 3c  ─► SourceType 字串化 + Settings 每源欄位 map 化   （併進批次 schema 變更）
   │
   ▼
Phase 9.1 ─► 內建三源改走統一介面（不改行為，只改形狀）      成本 M
   │           ↳ 此時「新增第四個內建源」的收益已兌現
   ▼
Phase 9.2 ─► flutter_js 整合 + Android 的 jvmTarget/KGP 修復（fork 或 upstream PR）  成本 M
   │
   ▼
Phase 9.3 ─► 介面凍結 + 3 個範例插件 + 驗證套件 + 提示詞範本  成本 M–L
   │
   ▼
Phase 9.4 ─► 信任模型（簽章 / TOFU / 撤銷）+ 插件管理 UI      成本 M
```

**驗收**（每一步都可執行）：
- 9.1：`rg "SourceType\.(bilibili|youtube|netease)" lib/` 在 registry 之外零命中；三源行為零變化，測試全綠。
- 9.2：Android 與 Windows 各跑一次 QuickJS 內的 Netease search + getAudioStream，結果與內建 adapter 逐欄位相同。
- 9.3：把提示詞丟給一個乾淨的 agent，生出的插件**通過驗證套件且能實際播放一首歌** —— 這是整個 Phase 的唯一真正驗收。
- 9.4：安裝一個簽章不符的插件會被拒絕；撤銷一把金鑰後既有插件停用。

#### 9.6 仍需你拍板的一項

**「出廠空殼」要不要做？** 這是「降低法律風險」這個動機**唯一有效的措施**，而它是產品決策：
app 出廠不附任何插件、不內建任何官方 repo URL，新使用者必須自己貼上第三方 repo 才能用。
代價是新使用者的第一次體驗會是一個空的 app。
**折衷選項**：三個內建源維持內建（它們不是插件），插件系統出廠不帶任何 repo URL ——
這樣既保留開箱可用，又讓插件生態在架構論述上與主 repo 分離。**我傾向這個折衷。**

---

### 3.2 里程碑與可發版點

| 里程碑 | 包含 | 使用者感受到什麼 | 累計規模 |
|---|---|---|---|
| **M1** | Phase 0 + 1.1–1.4 | 播放明顯變快（每次省 1.25–1.74s）、曲間靜默減半、幾個看得到的文案 bug 修好 | S–M |
| **M2** | Phase 1 全部 + 5a | 網路差時不再無限轉圈也不再空放；平板上不再掉內容 | M |
| **M3** | Phase 2 + 3a + 3b + 3c | 使用者感受不到（除了面板寬度會被記住）；但 16KB 對齊、Riverpod 3、面板持久化都到位 | L |
| **M4** | Phase 4 + 5c/5d/5e | Windows SMTC 不再有死鍵；面板與播放頁在各種尺寸下都合理 | L |
| **M5** | Phase 5f/5g + 3d/3e + 7 | 讀屏可用、錯誤訊息可讀、授權切 MIT 且揭露補齊 | L |
| **M6** | Phase 6 + 9.1 | 使用者感受不到；但目錄結構收斂完成，且「新增內建源」的成本降一個量級 | M–L |
| **M7** | Phase 9.2–9.4 | **使用者可以拿一份提示詞讓自己的 agent 生插件**，裝進 FMP 播放 | L |

> Phase 8（平台擴展）已決定不做，不佔任何里程碑。

---

## 4. 七＋五個項目的一段式摘要

### 4.1 多平台

**現況**：只有 `android/`（26 檔）與 `windows/`（15 檔），皆為 `flutter create` 模板；但 `lib/` 已有
21 處指向不存在平台的分支（iOS 10 / Linux 6 / macOS 5），看起來像已支援其實一行都跑不到。
音訊層已經抽象正確（`AudioRuntimePlatform` + 兩個 `FmpAudioService` 實作，正是 Harmonoid 的模式），
但**系統整合層全部寫死 Windows**（50 處 `Platform.isWindows`：托盤、快捷鍵、自啟、SMTC、桌面歌詞、
更新、字型 fallback），而底層套件（`tray_manager` / `window_manager` / `desktop_multi_window`）本來就支援 Linux/macOS。
**方案**：先做「50 處 `Platform.isWindows` 重新分類」這個共同前置（它讓 macOS 的重構工作壓到 0.5–2 人日），
再依有無 Mac 決定 Linux 先還是 macOS 先。Linux 有 2 個硬阻塞（inappwebview 無 Linux → YouTube 登入
要選 `webview_cef` / `desktop_webview_window` / 降級成匿名播放；媒體控制要接 `audio_service_mpris`），
macOS 硬阻塞為 0。
**✅ 已定案（2026-09-02）：只做 Android + Windows，Phase 8 從路線圖移除。**
但那個共同前置**保留在 Phase 4/6 內**，因為它現在就有價值 —— 它就是 02 P1-7 說的抽象洩漏
（上層用 `Platform.isX` 而不是介面上的能力查詢），Phase 4B 的 `NowPlayingPublisher` 會收掉其中 8 處。
**順手處理**：21 處指向不存在平台的分支（iOS 10 / Linux 6 / macOS 5）目前一行都跑不到，
卻讓「還缺什麼」的判斷失真 —— 既然不擴平台，應該刪掉或明確註記為刻意保留。
**已無待決策點。** 03 §4.5 的完整平台盤點留檔，將來要重新評估時直接用。

### 4.2 音源插件化

**現況**：抽象品質已經不錯（11 個窄 capability 介面、`SourceManager` 幾乎無 switch），問題在
registry **外圍**的硬編碼。三個阻塞裡**最大的一個已經解掉**（排行榜快取 49 處硬編碼 → registry 迴圈，
`583eef90`，該檔從約 500 行降到 288 行）；剩下 `SourceType` 封閉 enum 與 `Settings` 每源具名欄位。
技術路線已經實測過：`flutter_js`(QuickJS) 原型跑通（Windows 桌面不需額外建置、沙箱乾淨、
插件自帶 CryptoJS 可產出與 .NET 逐字元相同的 eapi params），但 0.8.7 在 Android 上**開箱即壞**
（Kotlin 1.7.20 + jvmTarget 1.8），是一筆維護債。
**✅ 已定案（2026-09-02）：三個動機都要，且產品形狀是「提供一份提示詞，使用者交給自己本地的 agent 生插件」。**
**方案**：四步（詳見 Phase 9）—— 9.1 內建三源改走統一介面（前置的 `SourceType` 字串化與
`Settings` map 化併進 Phase 3c，邊際成本近零）→ 9.2 整合 `flutter_js`/QuickJS 並修掉它在 Android 上
開箱即壞的 `jvmTarget 1.8` / Kotlin 1.7.20 → 9.3 **凍結介面，交付「完整注入能力簽章 + 3 個範例插件 +
可跑的驗證套件 + 提示詞範本」四件套** → 9.4 信任模型（抄 Mihon 的 repo 級簽章 + 逐版本 TOFU + 可撤銷）。
**YouTube 明說留在宿主**（`youtube_explode_dart` 的 signature cipher 是唯一無法拆解的整體依賴，
而它現在就已經在退化）。
**要據實說的一件事**：三個動機裡「降低法律風險」**技術架構解不掉** —— Tachiyomi 案裡 Kakao 的
法律通知連 app 本體與所有 fork 都要求刪除，儘管 extension 早在獨立 repo；有效措施是「出廠空殼」，
那是產品決策。
**剩餘決策點**：出廠空殼要做到什麼程度（我傾向折衷：三個內建源維持內建，插件系統出廠不帶 repo URL）。

### 4.3 播放核心

**現況**：管線結構是對的（5 個協作者邊界清楚），但缺三個機制，其中兩個仍然開著。
① **串流解析零快取**：`resolvePrimary()` 從不讀 `track.audioUrl`，預取的結果寫進一個馬上被丟掉的
`copy()`，實測同一首歌連播三次每次都重打 API（1.25s / 1.42s / 1.43s）。② **載入路徑無任何逾時上限**：
零位元組串流下 Android 阻塞 37.7 秒才拋、Windows **6.1 秒就「成功」返回**（`duration: null`、
`playing: true`）然後直接跳歌。③ **型別化錯誤 —— 已完成**（`PlaybackEndReason` 已落地，
`_isStringNetworkError` 全庫零命中，issue #41 隨之修好）。另外 `audio_provider.dart` 從 2,998 行
長到 **3,429 行**，god class 沒有停止生長。
**方案**：Phase 1 補齊 ①②（tracer bullet，每步獨立可驗），Phase 4 按 E→B→D→C 把責任叢集搬出去，
目標 400–800 行。**雙後端保留不統一**（media_kit 在 Android 有已知的 dispose 效能問題、
每 ABI +2.9–3.1MB、Namida 這個最接近的對照組音訊也走 just_audio），但把平台知識從 `Platform.isX`
改成介面上的能力查詢。
**建議**：**Phase 1 是整份路線圖裡投報比最高的一段** —— 成本 M，使用者立刻有感。
**決策點**：D1（逾時數值）與 D2（逾時後行為）**已於 Phase 1 定案並實機複驗**，見 §6.2。
D3（位元組快取）與 D4（just_audio 升級）**已於 2026-09-02 重新查證並定案**，見 §5.2 對應列。

### 4.4 MIT 授權

**現況**：`LICENSE` 是 GPL-3.0；貢獻者**只有一個人**（`ivanspwong@gmail.com`，`imoR`/`1morr` 是同一個
email 的兩個 display name；bot 的 54 個 commit 全是 README 版本號替換）；206 個 Dart 依賴逐一讀 pub cache
的 LICENSE，**零 GPL / LGPL**；唯一的 copyleft 面是 media_kit 在 Windows 動態連結的 `libmpv-2.dll`，
而讀原始建置腳本確認是 `-Dgpl=false` / `--disable-gpl --disable-nonfree --enable-version3`
—— **是 LGPL 不是 GPL，且是動態連結**，MIT 可以合法分發。
**方案**：三步，全部 S ——（1）著作權人書面同意（就是你本人，留在 commit message 備查）
（2）`LICENSE` + `README` ×2 + CHANGELOG（3）**先重寫 `qq_music_sign.dart`**（全 repo 唯一一處判定為
「結構明顯搬運」的程式碼：不只常數相同，連「跳過 t2 先算 t3」「手寫 base64 的 6 次迴圈 + 第 5 次特判」
「連 `=` 都一起漏掉的過濾集」都與無授權的譜系 B 一致；同演算法有一支 MIT 實作可照著重寫，約 30 行）。
mpv 自己走過 GPLv2+ → LGPLv2.1+ 的 relicensing（2015–2017，逐一檢視 44,000 個 commit）；
FMP 與那些案例的差異是量級的 —— 那個流程裡最貴的環節（數十到數百位著作權人）在本案完全不適用。
**✅ 已定案（2026-09-02）：切 MIT，並一併補 `NOTICE`。**
順序固定為 7.1（`NOTICE`）→ 7.2（重寫 `qq_music_sign.dart`）→ 7.3（`LICENSE` + README ×2 + CHANGELOG）。
**7.2 是 7.3 的硬前置** —— 那是全 repo 唯一一處判定為「結構明顯搬運」的程式碼，而它的來源譜系
沒有可用授權。成本 S（約 30 行，有 MIT 實作可照著寫），低到不值得為此賭。
**已無待決策點。**

### 4.5 UI 重設計

**現況**：骨架是對的（`ResponsiveScaffold` 三段路由、`ImmersivePlayerScaffold`、`ErrorDisplay` /
`LoadingPlaceholder` / `ToastService` 共用層都存在且設計正確），問題是**採用率**（16 用共用 vs 17 手刻、
10 用 vs 36 手刻）而不是缺件。真正的缺陷是點狀的：一行 `maxWidth` 語意錯置導致「1280dp 平板一播歌
就少掉一個音源」、三個 State 欄位沒進 `Settings`、一個 500dp 常數、少一層 840dp 斷點、
播放頁把 58% 面積固定給歌詞（六個成熟對照組裡沒有任何一個這樣做）。無障礙近乎為零
（121 個 UI 檔裡 `Semantics(` 出現 2 次、`semanticLabel:` 0 次、`textScaler` 全 `lib/` 0 次）。
**方案**：Phase 5，順序是 5a 止血 → 5b token → 5c/5d 版面 → 5e/5f/5g。
首頁選方案 A（收斂重複的播放狀態），播放頁選 P-A（門檻改成寬＋高、比例隨有無歌詞變）。
**「可切換佈局模式」明確不做** —— 那會把 shell 複雜度乘以模式數，且違反「不為想像中的未來需求加抽象層」。
**建議**：**5a 值得立刻做（一行修法消滅一個 P0）**；其餘照順序。
**決策點**：D1 面板上限模型、D2 補 840dp 後預設收起還是展開、D3「設定」搬去哪、
D4 首頁方案、D9 播放頁方案（**D4 與 D9 必須一起決定** —— 首頁方案 C 與播放頁 P-C 互斥）。

### 4.6 設計語言切換（Material ↔ 液態玻璃）

**現況**：先更正一個前提 —— 現況**不是**「Material 3 + dynamic_color」，`dynamic_color` 是死依賴
（`rg` 在 `lib/` 零命中），實際是 `ColorScheme.fromSeed` + 9 個寫死的預設色。token 層缺四層：
沒有間距 scale（260 個 `EdgeInsets` 字面值）、沒有版面尺寸 token、沒有動效曲線 token、
`app_theme.dart` 的 light/dark 是兩份逐字重複 85 行的巨大字面值。
**方案**：做 token 層的 1–3（`AppSpacing` + `AppLayout` + 元件 theme 抽取 + `AppMotion`），**不做**第 4 層
（字體語意層，只有真的要做第二套視覺語言時才必要）。做完之後「一套風格 = 一個 `ThemeExtension`
+ 一組值 + 可選的自訂元件建構器」，要改的是 15–20 個自繪/自組元件、1,500–2,500 行。
**建議**：**做 1–3（它們本身就有價值，且是 5c/5d 的前置），不引入液態玻璃套件。**
理由是卡在套件不是卡在架構：`liquid_glass_renderer`（885 likes，社群事實標準）最新版是
**0.2.0-dev.4，9 個月沒發新版**，pub 宣告支援平台只有 Android / iOS / macOS，
README 第一句是「EXPERIMENTAL - USE WITH CAUTION」—— 而 FMP 兩個目標平台之一是 Windows。
而且 token 層買到的是「換得動」，不等於「換了好看」：第二套視覺語言的實際設計工作不在這個估計裡。
**決策點**：現在放棄，還是設一個等待條件（該套件發出第一個 stable 且 pub 平台列表加上 Windows）。

---

### 補充項目（四份報告點出、但不在你列的七項裡）

### 4.7 【補充】依賴天花板 —— 這是整份路線圖裡最高槓桿的一項

**現況**：`isar_generator 3.1.0+1` 的約束是 `analyzer: ">=4.6.0 <6.0.0"`，把整個專案釘在
**analyzer 5.13.0 / build 2.4.1 / source_gen 1.5.0**（analyzer 目前最新 14.1.0），
`build_resolvers` 與 `build_runner_core` 的最新版已標 **(discontinued)**。
`dart pub outdated` 的 **Resolvable** 欄位證實：就算改 pubspec 也拿不到更新。
而且實測 `riverpod_annotation ^3.0.0` + 現行 `isar_generator` 直接 version solving failed
—— **換掉 Isar 是升 Riverpod 3 的前置條件**，不是兩件獨立的事。
**方案**：Phase 2。硬性順序是 slang 3.32→4.19 先、`isar_community` 後（兩者的依賴鏈無法繞過）。
**建議**：**這件事該排在 Phase 1 之後、其他所有結構性工作之前。** 資料遷移成本實測為零
（11 collection 生成碼逐字相同、schema id hash 全同、真實 DB 副本原地讀寫成功）。
**決策點**：什麼時候做（見 §5 Q1）。

### 4.8 【補充】資料庫治理 —— 一顆會隨使用時間自己引爆的雷

**現況**：`Isar.open(maxSizeMiB: 64)` 是官方預設 1024 的 **1/16**，而全庫**沒有任何一行處理「寫不進去」**
（`rg "maxSizeMiB|Database full|IsarError"` 除了那行設定本身零命中）；`PlayHistory` / `Track` /
`LyricsMatch` 都沒有自動保留策略。到達上限後每一次 `writeTxn` 都會拋，使用者看到的會是散落各處、
互不相關的失敗（存不了播放歷史、加不進歌單、下載狀態寫不回去），**沒有任何一條訊息指向真正的原因**。
Immich 踩過一模一樣的坑（PR #17372 把上限提到 2GiB）。同時「migration」不是 migration ——
全庫搜不到 `schemaVersion`，靠 `_hasLegacy*Signature` 這種「N 個欄位同時長得像預設值」的
不可證偽判斷式猜版本。
**方案**：Phase 0e 把 `maxSizeMiB` 調高（mmap 上限不是預先配置的磁碟空間，調大幾乎沒有代價）+
補明確的錯誤分類；Phase 3b 導入 `schemaVersion`。
**建議**：**`maxSizeMiB` 現在就改**，它是一行。`schemaVersion` 排 Phase 3b。
**決策點**：`PlayHistory` 要不要加保留上限 —— 這會**主動刪掉使用者資料**，是產品決策不是技術決策。

### 4.9 【補充】無障礙 —— 唯一有外部下限的項目

**現況**：`lib/ui` 121 檔裡 `Semantics(` 出現 **2 次**（都在標題列）、`semanticLabel:` **0 次**、
`textScaler` 在整個 `lib/` **0 次**、`test/` 裡 `meetsGuideline` **0 次**；96 個 `IconButton` 有 27 個沒 tooltip；
**迷你播放器的進度條是手刻 `GestureDetector`，對讀屏軟體完全不存在**；狀態列圖示在部分畫面
對比只有 **1.05:1**（已量測）。
**方案**：Phase 5f，按優先序做前 3 項 + 一條冒煙測試，不一次做完。
**建議**：**做最小可行集就好，但要做。** 迷你播放器 seek bar 是唯一「完全無法操作」的控制項，
它應該進 Phase 0c 而不是等 Phase 5。字級**建議不鉗制**（會傷害真正需要放大的使用者），
改為修掉三處固定高度。

### 4.10 【補充】可觀測性 —— 最需要 log 的情境恰好拿不到 log

**現況**：`AppLogger` 的 log **只在記憶體**。而 `runApp()` 之前的任何例外（issue #37）會導致
無視窗、無提示 —— 使用者連 log 頁面都打不開。`AppLogger.setMinLevel()` 全 repo 零呼叫點。
`StreamResolutionService` / `AudioStreamManager`（整條路徑最慢的一段）**一行 log 都沒有**。
另一方面，本專案的觀測工具其實很強：VM Service 的 `evaluate`（走 WebSocket）可以倒出毫秒級 log、
對活物件呼叫私有方法、在進程內起獨立後端做受控實驗；`dart:io` HTTP profiling 在 profile build 下
完全可用並給到逐階段時間軸 + 完整 header/body。
**方案**：Phase 1.8 補解析路徑的三行 log；Phase 3 順帶處理 log 落盤（要處理輪替、大小上限、
匯出時的隱私）。
**建議**：**Phase 1.8 現在就做**（它讓 Phase 1 的其他項目有量測基準）。log 落盤是決策點。

### 4.11 【補充】發版節奏 —— app 內更新對使用者靜默過期

**現況**：最新 release 是 **v1.9.1（2026-07-16）**，距今 47 天，期間 main 持續有
`fix(audio)` / `refactor(sources)` / `refactor(media)` 合入。app 內的更新檢查打的是 GitHub Releases API，
**且只在使用者手動觸發**（`checkForUpdate()` 全 repo 只有一個呼叫端，沒有 Timer、沒有啟動時檢查）。
**建議**：把 §3.2 的 **M1（Phase 0 + Phase 1 前半）當成下一個 release 的內容** ——
它剛好是「使用者立刻有感 + 全部低風險 + 全部可逆」的組合。之後每個里程碑發一版。

---

## 5. 決策清單

> 四份報告合計列出約 30 個決策點。以下按「會不會改變路線圖的內容」分成兩層。
> **第一層（4 題）本輪直接問**；**第二層在對應 Phase 開工時再答**，未答則照「我的建議」執行。

### 5.1 第一層 —— 改變路線圖內容的（**已於 2026-09-02 定案**）

| # | 題目 | **你的決定** | 對路線圖的影響 |
|---|---|---|---|
| **A** | Phase 2（`isar_community` + slang 4）什麼時候做？ | **Phase 0/1 之後立刻做** | Phase 2 定位為 M3 的核心。Phase 3 解除封鎖，Riverpod 3 與 analyzer 生態一併解鎖 |
| **B** | GPL-3.0 → MIT 切不切？ | **切 MIT，並一併補 `NOTICE`** | Phase 7 的 7.2（重寫 `qq_music_sign.dart`）從「可選」升為 **7.3 的硬前置**。三步的順序固定為 7.1 → 7.2 → 7.3 |
| **C** | 平台範圍？ | **只做 Android + Windows** | **Phase 8 從路線圖移除**；但它的共同前置（50 處 `Platform.isWindows` 重新分類）**保留**在 Phase 4/6 內，它本來就對現有兩平台有價值（消滅抽象洩漏） |
| **D** | 插件化的動機？ | **三個都是** —— 新增內建源更容易 ＋ 讓使用者自己加源 ＋ 降低法律風險。且明確指定產品形狀：**提供一份提示詞，使用者把它丟給自己本地的 agent 生成插件** | **Phase 9 從「先不做」升為實際交付物**，並且形狀被釘死：介面必須小且穩定、必須附完整的注入能力簽章 + 範例插件 + 可跑的驗證套件、沙箱與信任模型變成必要而非可選。見改寫後的 Phase 9 |

> **關於 D 的一則據實說明**：三個動機裡，「降低法律風險」這一項**技術架構解不掉**。
> Tachiyomi 案的時間線顯示：Kakao 的法律通知要求刪除 app 全部版本與 GitHub 上所有 fork，
> **儘管 extension 早已在獨立 repo**；核心貢獻者數日內自願下架整個 org。對照組 Aniyomi
> 在 Sony 一次 DMCA 移除 200+ extension 後 **app 本體未下架** —— 兩案的差別在於
> **「出廠是否為空殼」**（Mihon 現行做法：app 出廠不附任何 extension、不內建任何官方 repo URL，
> 使用者必須自行貼上第三方 repo）。所以這一項的有效措施是一個**產品決策**（新使用者要自己找源才能用），
> 不是把程式碼搬到另一個 repo。**這個取捨列在 §5.2 的 Phase 9 決策裡，需要你另外拍板。**

### 5.2 第二層 —— 在對應 Phase 開工時再答

| Phase | # | 題目 | 我的建議 |
|---|---|---|---|
| 0 | 01-7 | 7 個死依賴要不要移除？（pubspec 算對外介面變更） | 移除，但 `intl` 先確認不是 `flutter_localizations` 版本解析所需 |
| 0 | 01-1 | `docs/adr/` 要不要真的用？ | **(a) 開始寫**：現成題材有三個（Isar 決策、`services/`+`providers/` 分層、Windows 音訊後端選型）。現況（引用一個 clone 後不存在的目錄）是最差的一種 |
| 0 | 01-2 | `docs/review/` 的定位？ | **(c) 進 repo 但明文禁止程式碼引用**。前兩代都在一個月內被刪，而 `*_phaseN_test.dart` 還在引用它們 |
| 0 | 01-6 | `analysis_options.yaml` 要不要收緊（開 `unawaited_futures`、移除 `exclude: test/**`）？ | 要。這是 37 處空 catch 的唯一機制解，且扣掉單一 demo 檔的 95 條 `avoid_print` 只剩約 50 條要清 |
| 1 | 02-D1 | 逾時預算 T1/T2/T3 | T1=8s（解析）/ T2=10s（開流）/ T3=20s（緩衝耗盡） |
| 1 | 02-D2 | 逾時之後做什麼？ | 先換 fallback 串流試一次，仍失敗才停下並通知（介於 Auxio 的「直接跳」與 Finamp 的 `maxSkipsOnError:0` 之間） |
| 1 | 02-D3 | 位元組快取走哪條路？ | **✅ 已定案（2026-09-02）：(c) 先只做 URL 快取，位元組快取延後到 Phase 4 之後。** 重新查證推翻了原本的成本假設，也找到了真正的阻礙 —— 見下方展開。**2026-09-07 補充：那個阻礙（「要接的介面正在被改」）已經消失** —— 介面定在 `setNextMedia` / `advancedToNext`（§6.13），可以重新評估 |
| 1 | 02-D4 | 升 just_audio 0.9.46 → 0.10.6？ | **⚠️ 前提敘述有誤，已更正（2026-09-02）：升級不是 gapless 的前提。** 兩個後端現在就有佇列 API —— 見下方展開。升級本身仍可做（0.10.x 有 open issue #1486，release build 無聲音），但它是「要不要」而非「必須先」，且**不要跟 Phase 2 混在一起** |
| 1 | 02-D7 | crossfade 要不要明確放棄並寫進文檔？ | 放棄並寫進文檔。四個對照專案裡三個明說不做 |
| 3 | 03-D2 | 導入 `Settings.schemaVersion`？ | 要。它把不可證偽的形狀猜測換成可測試的版本遷移 |
| 3 | 03-D3 | `maxSizeMiB` 調到多少？`PlayHistory` 要不要加保留上限？ | 調到 2048（Immich 的答案）。保留上限**先不做** —— 它會主動刪使用者資料，需要一個設定項與明確預設值 |
| 3 | 03-D4 | Riverpod 3 走方案 A 還是 B？ | **A（legacy import，2–4 人日）**。B 的一半工作量在兩個要拆的 god provider 裡，那屬於 Phase 4 |
| 3 | 03-D5 | repository 邊界收斂要不要做？ | 做，但只收前三大（63%）。全收是 L，投報比在後半段下降 |
| 3 | 03-D13 | 6 個死欄位要不要刪？ | 刪 5 個自訂色；`RadioStation.note` 二選一（刪，或把 UI 做出來 —— 電台備註是合理的功能） |
| 3 | 02-D6 | `Settings` 每源欄位改成 map？ | **✅ 已由決策 D 連帶定案：做，且併進 Phase 3c。** Phase 9 既然要做，這是它的前置；在 3c 的批次裡做邊際成本近零，單獨做要再付一整輪 migration |
| 3 | 03-D11 | log 要不要落盤？ | 要，但要處理輪替、大小上限、匯出時的隱私。排 Phase 3 尾 |
| 5 | 04-D1 | Detail Panel 上限模型 | 像素下限 320 + 比例上限 40% + 預設 `min(412, 視窗寬/4)` |
| 5 | 04-D2 | 補 840dp 之後預設收起還是展開？ | **預設收起**，讓使用者自己展開。這是可見的行為變更 |
| 5 | 04-D3 | 底部導覽 6→5，「設定」搬去哪？ | 最小版本：側欄底部（桌面）+ 首頁右上角（手機） |
| 5 | 04-D4 / D9 | 首頁方案 / 播放頁方案（**必須一起決定**） | 首頁 **A**、播放頁 **P-A**。C 與 P-C 互斥，兩者都先不做 |
| 5 | 04-D5 | Design token 做到第幾層？ | 1–3，不做 4 |
| 5 | **04-D11（新）** | 要不要建 `AppMotion`（曲線 + 時長配對）？ | **不建。** 前提只成立一半：時長早就是 `AnimationDurations`（19 個檔、36 處在用），`lib/ui` 只剩 17 處字面值而其中 10 處在同一個 debug 頁；曲線是 13 處、4 個值（`easeOutCubic` 5 / `easeInOut` 4 / `easeOut` 3 / `easeInCubic` 1）。4 個值 13 處不構成一個 token 層，而換掉曲線是使用者看得見的變更。真的要做的時候正確做法是採 Flutter 內建的 M3 `Easing`，不是再定義一組自己的 |
| 5 | **04-D10（新）** | `AppSpacing` 要不要全量遷移既有的 312 處 `EdgeInsets`？ | **只建常數，不掃舊碼。** 新程式碼與本來就要動的檔案改用它。全量遷移是零行為變更的巨大 diff，會把真正的改動淹掉，而 76% 的數值本來就落在 4/8/12/16/24/32；「換得動」靠的是 `AppLayout` 與元件 theme，不是把每個 `EdgeInsets` 都換掉 |
| 5 | 04-D6 | 液態玻璃現在放棄還是留條件？ | 放棄，但記下等待條件（該套件發出 stable 且 pub 平台加上 Windows） |
| 5 | 04-D7 | 字級鉗制要不要做？ | **不鉗制**，改為修掉三處固定高度 |
| 5 | 04-D8 | issue #36 的範圍 | 拆兩張，先做 #36a（成本差 2.5 倍） |
| 7 | 03-D14 | `qq_music_sign.dart` 重寫還是保留加 NOTICE？ | **✅ 已由決策 B 連帶定案：重寫**（切 MIT 的硬前置） |
| 7 | 03-D10 | Windows code signing + 更新離線簽章？ | 先不做（憑證費用 + 金鑰保管 + CI secret 輪替的持續成本）。記錄為已知風險 |
| 3/5 | 03-D9 | `youtube_stream_test_page` 的 Cookie 探測怎麼處置？ | (a) 加 `kDebugMode` gate，並把守門測試掃描範圍擴到 `lib/ui/` |
| **9** | **新** | **「出廠空殼」要做到什麼程度？**（這是「降低法律風險」動機唯一有效的措施，且是產品決策） | **折衷**：三個內建源維持內建（它們不是插件），**插件系統出廠不帶任何 repo URL**。既保留開箱可用，又讓插件生態在架構論述上與主 repo 分離。完整版（連內建源都拿掉）代價是新使用者第一次打開是一個空的 app |
| **9** | **新** | 插件執行環境選 `flutter_js`（能力完整、無正式沙箱）還是 `dart_eval`（有權限模型、不能用 pub 套件）？ | **`flutter_js`**。`dart_eval` 的限制直接卡死 DASH XML 解析與 HTTP；沙箱改由「宿主注入的能力面」收斂（插件拿不到 `dart:io`，只能用宿主給的 `http`）。**但要把 `flutter_js` 0.8.7 在 Android 上開箱即壞這筆維護債算進排期** |

#### 5.2 展開：D3（位元組快取）與 D4（just_audio 升級）的重新查證

2026-09-02 重查了實際安裝的套件原始碼（不是 pub.dev 頁面、也不是記憶），三條事實與原本的敘述不符：

| 查證項 | 原本的敘述 | 實際 |
|---|---|---|
| `LockCachingAudioSource` | 隱含「要升級才有」 | **just_audio 0.9.46 就有**（`just_audio.dart:2908`）。API：`LockCachingAudioSource(Uri, {headers, cacheFile, tag})`，邊播邊寫磁碟、支援 range 請求，另有 `resolve()` / `clearCache()` / `downloadProgressStream`。官方文檔仍標 **Experimental** |
| `setAudioSources(preload:)` 是 gapless 的前提 | D4 這樣寫 | **0.9.46 沒有這個方法，但有 `ConcatenatingAudioSource(children:, useLazyPreparation: true)`**（`just_audio.dart:2550`），那就是 0.9.x 的佇列 API |
| Windows 側 | 未查 | media_kit 1.2.6 有 `Playlist`（`media_kit/lib/src/models/playlist.dart:32`） |

**所以 gapless 與「切歌立刻有聲」的真正阻礙不是套件版本，而是 `FmpAudioService` 的介面**：
它的開媒體方法一次只吃一個媒體，沒有 `setQueue` / `supportsQueue`。那是 Phase 4 的範圍
（02 §6.3 階段 4 已經列了這兩個方法）。升 just_audio 因此降級成「要不要」，不是「必須先」。

**D3 維持 (c) 的理由改變了**，原本是「成本高」，實際是兩個更硬的前提：

1. **`LockCachingAudioSource` 只有 Android 有。** Windows 走 media_kit，沒有對等物。而 Phase 1
   整段都在收斂「兩平台行為不一致」（型別化 `PlaybackEndReason`、統一逾時預算）——
   加一個只有一半平台生效的快取是往反方向走。
2. **自建 loopback 代理要接的介面正在被改。** 它掛在 `FmpAudioService` 這一層，正是 Phase 4 要拆的。
   現在做等於做兩次。

補充一個現實面：FMP 已經有明確的下載功能，想離線的使用者現在就能下載。自動位元組快取的
邊際價值是「最近播過的自動留著」，比原本估的小。

#### 5.2 展開：預取深度維持 1（2026-09-02 新增決策）

Phase 1 修好預取之後（結果寫回佇列實例而不是被丟棄的 `copy()`），出現一個新問題：
要不要往前多預取幾首，因為使用者可能連按下一首？**結論：維持 1。**

四個對照專案（02 §5 逐檔案考據）**沒有一個做「往前預取 3–5 首」**，只有兩種模式：

| | 做法 | 深度 |
|---|---|---|
| Auxio | 整條佇列丟給 ExoPlayer Timeline | 引擎決定 |
| Finamp | `setAudioSources(preload: true)` | 引擎決定 |
| Symphony | 手刻雙 `MediaPlayer`，提前 prepare 下一個 | 1 |
| Spotube | 播放進度到 **80%** 才解析下一首 | 1（更晚） |
| FMP | 播放成功後解析下一首（`_nextTrackForPrefetch`） | 1 |

不加深的三個理由，都可驗證：

1. **風控。** 每次預取是一次真實的來源 API 呼叫。Phase 1 實機驗證期間 Bilibili 就對該機器回了
   HTTP 412 `request was banned`（深度 1 的情況下）。加深等於加倍風控風險。
2. **URL 會過期。** Netease 實測 1200s、Bilibili 約 2 小時。預取第 5 首而使用者十分鐘後才走到，
   那次呼叫是白打的。
3. **shuffle 下「下下首」不穩定。** `QueueManager.getNextIndex()` 有定義，再往後會隨 shuffle order
   重算而失效。

而且加深解不了原本擔心的情境：使用者連按十次下一首，任何深度都追不上。**對「切歌立刻有聲」
真正有效的是把佇列交給引擎**（見上一節），那是 Phase 4 的工作。

---

## 6. Quick wins 彙整

四份報告共列出約 130 條 quick win（01 的 28 條、02 的 Q1–Q34、03 的 Q35–Q62、04 的 Q1–Q14），
去重後按「一個 PR」分批。**下表是 Phase 0 的完整內容**，其餘 quick win 已經吸收進各 Phase 的步驟裡。

| 批次 | 條目數 | 內容摘要 | 來源編號 | 估時 |
|---|---:|---|---|---|
| **QW-1** CI 紅燈 | 3 | 3 個檔名改動：`test/performance/*_test.dart` → `*_benchmark.dart`（2 個）、`test/demo/bilibili_info_test.dart` → `*_demo.dart`。**這 3 個檔名就消除了 CI 上唯二的結構性紅燈來源** | 01#1,#2 | 5 分鐘 |
| **QW-2** CI 設定 | 6 | `timeout-minutes: 10`、path filter（純文檔 commit 不跑 build job）、`dependabot.yml` 加 `groups`、`flutter pub run` → `dart run`（4 處）、release 的 test step 加 `--coverage` | 01#13,#14,#20；03 Q48,Q49 | 30 分鐘 |
| **QW-3** 測試資產 | 4 | 刪 `test/widget_test.dart`（11 行 `expect(true, isTrue)`）、併 `lyrics_window_layout_test.dart`、清 5 個死 `@override`（測試替身已與正式介面漂移）、`bilibili_live_api_lookup_demo.dart` 補 `ignore_for_file` | 01#18,#19,#22,#23 | 30 分鐘 |
| **QW-4** AGENTS.md 修正 | 10 | `playlistProvider` → `playlistListProvider`（硬性錯誤）、`_FmpImageCacheManager` 路徑、`audio_playback_types.dart` 描述、capability 5 → 11、刪「is enforced by」的假安全網、常數只有 3 個的說明、Key Paths 漏列 9 個子目錄、buffer profile 4 項未記載的 property、`storage_permission_service.dart` 的放置規則 | 01#3,#6,#7,#8,#9,#10,#24；02 Q12,Q13 | 45 分鐘 |
| **QW-5** 其他文檔 | 6 | `CONTEXT.md` 的 Netease allowlist（`c09aec10` 已刪除）、`docs/README.md` 的 `/qa`、`refactoring-log.md` banner + 失效路徑、`build-and-release.md:293-295`、`download_service.dart:1707` 註解、README 截圖說明 + 刪重複截圖 | 01#5,#11,#12,#17,#27,#28；03 Q37,Q38 | 45 分鐘 |
| **QW-6** verify-on-device SKILL | 6 | 模擬器音訊快 1.68x、AVD DNS 每次 1 秒不快取、`adb emu network speed` 對 Wi-Fi 無效、Windows run terminal 被 AXTree 洗掉只能靠截圖且要先抬前景、用 WinRT 讀 SMTC 不要截浮出視窗、**優先用 VM Service `evaluate` 而非截圖**、CMake 暫存專案不能放深層路徑 | 02 Q14,Q30 | 30 分鐘 |
| **QW-7** 使用者可見單行 | 9 | `player_page.dart:488` 的 artist fallback（**播放中顯示「選擇一首歌曲開始播放」**）、shuffle 關閉態圖示、設定頁副標題漏網易雲、`radio_player_page.dart:219`、8 個 tooltip、2 個播放鍵 tooltip、`semanticFormatterCallback`、狀態列 `AnnotatedRegion`、3 個 `unknownArtist` 字串統一 | 04 Q1,Q2,Q4,Q8,Q9,Q10,Q11,Q12,Q13 | 1.5 小時 |
| **QW-8** 死依賴與死碼 | 9 | 刪 6 個直接依賴、`SourceManager` 5 個死方法 + 2 個死 provider、`WindowsSmtcHandler.enable/disable/dispose`、`mobilePlayerBufferSizeBytes`、3 個無呼叫方的 `watch*`、`AudioController.dispose()` 補 `_windowsSmtcHandler.dispose()` | 01 決策點7；02 Q9,Q10,Q11；03 Q35,Q36,Q42；04 Q3 | 1 小時 |
| **QW-9** 安全與韌性 | 8 | `maxSizeMiB: 64 → 2048`、`MediaKit.ensureInitialized()` try/catch、`_preloadThemeSettings()` 空 catch 補 log、`allowBackup="false"`、log 遮蔽補裸 `csrf`、Bilibili/Netease `logout()` 清 WebView cookie、下載 isolate redirect 補 URL policy、`youtube_stream_test_page` Cookie 探測加 `kDebugMode` | 01#15；03 Q40,Q41,Q43,Q44,Q45,Q46,Q53 | 2 小時 |
| **QW-10** i18n / 本地化 | 2 | `LocaleSettings.useDeviceLocale()` 上移到 `AudioService.init()` 之前（**通知頻道名稱永遠是英文**的完整修法）、刪或說明未使用的 `nav.explore` key | 01#25,#26 | 20 分鐘 |
| **QW-11** 記到 issue / GitHub | 3 | issue #38 留言指向 `ce100d32` 後關閉、issue #42 撤下「備份仍照樣匯出匯入」那一條並改指向 `RadioStation.note`、issue #41 驗證後關閉 | 03 Q50,Q54 | 15 分鐘 |
| **QW-12** 觀測腳本入庫 | 3 | `scripts/smtc_probe.ps1`、`stallsrv.py` / `holdsrv.py` 進 `scripts/` 或 `test/manual/`、`docs/debugging-with-vm-service.md` 補「表達式求值」一節 | 02 Q21,Q26,Q31 | 1 小時 |

**合計約 69 條，估時約 9–10 小時**，全部成本 S、風險低、完全可逆。

**已經做掉、不要再列的**：02 的 Q24 / Q28 / Q32 / Q33 / Q34。

**升級成 Phase 步驟、不再算 quick win 的**：
02 Q1–Q8, Q15, Q17, Q22, Q23, Q25, Q29（→ Phase 1）；02 Q19, Q20（→ Phase 4B）；
03 Q39（→ Phase 2.0）、Q51, Q55–Q62（→ Phase 3）；04 Q5, Q6, Q7, Q14（→ Phase 5a/5b）。

### 6.1 執行時的失效重核（2026-09-02，Phase 0 開工當天）

報告寫成之後樹上又動過，開工前逐條 `rg` 過一遍。**以下 6 條已失效或當初就判斷錯誤，
不可照抄**——記在這裡是為了讓後面幾個 Phase 開工時同樣先做這一步。

| 原條目 | 開工當天的實況 | 處置 |
|---|---|---|
| QW-2 `flutter pub run` → `dart run`（4 處） | `rg "flutter pub run" .github/` 零命中 | 撤銷，已是對的 |
| QW-2 補 `timeout-minutes` | `ci.yml:28,78,115` 與 `release.yml` 5 處都已有 | 撤銷，已是對的 |
| QW-2 test step 補 `--coverage` | `ci.yml:64` 已是 `flutter test --coverage --exclude-tags live` | 撤銷，已是對的 |
| QW-5 `docs/README.md` 的 `/qa` | 零命中 | 撤銷，已是對的 |
| QW-5 `refactoring-log.md` banner | 檔案已不存在 | 撤銷 |
| QW-5 `docs/build-and-release.md:293-295` 失效敘述 | 該檔引用的 6 個 `.dart` 路徑全部存在，找不到失效處 | 撤銷，原判斷有誤 |

另外三條需要修正描述，不是失效而是**當初判斷錯了**：

| 原條目 | 更正 |
|---|---|
| QW-8「`SourceManager` 5 個死方法」 | 實際零引用的只有 `parseUrlProvider` / `parsePlaylistProvider` 兩個 provider。`trackInfoSourceForUrl` **有內部呼叫**（`source_provider.dart:99,104`），不是死碼；`isPlaylistUrl` / `refreshAudioUrl` 只被測試呼叫；`needsRefresh` 零引用但**是 Phase 1.1 要復活的那段 5 分鐘邊界邏輯，不可刪** |
| QW-8「`mobilePlayerBufferSizeBytes` 是死常數」 | `media_kit_audio_service.dart:154` 有引用。但 `audio_provider.dart:3267` 的 `audioServiceProvider` 讓 mobile 一律走 `JustAudioService`，所以那個分支在生產環境**不可達**——是「有引用但走不到」，不是「無引用」。保留為防禦性 guard，已在 `lib/services/audio/AGENTS.md` 記明 |
| 01 P0-3 / QW-4「AGENTS.md 13 條錯誤斷言」 | 機械抽驗全部 `AGENTS.md` + `CONTEXT.md`：**317 個識別符裡只有 1 個真的不存在**（`playlistProvider`），**所有 `.dart` / `.json` 路徑引用零錯誤**。其餘問題是語意層的（數量過期、過度宣稱「is enforced by」、Key Paths 漏列 9 個 `lib/services/` 子目錄、`CONTEXT.md` 的 allowlist），符號檢查抓不到 |

**新測得的基準（`9bb0b8e5` 之後）**：`flutter test --exclude-tags live` = **1220 passed**，
連跑 3 次一致，耗時 31–33 秒。01/02/03 報告的 1241 / 1242 / 1234 全部作廢。

**執行到一半才發現的另外四條**（都是報告的判斷有誤，不是失效）：

| 原條目 | 更正 |
|---|---|
| QW-10「刪未使用的 `nav.explore` key」 | **有在用** —— `explore_page.dart:92` 的 `t.nav.explore`。不刪 |
| QW-9「`youtube_stream_test_page` 的 Cookie 探測加 `kDebugMode` gate」 | **指控不成立**。`_formatHeaderKeys()`（`:818`）只印 `key(長度)`，不印值；該頁還在 `developerOptionsProvider` 解鎖之後。加 gate 只會拿掉 release 版的診斷工具，不改 |
| QW-7「8 個 tooltip + 2 個播放鍵」 | 機械掃描全 `lib/ui`：**96 個 `IconButton` 裡 26 個缺 tooltip**，不是 10 個。已全部補上（`lyrics_title_bar.dart:188` 是掃描誤報，它用 `Semantics(label:)` 已經是可存取的） |
| QW-8「刪 6 個死依賴」只列了 Dart 層 | **Dart 零 import 不足以判定**。`windows/runner/flutter_window.cpp:8` 手寫 include 並註冊了 `dynamic_color` 的原生外掛，只有 **release build 才會抓到**（`error C1083`）。往後刪依賴必須兩平台各 build 一次 |

**Phase 0 的最終基準（`104bd8d3`）**：1222 passed（1220 + 新增的 `csrf` 遮蔽與
`isLocalOrPrivateHost` 分類器兩條測試），`flutter analyze` 全綠，
`flutter build apk` / `flutter build windows` 皆成功。

---

## 7. 10 個 issue 的處置

| # | 標題 | 裁決 | 排到哪 | 要改什麼 |
|---|---|---|---|---|
| **#35** | 帳號憑證讀取未捕捉 secure storage 的平台例外 | **保留，獨立修，不併入任何重構** | **Phase 0e** | 描述改三處：Android 走的是舊式自訂 cipher **不是** `EncryptedSharedPreferences`；Windows 是 AES-GCM + Credential Manager **不是** DPAPI；真正的永久 loading 在 `audio_settings_provider.dart:139` 的 `readApiKey()`（issue 未列的第 4 處）**不是**帳號狀態。補上最可操作的根因：`AndroidManifest` 缺 `allowBackup="false"`，這正是上游 README 點名的觸發條件。⚠️ **不可以**把 `PlatformException` 併進現有的 `_discardMalformedCredentials()` —— 那會在暫時性 Keystore 失敗時永久刪掉憑證 |
| **#36** | 統一三源登入失效的呈現與重新登入入口 | **保留，改寫內文，拆成兩張** | **#36a → Phase 5 後段；#36b → Phase 5 之後** | 內文三處不符：Netease 的 301 判斷在**播放層**不在帳號服務層；Bilibili 續期的行號是 `:315-417` 且**只在啟動時跑一次**（那個 interceptor 全庫只註冊在一處，播放/搜尋路徑上的 -101 不會觸發續期）；隱含的「三個平台表現一樣」在播放層不成立（預設 `useNeteaseAuthForPlay = true`、另兩個 `false`）。**#36 有 8 成在 service/provider/model 層，不能掛在「UI 重構」下** |
| **#37** | `runApp()` 之前的任何例外變成靜默失敗 | **保留** | **Phase 0e（第二層）+ Phase 3（第一層）** | 一處不準：`_preloadThemeSettings()` 自己有 try/catch 吞掉一切，不可能 throw；裸奔的是 `MediaKit.ensureInitialized()` / `AudioService.init()` / `_initializeSmtc()` / `_initializeWindowManager()`。補充：`PlatformDispatcher.instance.onError` 未設，且 `if (kDebugMode)` 讓 release 模式框架層錯誤完全靜默 |
| **#38** | CI 的「Verify generated files」名不副實 | **✅ 可關閉** | **QW-11** | 問題已在 `ce100d32` 修掉（該步驟整個刪除，並用 `dart format --set-exit-if-changed` 取代）。留言指向該 commit 後關閉 |
| **#39** | Windows 可攜版搬動資料夾後開機自啟靜默失效 | **保留，根因描述錯了一半** | **Phase 0e 或獨立** | `isEnabled()` **全庫 0 呼叫**；`state.enabled` 直接讀 Isar，跟登錄檔無關。真正的機制是「沒有任何程式碼會去核對登錄檔」＋「自我修復只在下次**手動**啟動時才發生，而依賴自啟的人正是最不會手動啟動的人」。修法要調整：先讀登錄檔比對，偵測到漂移時**告知使用者**，把現有的靜默修復變成有回饋的修復 |
| **#40** | Windows SMTC 兩個無法作用的控制項 | **保留，標題要改成四個** | **next/prev → Phase 4B；seek/shuffle/repeat → Phase 0（改成不宣告）** | 實際是 **next / previous（電台時）、seek、shuffle、repeat** 四項，而且分兩類：next/prev **事件有到 FMP**（有 log），是 FMP 自己的 config 沒跟著關 —— 可修；seek/shuffle/repeat **事件沒到**，是 `smtc_windows` 1.1.0 的 Dart wrapper 沒 export —— 只能改成「不要對外宣稱有」。另外 issue 對症狀二的機制推論被推翻：`IsPlaybackPositionEnabled` 本來就是 `False`，Windows 根本不會畫可拖曳的條 |
| **#41** | 音訊輸出裝置失效被誤判成「播放失敗」 | **✅ 已修（`056f20c3`），驗證後關閉** | **QW-11** | `OutputDeviceFailed`（`audio_types.dart:107`）就是 issue 要的型別化訊號，`_isStringMediaOpenError` 已全庫零命中。關閉前建議複驗一次「電台路徑不再吞掉錯誤」（`RadioController` 過去完全沒訂閱 `errorStream`） |
| **#42** | `preferredAudioDevice*` 是死欄位 | **保留，但第二條指控要撤下** | **Phase 3c** | 第一條（功能缺口）證實。第二條（「備份仍照樣匯出匯入」）**推翻**，三層互相獨立的反證：`backup_data.dart` 裡根本沒有這兩個欄位；`backup_service.dart:765-769` 賦值來源是本機值且上一行註解寫著「保留当前值」；被引為證據的測試名字就是 `preserves device-specific ones`。**備份層的處理反而是對的。** 那條指控放在 `RadioStation.note` 上才成立 |
| **#43** | `audio_controller_phase1_test` 在負載下偶發失敗 | **保留，但改寫成「測試 fixture 生命週期洩漏」** | **Phase 0a + Phase 3** | 根因推測是錯的：CI 實際失敗的那條測試**已經在用** issue 建議的條件式 helper，而它自己也有 `maxPumps = 50` 上限。真正的鏈是 `tearDown` 沒有 drain 進行中的非同步工作就 `isar.close()` → `IsarError: Isar instance has already been closed` → 狀態永遠不收斂。修法方向要改（tearDown 前 await/取消 in-flight persistence，或讓 `QueueRepository` 在 Isar 已關閉時安全 no-op）。**順帶：生產環境的 `queue_manager.dart:402` 有同類風險，值得單開 issue** |
| **#44** | 遷移 isar 至 isar_community | **保留，補兩段** | **Phase 2** | ① **遷移步驟不完整 —— 照著做會在 `flutter pub get` 就失敗**，缺 slang 3.32→4.19 這個連動的大版本升級（實測輸出見 03 §14.2）② **價值被低估**：`isar_generator` 的 `analyzer >=4.6.0 <6.0.0` 把整個 build 生態釘在 2023 年，而且它是 Riverpod 3 的**硬**阻塞。這讓 #44 從「非緊急的維護性改善」升格為「其他兩件事的前置條件」③ 資料遷移成本**實測**為零（不只是 changelog 背書） |

### 建議新開的 issue（目前沒有 issue 在追，但都是 P0/P1）

| 標題 | 級別 | 依據 |
|---|---|---|
| 串流解析零快取：每次播放都重打音源 API，預取結果被丟棄 | P0 | 02 P0-1（實測每次多付 1.25–1.74s） |
| 播放載入路徑無任何逾時上限 | P0 | 02 P0-2（零位元組串流：Windows 6.1s 假成功、Android 37.7s 才拋） |
| YouTube audio-only 被 bot 檢查擋死，每次退化成 20 秒 + 含視訊的 muxed 串流 | P0 | 02 P0-3（點擊→出聲 22–24s，下載量 3–5.5 倍） |
| 首頁排行榜音源數用視窗級斷點判斷內容區寬度：平板上一播歌就少一個音源 | P0 | 04 P0-1（Windows 與 Android 兩平台各自實測拍到） |
| `Isar.open(maxSizeMiB: 64)` 沒有溢位處理，且資料無保留策略 | P0 | 03 P0-1 |
| `test/performance/` 的 12 條 wall-clock 斷言在 CI 規格機器上必失敗 | P1 | 01 P0-1（4/4 負載回合必失敗；乾淨 32 核機器餘裕只有 1.48x，GitHub Actions 是 4 vCPU） |
| `account_playlists_sheet.dart:123-129` 把所有例外吞成同一個代碼 | P1 | 04 §14.7 |

---

## 8. 驗證記錄：本輪查證了什麼

### 8.1 環境

```
HEAD d4401cbe（工作樹乾淨）
Flutter 3.47.1 / Dart 3.13.1 / Windows 11
本輪未執行 flutter analyze 與 flutter test（見 §8.3）
```

### 8.2 為了解決「報告之間看起來矛盾」而做的查證【事實】

| 疑點 | 查證方式 | 結論 |
|---|---|---|
| 01 說「35 檔依賴 Isar」，03 說「85 個 `.dart` 檔」 | `rg -l "package:isar" lib/` = **35**；`test/` = **50**；合計 **85** | **不是矛盾**，是範圍不同。01 講 `lib/`，03 講全樹 |
| 01 說 slang **3.32**，03 說 slang **3.31** | `pubspec.yaml:83` 是約束 `^3.31.0`；`pubspec.lock` 解析到 **3.32.0** | **不是矛盾**，約束 vs 解析版本 |
| 02 P2-13 說「依賴落後的只有 just_audio 一個」，03 §4.5 另外列了 5 個落後的 | 02 的範圍是**音訊後端三件套**，03 的範圍是全部直接依賴 | **不是矛盾**，但 02 那句話不能被單獨引用 |
| 測試基準 1241 / 1242 / 1234 三個數字 | 分別對應 `b93f72c7` / A 落地後 / `c09aec10`（D8 刪除移除 10 條測試）之後 | **不是矛盾**，是不同 HEAD。**Phase 0 結束後要重新量一次當新基準** |
| 02 說「不重寫」但又說 `AudioController` 值得「局部重寫」；03 說 migration 機制「該換掉」 | 逐段比對三份報告的措辭 | **不是矛盾**。模組層級全部漸進；「局部重寫」指的是兩個 ≤120 行的方法與一個機制。已在 §2.2 統一表述 |

### 8.3 為了確認「報告寫成之後樹上變了什麼」而做的查證【事實】

```
$ rg -n "endReasons|Stream<PlaybackEndReason>" lib/services/audio/audio_service.dart
29:  Stream<PlaybackEndReason> get endReasons;

$ rg -n "OutputDeviceFailed|EndedPrematurely|TransportFailed" lib/services/audio/audio_types.dart
80:final class EndedPrematurely extends PlaybackEndReason {
96:final class TransportFailed extends PlaybackEndReason {
107:final class OutputDeviceFailed extends PlaybackEndReason {

$ rg -n "_isStringNetworkError|_isStringMediaOpenError" lib/
（零命中）

$ wc -l lib/services/cache/ranking_cache_service.dart
288
$ grep -cE "SourceType\.(bilibili|youtube|netease)" lib/services/cache/ranking_cache_service.dart
0
$ rg -n "registeredSourceTypes" lib/services/cache/ranking_cache_service.dart
271:    for (final sourceType in manager.registeredSourceTypes)

$ wc -l lib/services/audio/audio_provider.dart
3429            ← 02 §1.1 的基準是 2998
```

**結論**：02 §8.1(A)、02 §6.3 階段 2、02 §7.4 步驟 3、issue #41 都已經完成。
而 `audio_provider.dart` 在刪掉約 120 行字串比對之後**淨增 431 行** —— Phase 4 的必要性增強。

### 8.4 為了確認「哪些結論仍然成立」而做的查證【事實】

```
$ ls test/performance/
list_scrolling_benchmark_test.dart   startup_benchmark_test.dart      ← 仍是 *_test.dart

$ ls test/demo/
bilibili_info_test.dart  …                                            ← 仍會被 flutter test 收進去

$ git ls-files docs/adr
（零輸出）                                                             ← 仍是本機空目錄，clone 後不存在

$ head -1 LICENSE
                    GNU GENERAL PUBLIC LICENSE                        ← 仍是 GPL-3.0
$ ls NOTICE THIRD_PARTY*
（無此檔）

$ grep -nE "^\s+(dynamic_color|riverpod_annotation|flutter_reorderable_list|logger|uuid|intl):" pubspec.yaml
15:  dynamic_color: ^1.7.0
19:  riverpod_annotation: ^2.6.1
53:  flutter_reorderable_list: ^1.3.1
77:  logger: ^2.5.0
79:  uuid: ^4.5.1
82:  intl: ^0.20.2                                                     ← 6 個死依賴全在

$ awk '/^  analyzer:/{f=1} f&&/version:/{print $2; f=0}' pubspec.lock
"5.13.0"                                                               ← 天花板仍在

$ rg -n "hasValidAudioUrl" lib/services/audio/stream_resolution_service.dart
220:    if (track.hasValidAudioUrl || _prefetchingTrackIds.contains(track.id)) {
      ← 只在預取去重守衛裡，resolvePrimary() 的解析路徑上沒有 → P0-1 仍然開著

$ rg -n "timeout" lib/services/audio/playback_request_session.dart
（零命中）                                                             ← P0-2 仍然開著
```

### 8.5 本輪新量到、四份報告都沒有的一個數字【事實】

```
$ rg --files -g '*_test.dart' test/ | wc -l
179
$ rg -l "'lib/" test/ | wc -l
41
```

**179 個測試檔裡有 41 個（23%）在字串層引用 `lib/` 的路徑。**
01 P1-8 把它列為目錄重構的最大改動面（當時是 46/184），本輪重新量確認仍然成立。

**這揭露了一個四份報告之間的真實張力**：01 把源碼字串測試視為 Phase 6 的主要成本，
而 03 Q56（備份欄位守門測試）與 04 §10.5-1（禁止手刻空狀態的靜態規則）都建議**再增加**這類測試。
兩邊各自都對，但必須配一條紀律 —— 見 Phase 6 的「跨 Phase 紀律」段。

### 8.6 issue 現況【事實】

```
$ gh issue list --repo 1morr/FMP --state open --limit 30
#35 #36 #37 #38 #39 #40 #41 #42 #43 #44   ← 10 個全部仍 OPEN
```

其中 **#38 與 #41 的問題已經被修掉**，只是 issue 沒關。

### 8.7 本輪未做的事（據實記錄）

| 項目 | 為何未做 |
|---|---|
| `flutter analyze` / `flutter test` | 本輪是規劃輪，不重新審查程式碼；且跑 `flutter test` 會觸發 01 P0-2 的 Bilibili 生產 API 請求。**新基準應該在 Phase 0（QW-1 改完檔名之後）才量** |
| 實機驗證 | 本輪未改任何程式碼，沒有需要在裝置上確認的行為 |
| 逐條複驗四份報告的所有【事實】 | 本輪只複驗了 §8.2–8.6 的 20 餘條（矛盾點、時效性、路線圖排序所依賴的關鍵前提）。**四份報告本身的證據鏈以各輪的驗證記錄為準** |
| 成本估算的人日數字 | 除了 03 已經給出人日估計的幾項（Riverpod 3 = 2–4、Linux = 14–22、macOS = 8–14）之外，其餘的 S/M/L 沿用各輪報告的標註，**未做獨立的工時估算**。標「工作日」的地方是我的推估，未驗證 |
```

### 6.2 執行時的失效重核（2026-09-02，Phase 1 開工當天）

同樣先逐條 `rg` 過現況。**兩條主張已經失效**（都是被更早的 commit 修掉了），
其餘成立但有多處行號位移：

| 原條目 | 開工當天的實況 | 處置 |
|---|---|---|
| 1.7 後半：`_shouldHandleTrackCompleted` 的 `duration == null` 直接放行 | **函式已不存在**（全庫零命中）。`056f20c3` 換成兩個後端各自的 `_classifyCompletion()`，`duration == null` 現在回 `EndedPrematurely` | 撤銷，已是對的 |
| P0-4「Android 播放期間的網路錯誤被完全丟棄」 | **已修**。`just_audio_service.dart:303-335` 把 `source error` 映射成 `TransportFailed(reset)` | 撤銷；T3 watchdog 仍要做（它管的是「引擎什麼都不說」的情況） |
| 1.3「`track.cid` 從不回寫」引用 `bilibili_source.dart:720, 819` | 那兩行是 `VideoPage.cid` 的建構。`Track.cid` 全庫唯一寫入點是 `import_service.dart:592` | 更正引用，結論不變 |
| 1.9 `stallsrv.py` / `holdsrv.py` 收進 repo | **全 git 歷史零命中**，只活在 scratchpad 裡 | 改成用 Dart 重寫 |

**執行中發現的三件事**（報告沒寫、實作時才浮現）：

| # | 發現 |
|---|---|
| 1 | **`Track.uniqueKey` 不含 `pageNum`**（`track.dart:334`）。解析快取只用它當 key 會把 Bilibili 分 P1 的 URL 餵給 P2 —— cid 還沒解析出來時兩者同 key。快取 key 必須另外併上 `pageNum` |
| 2 | **預取不可以落盤**。改成傳佇列實例之後若同時開 `persist: true`，這個 fire-and-forget 的寫入會撞上正在關閉的 Isar（測試 teardown 直接重現）。預取只寫記憶體，真正播放時才落盤 |
| 3 | **URL 沒過期不等於 URL 還能用**。短路必須配一個「播放失敗就作廢」的出口，否則被 CDN 403 掉但還沒過期的 URL 會在每次重試被交還回去，比不做快取還糟 |

**實機量到、需要你拍板的一項** —— **T1 = 6 秒讓 YouTube 在 bot 檢查下完全播不了**：

```
[YouTubeSource] Audio-only stream failed for s466YCiHfKw:
  Reason: Sign in to confirm you're not a bot
[PlaybackRequestSession] streamResolution exceeded its 6000ms budget
[AudioController] Failed to play track: JENNIE - FALLEN ANGEL
  Error: PlaybackTimeoutException: streamResolution exceeded 6s
（被放棄的解析在背景跑完）
[DefaultStreamResolutionService] Resolved stream for youtube:s466YCiHfKw
  in 22713ms (muxed, 446754bps)
```

逾時機制本身完全正確：6000ms 準時攔下、型別化例外、不跳歌、不進退避階梯、
畫面出現 `Cannot play "...": Connection timed out`。問題是**數值**：
androidVr 的 audio-only 被擋下之後，退到 muxed 實測要 22.7 秒（報告在 Windows 上量到 9.9 秒），
兩者都遠大於 6 秒。而 audio-only 被擋是常態不是例外。

**已定案並複驗：T1 = 25 秒，且整個請求共用一個總期限。**

逾時是「別無限等下去」的兜底，不是逼快的閘門，所以取值偏寬：太緊的代價是那些影片
一律播不出來，太鬆只是多轉一下才誠實失敗。20 秒實測仍會卡掉模擬器上 21.3–21.8 秒的
muxed 退路，25 秒才過。單獨放寬 T1 會讓最壞等待變成 (T1+T2)×2 —— 比原本要修的
Android 37.7 秒阻塞還糟 —— 所以同批加上每次請求一個 `budget.total` 期限，
fallback 只能用剩下的時間。

**實機複驗（Android 模擬器，`Medium_Phone`）**：

```
首次解析   Resolved stream for youtube:I-5e_J3LWS8 in 21137ms (muxed, 736575bps)
           Playback selection ready in 21167ms
重播同曲   Reusing resolved stream for youtube:I-5e_J3LWS8 (playback)
           Playback selection ready in 25ms
背景預取   Resolving stream for youtube:s466YCiHfKw (prefetch)
           Resolved stream for youtube:s466YCiHfKw in 19275ms
切下一首   Reusing resolved stream for youtube:s466YCiHfKw (playback)
           Playback selection ready in 32ms
```

P0-1 的兩半都成立：同一首歌重播從 21,167ms 降到 25ms；下一首因為預取寫回了佇列實例，
切歌時的解析從約 20 秒降到 32ms。

---

### 6.3 執行時的失效重核（2026-09-02，Phase 2 開工當天）

仍然成立的：85 個檔案 `import 'package:isar/isar.dart'`（全庫只有這一種寫法）、
40 份複製的 `_resolveIsarLibraryPath()`（9 種拼法，行為完全一樣）、
analyzer 被釘在 5.13.0、`riverpod_annotation` 已在 Phase 0d 移除。

**兩條主張是錯的，五件事報告沒寫**：

| # | 原本的說法 | 實況 |
|---|---|---|
| 1 | 「slang 先、isar 後，拆成兩個獨立 commit」 | **這個順序做不出兩個可運作的中間狀態。** 反向也擋：`slang_build_runner >=4.4.2` 依賴 `dart_style >=2.3.7`，那需要 `analyzer ^6.5.0`，而 `isar_generator 3.1.0+1` 透過 `dart_style ^2.2.3` 把 analyzer 壓在 `<6.0.0`。真正的解法是**把 `slang_build_runner` 移除**：這個 repo 沒有 `build.yaml`，i18n 走 `slang.yaml` + `dart run slang` 的獨立 CLI，那個 build_runner shim 從來沒做過事。改成直接依賴 `slang`（它不依賴 analyzer / build / dart_style）之後，兩步就真的拆得開 |
| 2 | 「要改 `slang.yaml` 的 `output_file_name`」 | **`output_file_name` 在 slang 4 仍然有效且必填**（README 設定表）。4.0 移除的是 `output_format`，而 FMP 沒設過它。真正要加的是 `lazy: false` |
| 3 | （沒寫）`-Sync` 後綴 | 官方 MIGRATION.md 明說：4.0 預設非同步載入，**要讓 `setLocaleSync` / `useDeviceLocaleSync` 正常運作必須同時設 `lazy: false`**。只改後綴不改設定會拿到還沒載入的語言。FMP 只出 Android 與 Windows，兩者都不支援 deferred loading，`lazy` 換不到任何東西 |
| 4 | （沒寫）`intl` | slang 4 的生成碼直接 `import 'package:intl/intl.dart'`（`DateFormat` / `NumberFormat`）。Phase 0 把 `intl` 當死依賴刪掉了，這裡要加回來（`intl: any`，版本交給 `flutter_localizations`） |
| 5 | 「2.3 是純 `sed`，約 90 行變動」 | **低估。** 換 package 還牽動兩處原生設定：Windows 動態庫從 `isar.dll` 改名成 `libisar.dll`（`Abi.localName` 的回傳值也跟著改），plugin header 目錄變成 `<isar_community_flutter_libs/...>`，`windows/runner/flutter_window.cpp:8` 要跟著改。plugin class 與 registrar 名稱（`IsarFlutterLibsPlugin`）沒變 |
| 6 | 「11 collection 生成碼逐字相同」 | **逐字比對是 11 個檔全不同**，因為 analyzer 解禁把 dart_style 一起帶到 3.1.7，尾逗號排版整批改寫。但把空白、尾逗號、`version:` 字串正規化之後**完全一致** —— schema id hash、property id、index / link 定義一個都沒動。`CollectionSchema.version` 是 build-time 的 `assert(Isar.version == version)`，不是磁碟格式檢查 |
| 7 | （沒寫）解禁之後才看得見的東西 | analyzer 5.13 → 10.2 多出 **18 條新 lint**（13 條 `unnecessary_underscores`、5 條 `use_null_aware_elements`），而 CI 跑的是裸 `flutter analyze`（exit 1）；build_runner 2.15 **移除了 `--delete-conflicting-outputs`**，10 個檔案與兩支 workflow 都還寫著它 |

**驗收記錄**：

| 項目 | 結果 |
|---|---|
| analyzer 天花板 | `5.13.0 → 10.2.0`；`build 2.4.1 → 4.0.7`、`source_gen 1.5.0 → 4.2.4`、`build_runner 2.4.13 → 2.15.1` |
| `flutter analyze` | 全綠（修掉 18 條新 lint 之後） |
| 測試 | 1254 條全過，與 Phase 2 開工前的基準相同 |
| 生成碼 | 11 個 collection 正規化後逐字一致（見上表 #6） |
| 16 KB 對齊 | `libisar.so` 四個 ABI 的 LOAD align `0x1000 → 0x4000`（先在 pub cache 裡驗，再從建好的 APK 裡驗 3 個實際打包的 ABI）。APK 內其餘原生庫本來就是 `0x10000`，也合規 |
| 真實資料庫 | `Documents/FMP/fmp_database.isar`（5.2 MB）複製一份，用 isar_community 3.3.2 原地開啟：11 個 collection 共 **1,534 列**全部讀得出來、Track 反序列化正常、寫入 + 刪除來回一次成功 |
| Android 實機 | AVD 是 `sdk gphone16k`（`ro.boot.hardware.cpu.pagesize = 16384`）—— 正是會觸發對齊對話框的映像。app 正常啟動、Isar 開啟、YouTube 曲目播放成功並寫入播放歷史，logcat 沒有任何對齊抱怨 |
| slang 4 語系切換 | 設定頁選「繁體中文」後整棵 UI 立即切換（`setLocaleSync`）；`pm clear` + `cmd locale set-app-locales zh-TW` 之後重啟，通知頻道名稱是 **`FMP 音訊播放`**（zh-TW），裝置語系為英文時是 `FMP Audio Playback` —— 兩個方向都對，證明 `useDeviceLocaleSync()` 在 `AudioService.init()` 之前同步生效，P1-9 的修法沒被弄壞（若失效會落到 base locale 的 `FMP 音频播放`） |
| Riverpod 3 解鎖 | `flutter pub add --dry-run flutter_riverpod:^3.0.0` 解得開（會動 13 個依賴），不再 version solving failed。**實際升級仍留在 Phase 3**（03-D4 方案 A） |
| Windows | `flutter build windows` 成功（原生 include 改動有編譯與連結驗證）；跑起來開啟真實資料庫，關閉後 11 個 collection 列數與備份完全一致 |

**兩件據實記錄的事**：

1. **Windows 子視窗的執行期路徑沒有實際驅動過。** `flutter_window.cpp` 改的是給歌詞子視窗用的
   plugin 註冊，只有編譯 + 連結驗證（header 路徑錯會編不過，符號錯會連不起來），
   registrar 名稱沒變。要驅動它得先在 Windows 上成功播放一首歌，而這台機器目前
   被 Bilibili 限流（HTTP 412）、YouTube 擋 bot 檢查。Windows 端也沒有語意樹可用。
2. **開啟後資料庫檔案從 5,242,880 縮到 2,686,976 bytes。** 列數逐項不變（1,534），
   所以是回收空閒空間不是掉資料。縮的比例（約 1.95）與 FMP 自己既有的
   `compactOnLaunch(minRatio: 2.0)` 吻合，那段設定這一期沒動過。

---

### 6.4 執行時的失效重核（2026-09-03 / 04，Phase 3 後半開工當天）

仍然成立的：`@Enumerated(EnumType.name)` 本來就寫字串所以 M5.5 不改磁碟格式、
Isar 的 `_requireNotInTxn()` 是 Zone 層級判斷所以匯入不能只加一層外層交易、
`docs/adr/` 是空的（這輪寫了頭兩份）。

**九條改變做法**：

| # | 原本的說法 | 實況 |
|---|---|---|
| 1 | 「備份今天沒有靜默遺失，缺的 3 個是刻意排除的裝置設定」 | **前提是錯的。** `Settings` 有 57 個持久化欄位，`SettingsBackup` 只涵蓋 44，缺 13。程式碼裡的註解只涵蓋裝置組與桌面平台閘控組；`railExpanded` / `detailPanelExpanded` / `detailPanelWidth` / `schemaVersion` **零說明**，而且每次匯入都被 `createBootstrapSettings()` 重設。前三個已補進備份 |
| 2 | 「M5.5 併進批次 schema 變更，邊際成本近零」（`:482`） | **前提不成立。** 這項改動不改磁碟格式、不需 migration、不碰備份格式與 catalog，它與那個批次共用的成本是 0。真正的理由是 Phase 9.1 前置 ＋ 修掉 **7 條**靜默改寫路徑（5 個 collection 的生成 reader 各一，加 `backup_service` 與 `download_scanner` 兩處手寫），不是 2 條 |
| 3 | 「`SettingsBackup` 把欄位手抄 4 遍」 | **6 處**。DTO 沒有 `fromSettings` / `applyTo`，那兩個方向被內聯進 `BackupService`。加一個欄位要改 2 個檔案 6 個地方 |
| 4 | 「守門測試掃 `settings.dart` 的欄位宣告」 | **會誤判。** `Settings.useAuthForPlay(String)` 是方法，`SourceSettingsEntry.useAuthForPlay` 是欄位，同名。改掃 `settings.g.dart` 的 `PropertySchema`，並限定在 `SettingsSchema` 區塊（該檔共 60 個，其中 3 個屬於 embedded 物件） |
| 5 | 「面板欄位跟桌面設定一樣做平台閘控」 | **錯的。** `_DesktopLayout` 由螢幕寬度斷點選出（`responsive_scaffold.dart:78`），不是平台；Android 平板在寬版面同樣會用到側欄與詳情面板。改成無條件還原 |
| 6 | 「`addTracks` 的交易本體 321 行」 | **129 行**（`:289-417`）。原本的量測把它跟後面的 `replaceTracksFromRemoteRefresh` 併在一起算了 |
| 7 | 「`Isar.isOpen` 存在」 | 是**實例 getter**（`isar.dart:148` 的 `bool get isOpen`），不是靜態成員 |
| 8 | 「#43 的根因是 `tearDown` 不 drain」（`:961` 的改判） | **只對一半，而且原 issue 的推測也只對一半。** 兩條根因獨立存在：(a) `audio_controller_phase1_test.dart:1310` 寫死的 `pumpEventQueue(times: 1)`，(b) `queue_manager.dart:212` 用 `Future.delayed(10s)` 排的孤立 track 清理沒有 handle 所以 `dispose()` 取消不了。兩條都修了 |
| 9 | 「3d 邊界收斂待驗收」 | 開工當天量測已經是 54（驗收線 < 60）。M6.2 之後降到 **19** |

**執行中發現，報告寫的時候不知道的**：

| # | 發現 |
|---|---|
| A | `backup_service.dart:502` 與 `:520` 兩筆交易只是在補償 `addTracks` 蓋掉的 `updatedAt` / `coverUrl`。補償邏輯仍然需要，但可以收進同一筆交易 |
| B | `existingHistoryKeys`（`backup_service.dart:534`）在迴圈內從不 `add`，同一份備份裡重複的播放紀錄會重覆插入。已修 |
| C | `kBackupVersion` 的說明註解只描述到 v3，M5.6 把常數改成 4 時沒更新。已補 |
| D | **本機 `dart format` 與 CI 的結果不一致**：同一套 Flutter 3.47.1 / Dart 3.13.1，本機判定 `lib/` 333 檔有 250 檔要重排（Dart 3.7 tall style），CI 的 `Check formatting` 卻是 success。已開 issue #53。在查清楚之前不要對舊檔跑整檔 `dart format` —— 這輪已經害過一次，那個 commit 被改寫掉了 |
| E | 全庫**沒有**單檔輪替的先例可沿用。`lyrics_cache_service` 的 `_evictOldest` 是多檔 LRU 淘汰，形狀不同 |
| F | `main.dart:51/66` 的錯誤處理器掛在 `ensureInitialized()`（`:71`）之前，而 `path_provider` 要等 binding。log sink 因此必須延遲初始化，並在掛上時回填記憶體緩衝 |

**驗收記錄**：

| 項目 | 結果 |
|---|---|
| `flutter analyze` | ✅ No issues found |
| `flutter test --exclude-tags live` | ✅ **1322 條全過**（Phase 3 前半結束時是 1289） |
| `dart run slang` | ✅ 重新生成後 analyze 仍綠 |
| repository 邊界 | ✅ 152 → **19**，且由 `isar_boundary_static_rule_test.dart` 釘住 |
| 真實資料庫副本 v1 → v2 | ✅ 11 個 collection 1,534 列不變，三筆 entry 值與舊欄位一致，舊欄位未被清空，連跑三次逐字相同 |
| M5.5 未知 source id（實機） | ✅ 用 VM Service 寫入 `sourceType: 'unknown'` 的 PlayHistory，冷關 app 後重啟讀回仍是 `unknown` |
| M5.6 每源設定（實機） | ✅ 三個音源的預設串流優先級與播放認證與 `kDefault*` 一致；改值後重啟保持 |
| M7 log 落盤（實機） | ✅ Android `app_flutter/FMP/logs/fmp.log` 與 Windows `Documents/FMP/logs/fmp.log` 都有內容，第一行是 sink 掛上前的啟動 log（緩衝回填有效），跨行程重啟 append（10,865 → 30,332 bytes），全檔無敏感 pattern |
| #43 的 `IsarError` 噪音 | ✅ 同一個測試檔從 33 筆降到 **0** |

**Phase 3 自己的實機驗收（`:325`）**：

| 項目 | 結果 |
|---|---|
| Android 背景播放 5 分鐘不中斷 | ✅ **5 分 14 秒**連續（03:28:12 → 03:33:26），`dumpsys media_session` 的 position 單調推進 6,547 → 135,548 ms，並在 03:31:22 掉回 6,751 —— **單曲循環的「播完→重播」轉換在完全沒有 UI 的情況下發生**。另一次獨立觀察：整首 5:42 在背景播到 `EndedNaturally()`。最後停止的原因是模擬器掉網（`BufferStarvationWatchdog` 偵測緩衝 15 秒 → 自動重試 → `網路連線失敗`），不是 out-of-view pause —— 而那套停滯偵測與重試本身也是在背景跑的 |
| Android 下載進度持續更新 | ✅ 觸發下載後立刻離開歌單頁，檔案 8 KB → 4,164 KB → 16,284 KB 完成落地，`已下載` 頁反映結果 |
| Windows 最小化到 tray 後播放不停 | ❌ **沒驗到**。縮到系統列本身成立（視窗數 0、行程存活、log `Minimized to tray`），但第一次嘗試時歌曲已在 04:10:36 自然播完（`No next track available`），我 04:11:13 才關視窗。後續三次都卡在 Windows GUI 驅動：用 Win32 `ShowWindow` 從托盤還原會讓 Flutter 停止繪製、熱重啟兩次讓 app 直接退出、`orca computer click` 的座標落到了其他視窗。**這是工具鏈阻塞，不是程式碼結論** |

**Windows 上的意外收穫 —— 真實生產資料庫**：

| 項目 | 結果 |
|---|---|
| v1 → v2 遷移 | ✅ `schemaVersion = 2`，`sourceSettings` 三筆的值與六個舊欄位**逐項一致**，而六個舊欄位**原封未動** —— 降級無損的保證在真實使用者資料上成立，不是在副本上 |
| M5.2 面板持久化 | ✅ `detailPanelWidth = 438.67`，是使用者自己拖出來的值，不是預設的 380 |
| M7 的實際價值 | log 檔是唯一讓人分辨「被托盤暫停」與「歌自然播完」的證據；沒有它只能看到位置停住 |

**三件據實記錄的事**：

1. **`bilibili_source_test` 有 2 條 `tags: 'live'` 的測試在本機是紅的。** 它們打真實
   B 站 API，這台機器被風控（HTTP 412）。專案的驗收指令本來就是
   `--exclude-tags live`，同檔其餘用 mock 的測試全過。
2. **#43 沒有證明修好。** 修掉兩條可證實的根因之後，失敗率從 19 次 3 次紅降到
   24 次 1 次紅，但沒有降到零，而且那一次的失敗細節沒抓到。issue 保持開啟。
3. **Windows 的三項驗證沒做到**：#42 的輸出裝置記憶、log 匯出、備份匯出。**備份匯入是刻意不做的** —— Windows 上跑的是使用者的真實音樂庫（1,194 首），匯入會實際寫進去。匯入的回滾行為由 `backup_service_test.dart` 涵蓋，而且那條測試做過反向驗證（把 track 寫入拆成獨立交易後它立刻紅）。
4. **log 匯出沒有在裝置上走完存檔。** 點按鈕會開啟 Android 系統目錄選擇器（證明
   Android 分支有跑到），但 `USE THIS FOLDER` 用合成點擊按不動。之後的寫檔是
   `File(path).writeAsString(...)`，與既有的備份匯出同一條路。輪替與落盤 redaction
   由單元測試涵蓋，沒有在裝置上用真實憑證驗過。

---

#### 6.4.1 Windows 驗收補完（2026-09-04 下午）

上面那張表把 Windows 的四項記成「工具鏈阻塞」。**其中「Windows GUI 驅動不了」這條
結論是錯的** —— 缺的只是一步：點擊之前要先把視窗提到前景。補上
`SetForegroundWindow`（用 `AttachThreadInput` 包住）之後，`orca computer click
--app pid:<n>` 的視窗座標一路都正確，四項全部驗完。做法記在
`.claude/skills/verify-on-device/SKILL.md`。

| 項目 | 結果 |
|---|---|
| Windows 最小化到 tray 後播放不停 | ✅ 14:07:02 `WM_CLOSE` → `Minimized to tray`、`IsWindowVisible` 轉 false、行程存活；隱藏期間 `PlayQueue.lastPositionMs` 從 76,771 走到 196,830，**牆鐘 120 秒、播放前進 120.1 秒**，零暫停事件；14:12:01 用使用者自己的 toggle 快捷鍵叫回視窗 |
| #42 輸出裝置記憶（還原半邊） | ✅ 在真實硬體上兩次獨立出現完整鏈路：`Restoring preferred audio device: wasapi/{2350b26b-…}` → `Setting audio device: … (喇叭 (Creative Stage SE))` → **`Audio device changed`（libmpv 自己回報切換成功）**。不是「程式碼有跑」，是輸出裝置真的換了 |
| 備份匯出 | ✅ 原生存檔對話框 → 828,868 bytes。`version = 4`；**M6.1a 的三個面板欄位都在**；`schemaVersion` 與 `preferredAudioDevice*` 正確不在 —— 與守門測試的排除清單逐項相符；`sourceSettings` 三個音源齊全 |
| log 匯出 | ✅ 原生存檔對話框 → 123,379 bytes，**等於磁碟上 `fmp.log` 的完整 1,228 行**；`Authorization` / `SAPISIDHASH` / `Bearer` / `Cookie:` / `SESSDATA` / `bili_jct` / `MUSIC_U` / `csrf` 掃描全為 **0**，`REDACTED` 出現 **11 次** —— 在有登入帳號的真實 session 上實際觸發過 |
| M7 日誌級別 UI | ✅ 開發者選項裡有「日誌級別 DEBUG」，副標「只影響這次執行，重啟後回到預設」 |

**#42 的另一半補的是測試，不是實機。** `4ca35a6d feat(audio): remember the chosen
output device` **一條測試都沒加**。本輪補上
`test/services/audio/audio_device_preference_test.dart`（6 條），涵蓋寫入、回到
auto、清單到齊時套用、裝置拔掉時不動也不清設定、只套用一次、沒存過就不動。做過反向
驗證：同時拿掉寫入與還原兩半之後，6 條裡有 3 條立刻紅。

**#42 的寫入半邊隨後也在實機上補驗了**（同日 14:44，上面那句「沒有用滑鼠點過裝置
選單」已不成立）：迷你播放器的輸出裝置選單 →「Realtek(R) Audio」，`Settings` 立刻寫入
`preferredAudioDeviceId = 'wasapi/{2698a574-…}'` 與
`preferredAudioDeviceName = '喇叭 (Realtek(R) Audio)'`，log 跟著出現
`Setting audio device` → `Audio device changed`；再點回「自動（跟隨系統）」兩個欄位都
回到 `null`，`Setting audio device to auto` → `Audio device changed: auto`。**issue #42
本輪關閉。**

驗這一項時另外修正了一條做法：`orca computer` 的 `--restore-window` 才是把視窗提到前景
的正確方式。我先寫進 skill 的 Win32 `SetForegroundWindow` 做法**時靈時不靈** —— 它在前景
鎖規則不允許時會靜默失敗，而接下來的 `get-app-state` 就會截到別的視窗（這次確實誤截了
使用者的另一個視窗一次，已刪除）。skill 已更正。

**仍然沒驗到的**：

1. **log 輪替沒有在裝置上驗**（要 2 MB，實測檔案只有 123 KB）。單元測試涵蓋。
2. **備份匯入仍然刻意不做** —— 理由同上：Windows 上是使用者的真實音樂庫。
3. **tray 測試期間三個音源都播不了**：Bilibili `playurl` 回 HTTP 412 `request was
   banned`、曲庫 1,194 首**沒有任何一首下載到本機**。tray 測試最後是用一段本機 WAV 走
   `_inspectLocalFiles` 的離線路徑跑的。這是環境限制，不是 FMP 的缺陷。（YouTube 稍後
   在 14:43 的裝置選單驗證裡是能正常播放的 —— 之前擋住的是評論 API，不是串流。）

**兩件據實記錄的事**：

- **redaction 有一個誤報**：`libmpv configured for audio-only mode (vid=no,
  sid=[REDACTED], …)`。那是 mpv 的字幕軌選項 `sid=no`，不是 session id。只影響 log
  可讀性，方向是安全的那一邊，本輪不改。
- **我弄丟了一筆資料**：佇列裡原本留著上一輪我自己建的測試曲目（唯一一首 youtube
  來源），把佇列換走之後被孤立清理刪掉了。使用者的 1,194 首 bilibili 曲目與 1 個歌單
  完好無損，已逐項核對。驗證期間改過的每一項（`minimizeToTrayOnClose`、
  `preferredAudioDevice*`、track 1 的 `playlistInfo`、佇列與循環模式）都已還原並確認。

**issue 動態**：本輪關掉兩張。**#44**（isar_community 遷移）—— 用 NDK 28.2 的
`llvm-readelf -l` 重量 release APK，三個 ABI 的 `libisar.so` 都從 `0x1000` 變成
`0x4000`，達到 issue 自己的驗收條件。**#42**（輸出裝置記憶）—— 寫入、清除、重啟還原
三條路徑都在真實硬體上走過，並補上原本缺席的 6 條測試。#43 與 #53 維持開啟。


---

### 6.5 執行時的失效重核（2026-09-05，Phase 4 步驟 B 開工當天）

Phase 4 的順序是 E→B→D→C。E（`QueueCommands`）已於 `fe0ee475` 落地。這一節記
步驟 B（`NowPlayingPublisher` + `PlaybackCapabilities`）開工前的重核與執行中發現。

#### 開工重核：三條說法被推翻

| # | 原本的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | `:958`「seek/shuffle/repeat 事件沒到，是 `smtc_windows` 1.1.0 的 Dart wrapper 沒 export —— 只能改成不要對外宣稱有」 | **兩邊都錯。** wrapper **有** `shuffleChangeStream` / `repeatModeChangeStream`（`smtc_windows_base.dart:102-103`），Rust 端也接了 `ShuffleEnabledChangeRequested` / `AutoRepeatModeChangeRequested`（`smtc_internal.rs:226/245`）—— FMP 只是從沒訂閱。而且 `SMTCConfig` **根本沒有** shuffle/repeat 的開關欄位，所以「不宣告」這條路**不存在** | 修法反過來：**去接事件**。已實作並實機證實兩個事件都送達（見下） |
| 2 | issue #40 是「Windows SMTC 的兩個控制項」 | **Android 有同一個 bug，而且更多。** `_getControls()` 無條件回傳三顆按鈕；`systemActions` 的 `skipToNext`/`skipToPrevious` 也是 `const`；更糟的是電台**從不清掉** `onSetRepeatMode` / `onSetShuffleMode`，所以在 Android 上聽電台時按通知欄的循環／隨機鍵，會去改**音樂的** loop mode | 兩平台一起修 |
| 3 | issue #40 附帶：「`enable()` `:299`、`disable()` `:311`、`dispose()` `:323` 三個成員從未被呼叫」 | **已過期。** 檔案在 `481acda8` 之後重排，`enable()`/`disable()` 已不存在，`dispose()` **有**呼叫點 | 更新 issue 時撤下這段 |

另外兩件決定設計的事實：

- **`androidCompactActionIndices` 的正解是「不要設」，不是「算出來」。**
  `AudioService.java:614-617` 在該欄位為 `null` 時自己算 `[0..min(3, 按鈕數))`，
  而 `:641` 顯示 SDK 33+ 根本不讀它。寫死的 `[0,1,2]` 才是越界來源。
- **`AudioRuntimePlatform` 只有 `mobile` / `desktop`**，而 `WindowsSmtcHandler`
  在 `_smtc == null` 時每個方法自己早退。所以 publisher **完全不需要
  `Platform.isWindows`**，`desktop` 涵蓋 Linux/macOS 是安全的 —— 這正是 §4.3 說的
  「把平台知識從 `Platform.isX` 改成介面上的能力查詢」。

#### 執行中發現

1. **`AudioController.dispose()` 直接 dispose 掉 SMTC 是一個潛在 bug。**
   原生 session 只在 `main.dart` 建立一次、沒有任何程式碼會重建它，所以只要
   `audioControllerProvider` 重建過一次，SMTC 就在該 session 裡永久死掉。改成
   `release(music)`：解綁回呼、留著原生控制代碼。
2. **交還擁有權的舊路徑有一個吞噬式 `catch`。** 電台停止時呼
   `AudioController.restoreMediaControlOwnership()`，外面包著 `catch (e) {
   logDebug(...) }`（release 模式看不見）。加上能力之後，那個 catch 一旦觸發，
   後果會從「回呼沒重綁」升級成「能力永遠停在電台的全關狀態」。改成 publisher
   自己記住音樂綁定並還原，那條跨 controller 呼叫與那個 catch 一起刪除。
3. **「非現任擁有者的發佈要丟棄」不是潔癖，是修一個真 bug** —— 而且**實機拍到了**：
   `Ignored publishPlaybackState from radio; owner is music`。點歌之後立刻點電台，
   `RadioController` 只 `pause()` 音樂、不取消進行中的請求，那個請求完成後會把歌名
   蓋到電台的通知欄／SMTC 上。
4. **步驟 B 不可能是「純位移」，三處不對稱必須收斂**：載入狀態與三條 reset 路徑
   過去只送到 Android 通知欄不送 SMTC；`_onPlayerStateChanged` 送給通知欄的是
   effective 值、送給 SMTC 的是後端原始值。AGENTS.md 那條「控制器擁有的載入階段，
   後端 idle 事件不得覆蓋 loading 狀態」沒有理由只保護一個平台。

#### 實機驗收（Windows，2026-09-05）

用新寫的 `.claude/skills/verify-on-device/scripts/smtc_probe.ps1` 直接讀 WinRT 的
`GlobalSystemMediaTransportControlsSessionManager`，不截系統浮出視窗。**探針從任何
行程都讀得到，所以完全繞開 FMP 守不住前景的問題。**（必須跑在 `powershell.exe`
5.1，pwsh 7 沒有 WinRT 投影。）

| 時間點 | `IsNextEnabled` | `IsPreviousEnabled` | `IsPlaybackPositionEnabled` |
|---|---|---|---|
| 音樂（啟動後） | **True** | True | False |
| 電台播放中 | **False** | **False** | False |
| 電台停止後 | **True** | True | False |

路線圖的驗收條件是「電台播放時 `IsNextEnabled` 為 `False`」——**達成**。回程也驗了，
因為「離開電台後能力沒還原」是比 #40 本身更糟的失敗模式，而它只在回程出現。

- **禁用不只是視覺**：電台播放中用 `TrySkipNextAsync()` 送 next（WinRT 回
  `accepted=True`），FMP 的 log **沒有**任何 `SMTC button pressed` —— 按鈕真的是惰性的。
  同一時間送 stop 則拍到 `SMTC button pressed: PressedButton.stop`，證明通道本身是通的。
- **Q19 的前提複驗**：`IsPlaybackPositionEnabled` 在三個時間點都是 `False`，
  與 §12.13a 一致。timeline 的 `maxSeekTimeMs` 已改為 0。
- **Q20 兩個事件都送達，並且真的接上了**：
  `SMTC repeat mode requested: RepeatMode.list` → `Setting loop mode: LoopMode.all`；
  `SMTC shuffle requested: false` → `Toggling shuffle`。兩個死鍵現在是活的。
  （WinRT 會把「與現值相同」的請求吃掉，所以測試要送反向值才看得到事件。）
- **`IsShuffleEnabled` / `IsRepeatEnabled` 恆為 `True`**，因為 `SMTCConfig` 沒有這兩個
  旗標。這正是「不宣告」做不到、只能去接事件的證據。

**讀 log 的通道要換**：Windows 的 `flutter run` terminal 被 `AXTree` spam 洗掉 ——
本輪量到 1,714 行的 buffer 撐不到 4 分鐘。改讀 Phase 3 M7 落盤的
`Documents/FMP/logs/fmp.log`，那裡完整。

**清理**：驗證用的電台（Bilibili 房間 6）已從資料庫刪除，回到「還沒有電台」；
shuffle 被測試切掉之後已切回原本的 `true`（loop mode 原本就是 `all`，未改動）。

#### 實機驗收（Android 模擬器 `Medium_Phone`，2026-09-05）

判準是**通知欄實際的按鈕數**（`dumpsys notification --noredact` 的 `actions=`），
不是 media session 的 bitmask —— 後者被 `audio_service` 混了一堆固定值（見下）。

| 時間點 | 通知欄按鈕 | session 有 `SKIP_TO_NEXT` / `SKIP_TO_PREVIOUS` / `SEEK_TO` |
|---|---|---|
| 音樂（YouTube 播放中） | **3**（上一首／暫停／下一首） | 是 |
| 電台播放中 | **1**（只剩播放／暫停） | **否** |
| 播回音樂 | **3** | 是 |

- **`AUTO_ENABLED_ACTIONS` 是套件寫死的常數**（`AudioService.java:99-100`），
  無條件 OR 進 `ACTION_SET_REPEAT_MODE | ACTION_SET_SHUFFLE_MODE`。所以在 media
  session 這一層，FMP **收不回**這兩項 —— 與 Windows `SMTCConfig` 沒有對應旗標
  是同一種結構限制。但通知欄的按鈕與 `SKIP_TO_*` / `SEEK_TO` 都正確撤下，而且
  電台期間 `onSetLoopMode` / `onSetShuffleEnabled` 為 null，**跨模式改到音樂
  loop mode 的那個 bug 已經修掉** —— 只是「不宣告」在這一層做不到。
- **擁有權檢查在真機上兩個平台各拍到一次**。Android 這邊是
  `Ignored publishTrack from music; owner is radio` —— 沒有它，音樂請求完成時
  會把歌名蓋到電台的通知欄上。這正是加這道檢查的理由。
- `androidCompactActionIndices` 維持 `null`，按鈕數從 3 掉到 1 沒有任何越界。

**模擬器新陷阱**：Gboard 的「Try out your stylus」教學浮層會攔截
`adb shell input text`，字進了教學的輸入框、FMP 的欄位仍是空的 —— 看起來就像
點擊沒中。截圖才看得出來，按 Cancel 關掉後重打即可。已補進
`.claude/skills/verify-on-device/SKILL.md`。

### 6.6 執行時的失效重核（2026-09-05，Phase 4 步驟 D）

步驟 D（把播放歷史、歌詞自動比對、Mix 預取摘出 `AudioController`）。commit
`76fe5abf`…`d3bed14b`。`audio_provider.dart` **3,436 → 3,209 行**（淨減 227）。

#### 開工重核：三條說法要更正

| # | 原本的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | `:342`：D 的價值是「把副作用從播放路徑上摘下來，**播放不再等它們**」 | **前提已經成立。** 三者當時都已非阻塞：歷史 `Future.microtask`、歌詞 `unawaited`、Mix `unawaited`。唯一 `await` 的是 `_advanceAfterPendingMixLoadMore()`（播到隊尾剛好有預取在飛就等它），那是**刻意的**，而且被 `audio_controller_mix_boundary_test.dart` 的 `completion at mix queue end waits for pending load-more tracks` 鎖住 | D **沒有**動那個 await。價值改述為：縮小 god class、讓三件事可單獨測、拆掉隱藏耦合 |
| 2 | 02 §8.1-D：`abstract interface class PlaybackObserver` ＋ `List<PlaybackObserver>` 廣播 | **三個方法只有一個有人實作。** 三者都只掛「播放請求成功」一個事件；`onTrackEnded` / `onQueuePositionChanged` 零實作。而且 Mix 必須對外曝露進行中的 `Future`，回傳 `void` 的 observer 做不到 | **介面未採用**，改成三個具體協作者，形狀照 `QueueCommands` / `NowPlayingPublisher`。02 §8.1-D 已標註 |
| 3 | — | **`PlaybackSessionCommand.recordHistory` 是死欄位。** 整個 `lib/` 沒有一處讀它；唯一的讀取者是測試裡一行「斷言它 round-trip 回自己」 | 連同那行斷言一起刪 |

另外兩件決定設計的事實：

- **`recordHistory` 這個名字在說謊。** 它同時閘住播放歷史**與**歌詞自動比對
  （`audio_provider.dart` 舊 `:2199`）。這個耦合是對的（重試與啟動還原都不算一次
  新的播放，兩者都不該重跑），但名字讓人以為它只管歷史。改名 `countsAsNewPlay`。
- **`_mixLoadMoreFuture` 與 `MixPlaylistHandler._current` 是兩組必須手動同步的狀態。**
  `_exitMixMode()` 與 `dispose()` 都得記得同時清兩邊。合併成 `MixSessionCoordinator`
  之後 `exit()` 一次做完，這個 bug 形狀消失。

#### 執行中發現

1. **`audio_controller_mix_boundary_test.dart` 的守門斷言差點被自己搬走。**
   它讀 `lib/services/audio/audio_provider.dart` 的原始碼字串，斷言其中不含
   `_queueManager.mixPlaylistId` 等四個 getter。Mix 程式碼搬到新檔之後，這個斷言
   會**變成恆真**——守門形同解除，而且測試照樣是綠的。已改成掃
   `lib/services/audio/` 整個目錄，並加一條 `expect(sources, isNotEmpty)` 防掃空。
   這正是 §Phase 6 那條「掃描型測試的路徑不得硬編」紀律要防的失效模式。
2. **播放歷史在 `AudioController` 這一層本來完全沒有測試。** repository 與 provider
   各有自己的單元測試，中間那條轉接沒有人守。D1 補上（4 條）。
3. **Isar 寫入不能用固定次數的 `pumpEventQueue` 當同步點。** 兩次 `record()` 排出
   兩個序列化的 `writeTxn`，單次 pump 只等得到第一筆 —— 這恰好證明了它不阻塞呼叫端，
   但也意味著測試要輪詢到落地為止。三個新測試檔都用這個模式。
4. **`startMixFromPlaylist` 的第一次抓取與預取用的是同一個 fetcher。** 為了不讓
   `MixTracksFetcher` 同時掛在 controller 與 coordinator 上，coordinator 開了
   `canFetch` / `fetch()`，controller 不再持有 fetcher。

#### 實機驗收（Android 模擬器 `Medium_Phone`，2026-09-05）

三個協作者都用新的 logger tag，實機拍到的就是新程式碼在跑。

| 要驗什麼 | 觀察到什麼 |
|---|---|
| 播放歷史真的有寫 | `[PlayHistoryRecorder] Recorded play history: Cardi B - AH HA…`；播放歷史頁 **11 → 13 首** |
| 啟動還原**不**重複記 | hot restart 走 `_prepareCurrentTrack`（`countsAsNewPlay: false`）→ 仍是 **13 首**，未增加 |
| 歌詞閘門（關閉） | `[LyricsAutoMatchCoordinator] Auto-match lyrics disabled in settings` |
| 歌詞閘門（開啟） | 暫時打開設定後：`[LyricsAutoMatchService] Auto-matching: "AH HA…" by "Cardi B"`，並依使用者的來源優先序打了 Netease |
| **Mix 預取** | `[MixSessionCoordinator] Mix mode: 0 tracks remaining, loading more…` → `Attempt 1/10: using last track as seed` → `adding 11 new tracks`；佇列頁 **25 → 36 → 54 → 67 首**，三輪都在畫面上確認 |
| Mix 還原路徑 | 持久化的 Mix 在 `initialize()` 還原到隊尾時自動排入預取，**不需要播放成功** |

**沒驗到的一項**：`isLoadingMoreMix` 的載入指示器渲染在佇列列表**底部**，而單次抓取
一輪就湊滿，視窗太短沒截到。它的 `[true, false]` 轉換由
`mix_session_coordinator_test.dart` 鎖住，同一組回呼的另一半（`onQueueChanged` →
佇列變長）則在畫面上確認了三次。

**當天的音源狀況（影響可驗範圍）**：Bilibili `playurl` 回 HTTP 412
`request was banned`；YouTube 的 **audio-only** 串流回 `Sign in to confirm you're
not a bot`，但**muxed 串流與所有 metadata API（排行榜、Mix 播放列表、Mix 追加）
完全正常**。所以 Mix 全程可驗，只有純音訊解析被擋。第一輪播放驗證改用本地已下載檔
（`_inspectLocalFiles`，無網路）。

**模擬器新陷阱**：從 snapshot 還原的 `Medium_Phone` 會整個卡死 —— 畫面凍結、
`orca emulator tap` 與 `adb shell input` 都沒有反應、`ax` tree 恆為 `nodes=0`，
連 hot restart 之後畫面都不變，logcat 只留下 `F/bluetooth … on_hardware_error
… code 0x42`。**`-no-snapshot-load` 冷開機即可**；不要在凍結的 snapshot 上耗時間。

**清理**：匯入的測試 Mix 歌單（`RDI-5e_J3LWS8`）已刪除，音樂庫回到原本只有
`DownloadProbe`；「自動匹配歌詞」已切回原本的關閉。**未還原**：驗證用的播放佇列
清空後沒有復原原本那 2 首（原佇列來自更早一輪的 YouTube 排行榜點擊），播放歷史多出
的紀錄也保留著 —— 那些是裝置上真的發生過的播放。

### 6.7 執行時的失效重核（2026-09-06，Phase 4 步驟 C）

步驟 C（拆掉 `_PlaybackContext`，把載入閂存與延後 seek 收進一個協作者）。commit
`c19e505e`…`d8afc346`。`audio_provider.dart` **3,209 → 2,942 行**（淨減 267）。

#### 開工重核：三條說法要更正

| # | 原本的說法 | 實況（file:line） | 處置 |
|---|---|---|---|
| 1 | 「Phase 1 的逾時預算收斂到這裡的單一 `budget`」（`05:343`）、「`budget` 是唯一一個『多久算太久』的定義點」（`02:874`） | **已經做完了。** `PlaybackTimeoutBudget`（`app_constants.dart:191`，`total` 是 `streamResolution + mediaOpen` 的 getter）就是那個定義點；`PlaybackRequestSession` 的 `_budget:177`、`_requestDeadline:180`（`:523`/`:619` 設定）、`_withBudget:716`、`_remainingBudget:735` 已經讓原始一輪與 fallback 共用同一份。commit `262657bc` + `591cb2b0`，由 `playback_request_session_test.dart:500/520/549/593` 釘住 | **C 不碰逾時。** 這一項移出 C 的範圍 |
| 2 | 介面 `abstract interface class PlaybackSessionCoordinator { start / cancel / states }`（`02:866-871`） | **`PlaybackRequestSession` 已經是這個東西**（852 行）：`start:214`、`restore:282`、`cancelActive:206`、`isSuperseded:204`、`dispose:191`。再造一個同名類別只會變成「兩個都叫 session 的東西」；而 `Stream<PlaybackSessionState>` 只會有一個消費者 | **介面不採用**，理由與 D 相同。`02 §8.1-C` 已標註 |
| 3 | 「`_context` 整包搬走」（`02:861`） | **`_PlaybackContext`（`:120-185`）裝的是三件無關的事**：播放模式（28 處）、載入閂存（21 處）、臨時播放快照（21 處）。整包搬會把另外兩件拖進去 | 分三個歸屬：模式留成普通欄位、快照交給 `TemporaryPlayHandler`、閂存與延後 seek 合成 `PlaybackHandoffGate` |

#### 執行中發現

1. **`_context.activeRequestId` 與 `PlaybackRequestSession.activeRequestId` 是同一個
   計數器。** `_enterLoading()`（`playback_request_session.dart:463-470`）做
   `++_requestId` 後把 id 交給 `onLoadingStarted` → `_startSessionLoadingState` 原樣
   存起來。它是**閂存副本**，交接結束歸零 —— 回答「控制器現在為哪一次請求做投影」，
   不是「哪一次才是最新的」。兩者不可互換：`_clearMatchingSessionLoadingContext`
   是唯一以閂存為準的路徑，其餘一律問 `isSuperseded`。
2. **閂存與延後 seek 從來沒有分開改過。** 11 個寫入點（建構子的 `onLoadingFinished`
   閉包、四個起播前導、`_startSessionLoadingState`、`_exitLoadingState`、三個
   `_reset*`）每一個都同時動兩者。這正是 D 在 Mix 上消掉的形狀，所以合成一個
   `PlaybackHandoffGate` 而不是兩個類別。
3. **`state.currentTrack` 是 `playingTrack` 的別名**（`player_state.dart:114`），
   所以 seek 那三處 `?? state.currentTrack?.uniqueKey` 是死程式碼。拿掉之後 gate
   完全不需要 `PlayerState`，這才讓它符合既有協作者的形狀。
4. **`copyWith` 藏了兩個行為**，拆開時必須寫出來：`copyWith(mode: null)` 會保持原
   模式（重試與啟動還原靠它才不會把臨時播放或 Mix 打回 queue）；`clearSavedState`
   會覆蓋另外三個具名參數。兩者都在 commit `f02a2ef5` 裡顯式化。
5. **`_startSessionLoadingState` 刻意只清視窗、不清「下一次要穩定化」旗標**
   （`:1519` 直接 `= null` 而不是呼叫 `_clearSeekStabilizationWindow()`）。gate 因此
   把 `prepareForRequest`（不清旗標）與 `cancel`（清）分成兩個方法，並由
   `playback_handoff_gate_test.dart` 的
   `the stabilize-next flag survives beginRequest but not cancel` 釘住。
6. **`AudioController.seekForward` / `seekBackward` 是死程式碼**，`lib/` 與 `test/`
   都沒有呼叫者。連同 `FmpAudioService` 的兩個介面宣告、`JustAudioService` 與
   `MediaKitAudioService` 的實作、測試 fake 的樁與
   `AppConstants.seekDurationSeconds`，整條鏈都沒有入口 —— 六個檔案 70 行，已在
   第十一輪刪除。

   > **更正（第十一輪）**：本項原本斷言「`audio_handler.dart:59-60` 宣告了
   > `MediaAction.seekForward` / `seekBackward` 但 `FmpAudioHandler` 沒有覆寫
   > `fastForward()` / `rewind()`，所以通知列上那兩個動作按下去沒有任何反應」。
   > **這是錯的。** `FmpAudioHandler` 的宣告是
   > `extends BaseAudioHandler with SeekHandler`（`audio_handler.dart:16`），而
   > `SeekHandler`（`audio_service-0.18.18/lib/audio_service.dart:3220-3260`）
   > 已經實作了那四個方法，全部收斂到 `seek()` —— 而 `seek()` 正是
   > `FmpAudioHandler` 有覆寫的那個。系統動作是通的，能力宣告沒有缺陷。
   > `main.dart:125-126` 的 `fastForwardInterval` / `rewindInterval` 就是餵給
   > `SeekHandler._seekRelative` 的。已在 `audio_handler.dart` 就地加註，避免
   > 下一個讀者重蹈覆轍。

#### 新測試的變異驗證

`playback_handoff_gate_test.dart` 有 11 條在守同一件事：**任何作廢路徑都必須
`complete()`**，否則 `seekTo` 的呼叫端永遠 await 不到。把 `discardPending` 裡的
`pending.complete()` 拿掉重跑，**12 條中有 7 條失敗**（而且是掛住到逾時，不是斷言
失敗），確認這組測試真的守得住。

#### 實機驗收（Android 模擬器 `Medium_Phone`，`-no-snapshot-load` 冷開機）

| 要驗什麼 | 觀察到什麼 |
|---|---|
| 一般 seek（無交接） | 進度條點 75% → 位置 264101ms；點 25% → 87753ms。兩次都精確落在 351–352 秒曲目的對應比例上 |
| **交接期間的 seek 會延後** | `[PlaybackHandoffGate] Deferring seek to 0:01:56.367000 until playback request 2 is ready` |
| **穩定化視窗** | `[PlaybackHandoffGate] Stabilizing seeks for request 2 until …` → `Waiting 0:00:00.498569 before applying deferred seek`（500ms 視窗只剩 498ms） |
| **延後的 seek 落在新歌上** | `[PlaybackHandoffGate] Applying deferred seek to 0:01:56.367000 for request 2`，隨後 `dumpsys media_session` 讀到 132612ms（1:56 ＋ 已播的 16 秒） |
| 臨時播放快照 | `[TemporaryPlayHandler] Saved playback state: index: 0, position: 0:01:18.124453` 等三次，每次都與點擊前一刻的 `dumpsys` 位置吻合 |
| 步驟 D 的協作者沒被弄壞 | `[PlayHistoryRecorder] Recorded play history: …`、`[LyricsAutoMatchCoordinator] Auto-match lyrics disabled in settings` 照常 |

**沒在畫面上捕捉到的一項**：被新請求取代時的 `Discarding deferred seek`。要湊出
「延後中 → 立刻再切一次歌」需要兩次點擊都落在載入視窗內，而模擬器後段對合成點擊
的反應變得不穩（`ax` 樹正常但點擊不進 Flutter view）。這條由
`playback_handoff_gate_test.dart` 的四條作廢測試與既有的端到端
`audio_controller_phase1_test.dart:519` 覆蓋。

#### 順手發現的既有缺陷（**不是 C 造成的**）

**臨時播放按「下一首」返回佇列時，還原有機率卡在載入中**：mini player 的播放鍵變成
無限轉圈，通知列位置停在 0，`_restoreSavedState` 只印出 `started` 而沒有
`completed successfully`。log 停在
`PlaybackRequestSession: Restoring queue track` → `JustAudioService: File set` →
`playing=true, ready`，之後就沒有下文 —— `restore()` 的 future 沒有回來。

**A/B 驗證**：把工作區切到步驟 C 之前的 `29eaaad6` 熱重啟後跑同一組操作，
**症狀完全相同**（log 最後一行是舊的 `[AudioController] Saved playback state` tag，
證明跑的是舊 build；位置同樣停在 0、轉圈同樣不停）。所以這是既有缺陷，應另開 issue
追蹤，不在 C 的範圍。

#### 誠實的預期：Phase 4 的驗收線需要重述

**C 做完是 2,942 行，離 ≤800 還差 2,140 行，而路線圖的 A–E 五步到此就用完了。**
實測目前的行數分布（`AudioController` 本體）：

| 群 | ~行數 | 狀態 |
|---|---|---|
| 後端事件處理與失敗分類（`_onPlayerStateChanged` / `_onPositionChanged` / `_onTrackCompleted` / `_onPlaybackEnded` / `_onTransportFailure` / `_onBufferStarvation` / 輸出裝置） | 420 | 未規劃 |
| 起播命令與 transport（play\* / playAt / next / previous / 音量 / 靜音 / 循環 / 裝置） | 500 | 大部分該留 |
| 啟動與還原（`initialize` / `_prepareCurrentTrack` / `_restoreQueuePlayback` / `_restoreSavedState` / `returnFromRadio`） | 370 | 未規劃 |
| `_executePlayRequest` 與音源錯誤處理 | 215 | 未規劃 |
| 重試階梯投影 | 168 | 未規劃 |
| `PlayerState` / `QueueState` 投影助手 | 190 | 該留（就是投影本身） |
| Mix 起播與退出 | 156 | 該留 |
| 載入狀態投影與 publisher | 120 | 該留 |
| 錯誤 → toast 翻譯 | 91 | 未規劃 |
| 同檔案裡不屬於 controller 的（`QueueState` ＋ 12 個 provider） | 230 | **純檔案切分即可** |

要接近 800 至少還需要：

- **最便宜的 230 行根本不是重構** —— 把 `QueueState` ＋ `queueStateProvider` 移到
  `queue_state.dart`、12 個 provider 移到 `audio_providers.dart`，零行為變更，
  搬走的行數比 C 還多。建議優先做。
- **F — `PlaybackEventRouter`**（後端事件，約 −300）：注意它**無法照既有協作者的
  規矩寫** —— 那些 handler 本身就是 `PlayerState` 投影，要嘛讓它吐 typed intent 由
  controller 重播，那是新的設計決定，不是位移。
- **G — `PlaybackStartupRestorer`**（啟動與還原，約 −320）
- **H — `PlaybackErrorPresenter`**（錯誤翻譯，約 −140）

三步加檔案切分之後樂觀估計 **1,000–1,200 行**。**≤800 只有在投影本身被重構
（`02 §8.1-F` 的 `_project()`）之後才可能成立，Phase 4 的驗收線應該按這個重述。**

### 6.8 執行時的失效重核（2026-09-06，Phase 4 步驟 F / G / H 與檔案切分）

commit `b952ccdf`…`fd8a64b6`。`audio_provider.dart` **2,942 → 2,573 行**（淨減 369）。
測試 1,382 → 1,408。

#### 開工重核：F 與 G 都寫不出來，H 只有一半能寫

路線圖 §6.7 把剩下的三步估成 F −300、G −320、H −140。逐項量過之後：

| 步 | 原估 | 實際可搬 | 為什麼 |
|---|---|---|---|
| **H** | −140 | **−87** | 「錯誤 → 文案」可以整包搬；`_handleSourceError` 不行 —— 它跳下一首、停後端、寫 `state.error`，那是**用**結論不是**得出**結論 |
| **G** | −320 | **−16** | 見下表：345 行引用了 **41 個**控制器成員 |
| **F** | −300 | **−7** | 167 行引用了 **29 個**控制器成員 |

判準不是感覺，是「要注入幾個回呼」。既有五個協作者的實測值：

| 協作者 | 建構子注入的外部相依 |
|---|---|
| `EffectivePlaybackState` | 0（純值） |
| `PlaybackErrorPresenter` | 0（純函數） |
| `PlaybackHandoffGate` | 3 |
| `MixSessionCoordinator` | 5 |
| **`PlaybackEventRouter`（F，若要寫）** | **約 15** |
| **`PlaybackStartupRestorer`（G，若要寫）** | **約 26** |

15 個回呼的建構子不是邊界，是把控制器換個名字再傳一次。這兩步**不執行**，改成
只取其中真正獨立的部分。

#### 實際做了什麼

1. **issue #54 的根因與修法**（`b952ccdf`）—— 不是重構題目，是查步驟 C 的實機
   異常時挖出來的：`_waitForRequestOperation` 只在 `phase != null` 時套預算，而
   `_executeQueueRestore` 的 `setMedia` / `seekTo` / `play` **三個都沒傳**。後端
   任一個 future 不回來，`restore()` 就永遠不返回 → 呼叫端 `requestId` 停在
   `null` → `finally` 的 `_resetLoadingState` 不執行 → 轉圈到天荒地老。
   Phase 1 的 `637aa276` 只覆蓋了一般起播路徑。三條新測試各對一個等待點，把
   `phase:` 拿掉重跑會**各掛住 30 秒到逾時**。
2. **死路徑刪除**（`6175812d`）—— `seekForward` / `seekBackward` 從控制器、
   `FmpAudioService` 介面、兩個後端實作、測試 fake 到
   `AppConstants.seekDurationSeconds`，六個檔案 70 行，全鏈無呼叫者。
3. **純檔案切分**（`34daba59`，−244）—— `QueueState` ＋ `queueStateProvider` 出去
   成 `queue_state.dart`；5 個建構 provider 進
   `lib/providers/audio/audio_controller_provider.dart`；9 個衍生 provider 併入既
   有的 `audio_player_selectors.dart`。**沒有留 re-export**：43 個匯入端逐一改
   完，編譯器全程覆蓋。
4. **H —— `PlaybackErrorPresenter`**（`74c50fb0`，−87）。
5. **Mix 還原歸位**（`7d197130`，−16）—— `mixPlaylistId` / `mixSeedVideoId` /
   `mixTitle` 在 `MixSessionCoordinator` 之外的最後一個讀取點收掉了。
6. **F 唯一真正能抽的東西**（`fd8a64b6`）—— `EffectivePlaybackState`。

#### 更正 §6.7 的一項

§6.7 執行中發現第 6 項斷言通知列的快轉／倒退「按下去沒有任何反應」。**那是錯的**，
已就地更正：`FmpAudioHandler` mix 了 `SeekHandler`，那四個方法都有實作。原本要
為此開的 issue 沒有開。

#### 順手守到的兩個洞

- **`audio_error_kind_structure_test.dart` 會變成恆真**：它比對
  `audio_provider.dart` 裡的字面簽名，分類器搬走之後三條斷言全部失效而測試仍綠。
  改成掃整個 `lib/services/audio/` 找字串分類器，正向行為交給
  `playback_error_presenter_test.dart` 用真的例外物件釘。
- **`source_ownership_phase3_test.dart` 的檢查清單**：`mixTracksFetcher` 的接線
  搬到 `audio_controller_provider.dart` 之後，臨時 `new YouTubeSource(` 最可能長
  回來的地方變成它，已加進清單。

#### 沒有測試守著的一條規則，現在有了

`AGENTS.md` 的 Platform Split 寫著「控制器擁有的載入階段，後端 idle 事件不得覆蓋
loading 狀態」，程式碼註釋還記著「過去 SMTC 收的是後端原始值，這條只在 Android
成立」。**這條規則一個測試都沒有**，只活在 `_onPlayerStateChanged` 的三個區域變數
裡。抽成 `EffectivePlaybackState.from` 之後由 7 條測試釘住。

#### 實機驗收（Android 模擬器 `Medium_Phone`，`-no-snapshot-load` 冷開機）

| 要驗什麼 | 觀察到什麼 |
|---|---|
| **`EffectivePlaybackState` 把後端 idle 改寫成 loading** | 切歌時 log 連兩行 `PlayerState changed: playing=false, processingState=idle`（控制器自己的 `stop()`），同一時間 `dumpsys media_session` 連六次都讀到 **`state=CONNECTING(8), position=0`** —— 不是 `STOPPED`，位置也沒殘留上一首。這正是 `AGENTS.md` 寫了很久卻沒有測試的那條規則 |
| 交接完成後回到播放 | 22 秒後 `state=PLAYING(3), position=20696`；8 秒間隔的兩次取樣 34241 → 42041 |
| **檔案切分沒有拆斷投影** | 加三首進佇列 → 佇列頁渲染「正在播放第 3 首／共 3 首」與三個列項；mini player 的「上一首」「下一首」由 `click=False` 變 `click=True`（`QueueState.canPlayPrevious/canPlayNext` 經搬到 `queue_state.dart` 的 `queueStateProvider` 走完整條路） |
| **`PlaybackErrorPresenter.shouldRetrySource` 分類正確** | 飛航模式下播 YouTube 曲目 → `Scheduling retry 1/5` … `5/5` → `Max retry attempts reached`，退避階梯完整跑完 |
| 失敗後載入狀態有清掉 | 重試耗盡後 mini player 的轉圈變回 ▶（截圖），沒有卡住 —— issue #54 的症狀類別 |
| 錯誤 toast 有渲染 | 限流：橘色警告「請求過於頻繁，請稍後再試」（`rateLimited` 分支，不經 presenter，作為對照組）；離線：紅色「播放失敗: 这次是真玩爽了」 |

**沒能在裝置上構到的一項**：presenter 自己產的文案（`cannotPlay` /
`playbackFailed`）。網路錯誤是可重試的，走退避階梯，耗盡之後不經過
`_handleSourceError`；要觸發得有一支**地區限制或 VIP** 的影片，這台模擬器上沒有
穩定的來源。這條由 `playback_error_presenter_test.dart` 的 12 條測試覆蓋 ——
它們斷言的是「挑了哪一個 i18n key」，不是字面文字。

**Mix 還原（`7d197130`）沒有做實機驗收**，因為它對外行為零變化：原本的 `if` 也
是三個欄位缺一就整段不做，搬進 `MixSessionCoordinator.restoreFrom` 之後判斷完全
相同，由三條新測試逐欄位釘住。

裝置狀態已還原：佇列清空（確認顯示「播放佇列為空」）、飛航模式關閉、Orca 終端
關閉、`adb emu kill`、`adb devices` 為空且無殘留 emulator 行程。本輪驗收過程新增
的播放歷史列沒有清除。

#### 誠實的行數帳（取代 §6.7 的估算）

| 群 | ~行數 | 狀態 |
|---|---|---|
| 起播命令與 transport | 500 | 該留 |
| 啟動與還原 | 345 | **G 寫不出來**（41 個相依） |
| `PlayerState` / `QueueState` 投影助手 | 190 | 該留（就是投影本身） |
| 後端事件處理 | 167 | **F 寫不出來**（29 個相依） |
| 重試階梯投影 | 168 | 未評估 |
| Mix 起播與退出 | 140 | 該留 |
| `_executePlayRequest` | 130 | 該留 |
| 載入狀態投影與 publisher | 120 | 該留 |

**≤800 不可能靠繼續抽協作者達成。** 剩下的 2,573 行有 1,080 行是投影與 transport
命令 —— 它們就是 `AudioController` 這個類別的定義。要再往下只有兩條路，兩條都是
改變控制器**是什麼**，不是把東西搬出去：

- **拆 `PlayerState` 本身**（`02 §8.1-F` 的 `_project()`）：把播放狀態拆成幾個各自
  獨立的 notifier，投影助手才有地方去。
- **`StateNotifier` → `Notifier` 改寫**（路線圖同節已列）：Riverpod 3 的 `Notifier`
  可以把 `ref` 拿進來，起播 provider 的接線就不必全擠在 provider 工廠裡。

**Phase 4 的驗收線應該重述為：`AudioController` 不再持有任何可以獨立測試的規則。**
以行數計已經沒有意義 —— 這一輪搬走的 369 行裡，真正的邊界改善（H、Mix、
`EffectivePlaybackState`）只有 110 行，其餘 259 行是檔案切分與刪死碼。

### 6.9 Phase 1–4 收尾複審（2026-09-06）

commit `eeca7dd5`…`312c803d`。全面複審 Phase 1–4 之後補的五件事。
`audio_provider.dart` 2,573 → 2,561 行，`player_state.dart` 222 → 163 行。
測試 1,408 → 1,409（`main` 基準；`feat/phase-5-ui-ux` 另有排行榜的 +2）。

#### 複審確認成立的部分

- **Phase 3 的驗收超標**：`rg "\bisar\.[a-z]|_isar\.[a-z]"` 在 repository 之外
  從 152 降到 **21**（目標 < 60），而那 21 筆全是 `import 'package:isar_community/isar.dart'`
  這種 import 行 —— 真正的 `isar.<method>` 呼叫是 **0**。
- **協作者模式統一**：11 個新檔的形狀一致，跨 6 個協作者共注入 13 個函數參數。
  11 個裡 10 個在 `lib/services/audio/AGENTS.md` 的 Ownership 有專屬條目。
- **偏離計劃有寫理由**：Riverpod 3 的 auto-retry，計劃寫「26 個 `FutureProvider`
  逐一決定」，實際是 `main.dart:192` 一個全域關閉，理由寫在程式碼註釋與
  `lib/providers/AGENTS.md:81`。

#### 補上的五件事

1. **階段章節從未標記已執行**（`eeca7dd5`）。§6.2–§6.8 共約 600 行執行記錄修正的
   是階段表的內容，但只有 Phase 2 有「已執行 ＋ 見 §6.3」的回指。Phase 1、3、4
   沒有，讀者翻到階段表看到的是原計劃，要往下 1,300 行才會知道被推翻過。
   三個章節補上標記。**Phase 4 的 ≤800 行驗收線改成刪除線 ＋ §6.8 的重述**，
   並註明本節列出但未開始的兩項（`Notifier` 改寫、`setQueue` / `supportsQueue`）。

2. **文檔說「兩個 request-id 述詞」，實際有三個**（`eeca7dd5`）。
   `AudioController._navRequestId`（`:76`、`:892-945`）就是一個 raw 計數器，而
   同一節寫著「不要新增 raw request-id 計數器」。它早於 session（`b9b4d6b2`），
   守的是 `next()` / `previous()` 在拿到 session id 之前的那段 await 視窗。
   `AGENTS.md` 補上它，並說明為什麼不併進來。

3. **控制器同時講簡體和繁體**（`1f7cb99b`）。Phase 4 寫了 11 個全繁體的協作者檔，
   留下的控制器是 190 簡 / 152 繁，相鄰的區塊標題用不同字體。133 行註釋轉繁，
   **只動註釋**。用語照 `lib/` 既有多數：佇列 86/23、網路 28/8、音訊 31/9、
   點擊 37/1、回呼 17/5、台 363/0。OpenCC `s2twp` 前五個對、最後一個錯
   （會轉成「臺」），並且會把「只」誤轉成「隻」—— 兩者一律還原。
   已經是繁體的註釋一律跳過，否則「回調」會被改成「回撥」。

4. **兩個抽取殘留**（`d240c431`）。`PlaybackHandoffGate.clearStabilizationWindow`
   在步驟 C 的計劃裡是公開 API，實際接線沒用到，四個呼叫者全在類別內 → 改私有。
   `onLoadingFinished` 用兩個並列 `if` 測同一個 `result.isSuperseded` → 一個
   guard ＋ 一個巢狀分支。

5. **★`QueueState` 是投影的第二份副本**（`312c803d`）。這是本次複審最實在的一項。

#### 第 5 項：兩份佇列投影

`QueueState` 的 12 個欄位**全部**同時存在於 `PlayerState`，零個獨有。
`_updateQueueState()` 一次寫兩份，而 `_createQueueStateFromCurrentState()` 是逐欄位
從 `state` 抄過去。消費端因此裂成兩邊：

| 讀 `queueStateProvider` | 讀 `PlayerState` |
|---|---|
| `queueProvider` `queueVersionProvider` `queueTrackProvider` | `isShuffleEnabledProvider` `loopModeProvider`、`mini_player.dart:329-337`、`player_page.dart:93-100`、`home_page.dart:1124/1173`、`track_detail_panel.dart:756` |

**這個重複早於 Phase 1**（`9f2bed8f:55` 就有 `class QueueState`），Phase 4 沒有製造
它，只是把它搬進獨立檔案。問題是搬的同時寫了一段程式碼並不支持的理由 ——
`queue_state.dart` 與 `AGENTS.md` 都說「Deliberately separate from `PlayerState`…
merging them would rebuild every queue list on the once-a-second position tick」。
它們不是分開的，是重複的；而且 `PlayerState` 仍帶著 `queue` 與 `upcomingTracks`，
那個效能理由沒有兌現。`QueueState.copyWith` 的 `clearMixTitle` 當時也沒有呼叫者。

修法採「刪掉舊路徑」而不是改文案：`PlayerState` 的 12 個欄位全部刪除，
控制器改持有 `QueueState _queueState` 並用 `_emitQueueState()` 單點寫入，
`_createQueueStateFromCurrentState()` 刪除。新增 `AudioController.queueState`
唯讀 getter 給不架 container 的呼叫端。選擇器補 `upcomingTracksProvider` 與
`queueControlStateProvider`（後者讓播放控制列一次讀完五個佇列欄位，
取代 mini player 原本的五次 `.select`）。

**順手修掉一個時序缺陷**：`toggleShuffle` / `setLoopMode` / `cycleLoopMode` 過去只寫
`PlayerState`，`queueStateProvider` 要等 `QueueManager.stateStream` 的下一次事件才會
跟上。現在是同步送出。

`analysis_options.yaml` 排除 `test/**`，所以 `flutter analyze` 全綠時 7 個測試檔仍
編不過 —— 這個陷阱又踩到一次，唯一的守門是實際跑測試。原本釘住這份重複的測試
（`queueProvider follows queueStateProvider instead of PlayerState queue`）改寫成
反向守門 `PlayerState declares none of the queue fields`。

#### 實機驗收（Android，`-no-snapshot-load` 冷開機）

`Medium_Phone`（1080×2400，繁中）：

| 要驗什麼 | 觀察到什麼 |
|---|---|
| `queueControlStateProvider` 的 shuffle / loop | mini player「順序播放」→ 點一下變「隨機播放」；「單曲循環」→ 點一下變「不循環」。這正是 `toggleShuffle` / `cycleLoopMode` 改成同步送出的那條路徑 |
| 播放頁讀同一份 | 展開播放頁顯示「隨機播放」「不循環」，與 mini player 一致 |
| `queueStateProvider.queue` / `currentIndex` | 佇列頁「正在播放第 1 首／共 2 首」＋兩個列項 |
| `upcomingTracksProvider` | 首頁「接下來播放」渲染佇列裡的兩首 |
| 脫離佇列分支 | 第三次點選誤中「播放」→ log `isPlayingOutOfQueue: true`，佇列投影與 playingTrack 刻意不一致，兩者各自正確 |
| `canPlayPrevious` / `canPlayNext` | 脫離佇列且佇列非空 → 上一首／下一首皆 `click=True` |

`Medium_Tablet`（2560×1600 橫向 = 1280dp，英文）：

| 要驗什麼 | 觀察到什麼 |
|---|---|
| 空佇列的能力投影 | 佇列只有 1 首時 `Previous` / `Next` 為 `click=False`；加到 3 首後翻成 `click=True` |
| **`track_detail_panel` 的下一首**（只在 desktop 佈局出現，≥1200dp） | 播 JENNIE、佇列有 3 首 → 右側面板渲染 `Next / DECO*27 - 洗脳 feat. 初音未来`，即 `queueStateProvider.upcomingTracks.first` |
| 佇列頁 | `Now playing #1 / 3 tracks` ＋三個列項 |

**沒能驗到的一項**：`radio_controller.dart:1004` 的
`_ref.read(queueStateProvider).currentIndex`。這台 AVD 沒有電台，而 Bilibili 整輪
都在 HTTP 412 `request was banned` 風控狀態（log 可見），加不了直播間，
電台返回那條路徑構不到。它是同一個值換讀取來源的一行改動，由編譯器覆蓋，
`queueStateProvider` 本身則由上面每一條驗證證明是活的。

另外，平板上的彈出選單 **uiautomator 取不到**（`orca emulator ax` 完全看不到
`MenuItem`，截圖裡選單是開著的），要靠截圖定座標再 `adb shell input tap` 驅動。
這一點記進 `verify-on-device` 的限制。

裝置狀態已還原：兩台的佇列都清空（確認顯示「播放佇列為空」／`Queue is empty`）、
旋轉設定復原、Orca 終端關閉、`adb emu kill`、`adb devices` 為空且無殘留
emulator 行程。本輪新增的播放歷史列沒有清除。

---

### 6.10 執行時的失效重核（2026-09-06 / 07，Phase 5a 剩餘三項 + 5g）

commit `0483bf8b`…`2421f73d`。測試 1,411 → 1,429。`flutter analyze` 全綠。
本輪清掉全部剩餘 P0（P0-2 / P0-3 / P0-4）並把原始例外擋在 UI 之外（P1-7）。

#### 五條說法要更正

| # | 原本的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | 「9 處 `.when(error:)` 吞錯誤，8 處連 log 都沒有」（`05:391`、`04 §4.2`） | `lib/` 共 **21** 個 `.when(error:)` 呼叫點：**10 個吞掉**（04 的表漏了 `add_to_playlist_dialog.dart:291`）、2 個是 provider 轉包、9 個有顯示給使用者（其中只有 3 個走共用 `ErrorDisplay`）。吞掉的 10 個裡有 2 個 `debugPrint` —— 而 `debugPrint` **進不了 App 內的日誌檢視頁**，只有 `AppLogger` 會 | 處理 10 個，`debugPrint` 一併改掉 |
| 2 | 「9 個檔把 `e.toString()` 直接顯示給使用者」（`05:391`、`04 §4.3`） | 追到真正的 UI sink 之後是 UI 層 27 處、provider 層 27 處、service 層 3 處，**合計約 54 個呼叫點、33 個檔** | 5g 從 M 改判為 **L**，拆成三個 commit |
| 3 | 「27 個 `IconButton` 缺 tooltip」「`semanticFormatterCallback` 缺」（5f ②③） | **已經不成立。** 97 個 `IconButton` 只有 1 個沒有 `tooltip:`，而那一個（`lyrics_title_bar.dart:188`）用 `ExcludeSemantics` + `Semantics(button:, label:)` 手動補齊。`semanticFormatterCallback` 在 `player_page.dart:529` 已經有了 | **5f 縮到只剩兩項**：迷你播放器手刻 seek bar（`mini_player.dart:147-253`，仍無 `Semantics`）＋ 一條 `meetsGuideline` 冒煙測試 |
| 4 | 「`app_theme.dart` 逐字重複約 85 行」「260 個 `EdgeInsets`」 | 重複區塊是 **71 行且逐位元組相同**（`:124-194` vs `:219-289`）；`EdgeInsets` 是 **312 個構造呼叫、79 個檔**，其中約 76% 的數值本來就落在 4/8/12/16/24/32 | 本輪不做 5b，數字改對，並補 §5.2 的 04-D10 |
| 5 | `lib/ui/AGENTS.md:16-18`：「三個版面欄位刻意**不**進備份」 | **與程式碼相反。** `6efcefc7` 已經把它們加進備份，理由寫在 commit message 裡，AGENTS.md 沒跟著改 | 規則檔過期比沒有規則危險，本輪改正 |

#### 設計上的一件事：映射層已經存在，只是被關在播放層

`PlaybackErrorPresenter.reasonFor` 是一個對 `SourceErrorKind` 的窮舉 switch，
接了 8 個翻譯鍵、有低訊號過濾與合成診斷抑制 —— 而登入頁、搜尋、匯入、歌單對話框
全都在問同一個問題卻各自 `e.toString()`。第二份會漂移，所以**措辭那一半搬到
`lib/core/errors/user_message.dart`**，presenter 只轉發。

這推翻了 presenter 自己在 Phase 4 步驟 H 寫下的理由（「拆開會讓下一次新增 kind
的人改一半就走」）：重試判斷本來就是 `SourceErrorKind.isRetryable` /
`.shouldSkipTrack` 兩個 getter，住在 `source_exception.dart` 的 enum 上，
presenter 只是轉發；而措辭的 switch 是窮舉的，少一個 kind 分析器會先擋下來。
註釋改寫成新的理由，不是刪掉。

`lib/core` 可以 import `lib/data`（既有 3 個檔這樣做）但從不 import
`lib/services`，所以映射層放 `lib/core/errors/` 拿得到 `SourceApiException`，
而 `ToastService`（也在 `lib/core/services/`）可以直接用它。

#### 實機驗收抓到的兩個漏網路徑

**只掃 `lib/ui` 的 sweep 是不夠的。** Android 模擬器上關掉網路搜尋，畫面印出的是：

```
bilibili: BilibiliApiException(-2): 網路連線失敗
netease: NeteaseApiException(-998): 網路連線失敗
youtube: YouTubeApiException(search_error): Search failed: ClientException with
SocketException: Failed host lookup: 'www.youtube.com' ... uri=https://www.youtube.com/results?search_query=hello
```

兩個成因都在 UI 之外：

1. `search_service.dart:113` 用 `errors.add('$type: ${e.toString()}')` 組出整段
   文字，而那段文字會原封不動畫進搜尋頁的 `ErrorDisplay`。
2. YouTube adapter 的搜尋 catch 把底層例外包成 `message: 'Search failed: $e'`，
   而 `sourceErrorReason` 會把 adapter 的 `message` 當成「有意義的診斷」照顯示。
   同一個檔案裡本來就有一個分類器（`_classifyStreamFallbackError`，只用在串流
   fallback），改名為 `_classifySourceError` 並讓搜尋也走它。

修完之後同一條路徑是 `bilibili: 網路連線失敗 / netease: 網路連線失敗 /
youtube: 網路連線失敗`，而完整原文（含 URL）仍在 log 裡。
**靜態規則因此擴大到掃整個 `lib/`**，不只 `lib/ui`。

第三個：電台播放失敗的 toast 是一整條五行的 `DioException`（含
`api.live.bilibili.com`）。那是一個沒有被任何 adapter 包成 `SourceApiException`
的裸 `DioException`，`userMessageFor` 認不得它而退回「未知錯誤」。Dio 是全 App
的 HTTP 層，裸的 `DioException` 逃到 UI 是常態不是例外，所以 `userMessageFor`
接上 `classifyDioError`（adapter 用的同一份），toast 變成
**「播放失敗: 網路連線失敗」**。

#### 靜態規則

新檔 `test/ui/static_rules/error_presentation_static_rule_test.dart`，三條：
`lib/ui` 的 async error 分支不得回傳 `SizedBox.shrink()`；`lib/` 全樹的
`t.x(error: …)` 不得收到原始例外；`lib/ui` 的 `ToastService.*` /
`ErrorDisplay(message:)` 引數不得含 `e.toString()`。
**三條都用刻意寫的違規檔驗證過會失敗**，不是「跑起來是綠的」就算數。

**沒有採用** 04 §10.5-1 的「`Center`+`Column`+`Icon`+`Text` 不得繞過
`ErrorDisplay`」：樹上還有 17 處手刻空狀態，那條規則上線就要嘛一次改完 17 處
（超出本輪），要嘛帶一份 17 筆白名單（AGENTS.md 明文反對的平行清單）。

#### 實機驗收

**Android（`Medium_Phone`，冷開機 `-no-snapshot-load`）** ——
錯誤路徑靠 `adb shell svc wifi disable && svc data disable` 誘發：

| 要驗什麼 | 觀察到什麼 |
|---|---|
| 搜尋失敗的錯誤區塊 | 修前：三段原文含 `ClientException`、`SocketException` 與完整 URL。修後：`bilibili: 網路連線失敗 / netease: 網路連線失敗 / youtube: 網路連線失敗` |
| 原文有沒有留下 | log 裡仍有完整的 `ClientException with SocketException: Failed host lookup: 'www.youtube.com' ... uri=…`，並帶 `[ERROR] [Search] Searching youtube failed` |
| 電台播放失敗的 toast | 修前：五行 `DioException [connection error] … api.live.bilibili.com`。修後：**「播放失敗: 網路連線失敗」** 一行 |
| 恢復網路後沒有回歸 | 同一條搜尋回 43 筆線上結果；首頁三個排行榜音源都在 |

**Windows（P0-4 是 Windows-only，Android 構不到）**：播一首沒有歌詞匹配的曲目
→ Detail Panel 切歌詞模式顯示「暫無歌詞」→ 開浮動歌詞視窗 →
**視窗同樣顯示「暫無歌詞」**，與面板一致（修前會永遠停在「等待歌詞…」）。

**驗不到的三項，照實記錄**：

- **P0-2**（下載管理員的 error 分支）要 `trackByIdProvider` 這一次 Isar 讀取真的
  拋例外才會出現，裝置上沒有安全的誘發方式（Isar 寫爆是 §4.8 那顆雷）。只有
  widget 測試覆蓋，實機只確認正常列沒有回歸。
- **P0-3 的三個區塊級分支**（首頁歌單／最近播放／播放歷史統計）讀的都是本地
  Isar，關網路對它們沒有作用，一樣構不到。同樣只有測試覆蓋。
- **P0-4 的反向情況**（有歌詞的曲目仍正常渲染歌詞）沒驗到：Orca 在會話中途丟失
  了 FMP 主視窗的 UIA handle，而 Win32 合成點擊送不進 Flutter view；能構到的
  排行榜曲目在這台機器上都沒有歌詞匹配。

順帶記進 `verify-on-device`：`adb shell am force-stop` 會把 `flutter run` 的連線
斷掉，之後每一次 hot restart 都是**靜默的空操作** —— 本輪因此拍到兩張修前行為的
截圖，差點被當成修不好。終端只印一次 `Lost connection to device.` 就沒了。

裝置狀態：Android 模擬器已 `adb emu kill`、`adb devices` 為空、無殘留行程，
網路已恢復。Windows 的 FMP 已 `q` 結束、視窗幾何還原成原本的 640,296 1280x800；
本輪在這台機器上播過兩首歌，播放佇列與播放歷史因此各多了記錄，未清除。
過程中誤點開了使用者的記事本設定頁，已導覽回文件，未更動任何設定。

### 6.11 執行時的失效重核（2026-09-07，Phase 5b–5f）

commit `81d8fc1f`…`063a5b73`。測試 1,429 → 1,459。`flutter analyze` 全綠。
本輪把 Phase 5 剩下的五個子項一次做完，Phase 5 收尾。

#### 八條說法要更正

| # | 原本的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | 5a① 是「改用容器級 `columnsFor(constraints.maxWidth)` —— 一行修法」，已由 `9557e03f` 完成 | **兩處都不對。** `columnsFor` 這個名字**全樹不存在**；`LayoutBuilder` + `constraints.maxWidth` 在 `9557e03f` **之前就有**（`git show 9557e03f^` 可證）。那個 commit 做的是「放不下換行而不是丟掉」＋把 inline 的斷點 switch 抽成具名的 `rankingColumnsFor`，而且註釋明說欄數刻意不改。容器級的「量測」是舊的，容器級的「函式名」是新的，它查的門檻仍然是視窗級的 600/1200 | 5c 要做的分離本輪才做 |
| 2 | 「312 個 `EdgeInsets`、79 個檔」 | 嚴格的構造呼叫是 **260 處 / 71 檔**（symmetric 99、all 74、only 48、fromLTRB 39）；312 = 260 + 52 個 `EdgeInsets.zero`。**76% 落在 4/8/12/16/24/32 是精確的**（347/457 個數值引數 = 75.9%） | 數字改對，04-D10 不變 |
| 3 | 5b 要建 `AppMotion`，因為有「13 個 inline `Curves.*`」 | **前提只成立一半。** 時長早就 token 化：`AnimationDurations` 被 19 個檔、36 處使用，`lib/ui` 只剩 17 處字面值而其中 10 處在同一個 debug 頁。曲線確實是 13 處、4 個值 | **不建。** 記為 04-D11 |
| 4 | 「`app_theme.dart` 逐字重複 71 行」，檔案在 `lib/core/theme/` | 檔案在 **`lib/ui/theme/app_theme.dart`**。重複的不只 71 行：`lightTheme` 與 `darkTheme` 兩個 93 行的函式**全文只差三行**，而其中兩行是同一個 `Brightness`（一次給 `_colorScheme`，一次多餘地給 `ThemeData`） | 不是抽 sub-theme，是整個函式體收成一個私有建構器（−97/+27） |
| 5 | 04 §5.2：「兩個全螢幕播放頁的主播放／暫停鍵完全沒有語意標籤」 | **已失效。** `PlayerPlayPauseButton` 的四個呼叫點現在都傳了 `tooltip` | 5f 只剩迷你播放器那一條進度條 ＋ 冒煙測試 |
| 6 | `repairSettingsInvariants` 會「夾住」不合法的面板寬度 | 它是**重設為預設值**，不是夾到邊界（`9999 → 380`），而 `database_migration_test.dart:370` 把這個行為釘住了 | 下限提到 320 時，停在 280–319 的使用者會被重設而不是變成 320 —— 本輪改成 clamp，並補兩條測試 |
| 7 | — | `LayoutSettingsState.isLoaded` **寫了但全樹沒有人讀** | 刪掉 |
| 8 | — | `responsive_scaffold.dart` 的註釋說收起寬度是 48/120，程式碼是 **36/54**（還重複了一行）；`Expanded(flex: 2)` 與播放頁的 `Expanded(flex: 3)` 都是各自 `Row`/`Column` 裡唯一的 flex child，flex 值無作用 | 順手改正 |

#### 執行中發現

- **`columnsFor` 的常數不是自由的。** `(w / 400).floor().clamp(1, 3)` 精確重現
  `home_ranking_sources_test.dart` 現有的四條斷言（1200→3、868→2、800→2、
  599→1），所以那六條測試一行不改就是這一步的驗收。04 §10.2 提的
  `idealColumn = 420` 會讓 800→1，直接弄紅測試。**唯一刻意的差異**在容器寬
  600–799 這一帶：2 欄變 1 欄（兩個 300dp 的排行榜欄位低於卡片的舒適寬度）。
- **「預設寬度 `min(412, 視窗寬/4)`」不需要存在。** 現有 schema 的
  `double detailPanelWidth = 380` 不可為 null，沒有「使用者從未選過」的哨兵值，
  而加一個欄位還會踩 `settings_backup_coverage_static_rule_test.dart`。但加上
  渲染期的 40% 夾擠之後這個公式就多餘了：存 412、在 840dp 視窗上渲染成 336
  （= 840 × 0.4），結果與公式一致。**所以不加欄位。**
- **`AppLayout` 搬進自己的檔案。** 面板界限同時被 UI 層（拖曳與渲染）和資料層
  （`repairSettingsInvariants`、備份 DTO）讀取，而 `ui_constants.dart` import
  了 `package:flutter/material.dart`。`lib/core/constants/app_layout.dart` 只
  import `dart:math`，資料層才共用得到同一組數字，不必再抄一份 280/500。
- **`Semantics(slider:)` 少了 `container: true` 會併進按鈕節點。** 沒有它，
  迷你播放器的語意樹上會出現**一個同時是 button 又是 slider、標籤是兩句話黏
  在一起**的節點（`label: "Open player\nPlayback progress"`）。實際 dump 出來
  才看到。順帶：`find.bySemanticsLabel` 找不到「不擁有節點」的標註，所以那條
  測試一開始怎麼寫都找不到東西。
- **兩條 guideline 都用刻意的回歸驗證過會失敗**：把迷你播放器高度從 64 改成
  20 → `androidTapTargetGuideline` 紅；拿掉 `label:` → `labeledTapTargetGuideline`
  紅。不是「跑起來是綠的」就算數。

#### 實機驗收（Android 模擬器）

`Medium_Phone`（411dp）與 `Medium_Tablet`（1280×800dp，並用
`adb shell wm size` + 重啟 App 覆蓋其餘級距）。**本輪沒有 Windows 專屬的改動**，
`_ExpandedLayout` 由寬度斷點選出、與平台無關，所以只驗 Android。

| 視窗 | WindowClass | 觀察到什麼 |
|---|---|---|
| 411 × 914 | `compact` | 底部導覽**五個**分頁（`第 N 個分頁 (共 5 個)`），沒有「設定」；首頁右上角的「設定」按鈕進得去設定頁，而且**高亮留在首頁**；迷你播放器的進度條在 uiautomator 上是 `android.widget.SeekBar`、`focusable=true`、`content-desc="0:52, 播放進度"` —— 改動前這個節點**完全不存在** |
| 720 × 600 | `medium` | 固定 72dp 導覽軌、無收合鍵、無面板（不變）；排行榜 1 欄（容器 648dp），三個音源全在 |
| 900 × 700 | `expanded`（**新的一段**） | 可收合導覽軌 ＋ 軌底的設定鍵 ＋ 右側 36dp 的面板收合條 —— 這一帶以前**完全拿不到面板**；排行榜 2 欄 |
| 1280 × 800 | `large` | 排行榜 3 欄；把把手拖到底停在 **512dp = 1280 × 0.4**（舊模型是絕對值 500）；面板吃到 512dp 之後內容區 672dp、排行榜收成 1 欄而**三個音源一個都沒有消失**；沒有歌詞的曲目播放頁是**單欄置中**（舊版會把 58% 畫面留給一句「暫無歌詞」） |
| 1700 × 800 | `extraLarge` | 面板上限 **682dp ≈ 1700 × 0.4**（舊模型仍是 500，只佔 29%）；面板拖到底時排行榜 2 欄，三個音源全在 —— 這正是路線圖驗收要的「1700 + 面板拖到上限，排行榜不變」 |
| 1200 × 500 | `large` 但矮 | 播放頁**維持單欄**。舊的 `width >= 1200` 會在這裡給雙欄；`height >= 520` 擋掉了（抄 Auxio 的 `layout-h520dp`） |

持久化：既有安裝（有舊資料庫）保留存下來的 380dp 與展開狀態；
`pm clear` 之後的全新安裝，面板是 36dp 的收合條 —— 決策 04-D2 的「預設收起」
只作用於新建的列，既有使用者的選擇沒有被改寫。

#### 順帶發現的一個既有缺陷（本輪不修）

1200 × **500dp** 時收合的導覽軌會 `OVERFLOWED BY 64` 像素。量到的每個目的地
高 64dp：新的軌需要 5 × 64 + 56（設定鍵）+ 65（漢堡鍵與分隔線）= 441dp，
舊的六個目的地需要 6 × 64 + 65 = 449dp，而可用高度是 500 − 64（迷你播放器）
− 24（狀態列）= 412dp。**兩者都放不下，新的還少 8dp**，所以這是矮視窗的既有
問題而不是本輪造成的。它屬於 P1-2 那一類（固定高度遇上空間不足），本輪沒有
處理短視窗，照實記在這裡。

#### 驗不到的

`detailPanelStoredMax`（1600）只有在手改資料庫或匯入壞掉的備份時才碰得到，
裝置上沒有誘發路徑；它只有單元測試覆蓋（`database_migration_test.dart` 三條）。

裝置狀態：模擬器已 `adb emu kill`，`adb devices` 為空，無殘留行程，
`wm size` 已 `reset`。**本輪沒有動使用者的 Windows 機器。**

---

### 6.12 執行時的失效重核（2026-09-07，Phase 4 收尾 Round A：`Notifier` 改寫）

Phase 4 列出但從未開工的兩項裡的第一項。**這一輪是零行為變更**，但它動了
`lib/providers/` 底下的每一個檔案，以及 `lib/services/` 的四個。

#### 為什麼四輪 Phase 4 都沒做它

不是因為技術上做不到，也沒有任何文件記錄過「決定不做」。是**兩份文件互相矛盾**：
路線圖 Phase 4 寫「**同時做**」，而 `lib/providers/AGENTS.md` § Riverpod 3 寫
「Rewriting the remaining `StateNotifierProvider`s into `Notifier` is a separate,
later change — **do not start it opportunistically**」。`AGENTS.md` 是有約束力的
規則檔（根 `AGENTS.md` 明文），所以每一輪都被它擋住，而它自己從來沒有被排成
獨立的一輪。**本輪把那句話刪掉，換成「lib 已無 legacy，由靜態測試守著」。**

#### 十條要更正的說法

| # | 開工前的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | 「39 個 `StateNotifierProvider`」（03 §1217） | **43 個 legacy provider**：40 個 `StateNotifierProvider`（33 plain、5 `.autoDispose`、1 `.family`、1 `.autoDispose.family`）＋ 3 個 `StateProvider`，由 36 個 notifier 類別支撐。`lib` 裡 33 個檔 import `legacy.dart` | 全部改完；現況 43 個 `NotifierProvider`（36 plain、5 `.autoDispose`、2 `.family`）＋ 39 個 `Notifier` 類別 |
| 2 | `AGENTS.md` 列了 `StateController`、`ChangeNotifierProvider` | **兩者實際用量都是 0** | 規則檔的清單縮掉 |
| 3 | 本輪計畫：「兩個 `.family` 是唯一不機械的一組」，並準備了退路 | **不成立。** `NotifierProvider.family` 的 create 函式**吃 family 參數**（riverpod `builder.dart:669`），所以 id 照樣走建構子 | 兩個 family 都是機械翻譯，退路沒有用上 |
| 4 | 本輪計畫：A2 是 `lib/providers/settings/` 的「11 個」 | 該目錄只有 **10 個**；被誤算進去的 `audio_settings_provider` / `playback_settings_provider` 住在 `lib/providers/audio/` | 那兩個併進 A5 |
| 5 | — | **`ref.onDispose` 在「provider 即將 rebuild」時也會跑**（riverpod `ref.dart:513-518`）。這正是「每次 build 開的訂閱都成對關掉」成立的原因 | 寫進規則檔；`PlaylistImportNotifier` 的訂閱洩漏由 `notifier_rebuild_test.dart` 守著（拿掉 `ref.onDispose` 那條測試會紅，已實測） |
| 6 | — | **生命週期回呼裡不能碰任何別的 provider**：`state =` 與 `ref.invalidate` 都會撞上 `riverpod/src/core/ref.dart:235` 的斷言。`StateNotifier` 時代是允許的 | `downloadServiceProvider` 釋放時清空下載進度那一行改成排到回呼堆疊之外並加 `ref.mounted` 守衛；`RadioController._teardown` 要碰的兩個物件改在 `build()` 先抓在手上 |
| 7 | — | **provider 建立期間也不能改別的 provider**（`element.dart:804`）。把第 6 點那行搬到工廠開頭同樣被擋 | 只有「排出回呼堆疊」這一條路 |
| 8 | — | **最貴的一條**：`AudioController._teardown` 做的是**所有權釋放**（dispose 後端音訊服務、交還系統媒體控制）。`onDispose` 既然在 rebuild 前也跑，用 `ref.watch` 取協作者就等於「任何一個相依變動都會在控制器還活著的時候把播放器關掉」。實測症狀是 `Cannot add new events after calling close` | `AudioController.build()` 的協作者一律 `ref.read`。`RadioController` 相反 —— 它**需要** `watch`（等資料庫開好），而它的 teardown 只取消自己重建得回來的訂閱 |
| 9 | — | `Ref.mounted` 存在（`ref.dart:112`）；`Notifier.state` 是 `@protected @visibleForTesting`（`notifier_provider.dart:79-81`） | 13 個檔約 58 處 `mounted` 機械改成 `ref.mounted`（`AudioController` / `RankingCacheService` 保留自己的 `_isDisposed`）；`lib` 裡三處外部 `state =` 改成具名方法 |
| 10 | — | **`Notifier.new` 不吃參數**，所以每一處「測試用建構子注入」都要改。實際規模：**51 個直接 new 的呼叫點、15 處 `overrideWith`、9 個測試替身** | 見下 |

#### `Notifier.new` 不吃參數帶來的結構後果

這是本輪唯一真正改變了介面形狀的地方，全部都是被框架逼出來的，不是預先抽象：

- 三個窄 provider：`mixTracksFetcherProvider`、
  `optionalLyricsAutoMatchServiceProvider`、`homeRankingSettingsStoreProvider`。
  前兩個讓播放測試不必為了一個可選協作者把整條歌詞／設定鏈拉起來（那條鏈會碰
  secure storage，測試環境沒有實作）。
- `RankingCacheService` 拆出 `bindSources()`：初次載入與網路監聽以前寫在
  provider 工廠的 body 裡，測試直接 new 就能跳過；`NotifierProvider` 沒有 body，
  所以接線與啟動分成兩半，測試子類只呼叫前一半。
- 兩個測試支援檔：`test/support/audio_controller_harness.dart`（把
  `AudioController` 舊建構子的十個具名參數翻譯成 override）與
  `test/support/audio_settings_notifier.dart`。

#### 反過來拿掉的東西（§6.8 預言的那一半）

§6.8 說「`Notifier` 可以把 `ref` 拿進來，起播 provider 的接線就不必全擠在
provider 工廠裡」。實際兌現的：

- `audioControllerProvider` 的工廠從 **74 行變成 1 行**（8 個 `ref.watch`、
  3 個回呼接線、1 條訂閱 ＋ `ref.onDispose`、`Future.microtask` 全部進 `build()`）。
- `FileExistsCache` 的 `onEpochChanged` 回呼**整個刪掉** —— 它存在的唯一理由是
  `StateNotifier` 拿不到 `ref`。
- `RadioController.forLoading()` 這個第二建構子、`_DummyRadioRepository`、
  `_DummyAudioService` **三個一起刪掉**：資料庫還沒開的分支變成 `build()` 的一條
  早退路徑。（順帶解決了 Round B 原本要處理的「`_DummyAudioService` 的
  `noSuchMethod` 會靜默吞掉新介面成員」。）
- 七個類別不再需要在建構子吃 `Ref`。

規模：**69 個檔、+1601 / −1105**（lib +826 / −769，test +775 / −336）。

#### 驗收

`flutter analyze` 全綠；`flutter test --exclude-tags live` **1466 通過**
（基準 1459 ＋ 7 條新測試），九個 commit 每一個都跑過完整套件。

**實機（Android 模擬器 `Medium_Phone`，1080×2400）**：完整走過首頁、設定、
音訊品質、音樂庫、歌單詳情、播放、電台、搜尋、全螢幕播放頁。506 行 Dart log 裡
**零個** `LateInitializationError` / `UnmountedRefException` /
`Cannot use Ref` / 未處理例外。逐項證據：

| 觀察到的 | 證明了哪一批 |
|---|---|
| 首頁 YouTube／網易雲排行榜載入（Netease 50 首）、`[RankingCache] 網絡恢復監聽已設置` | A6 的 `bindSources()` ＋ 初次載入 ＋ 網路監聽 |
| `[ConnectivityNotifier] DNS polling started (interval: 15s)` | A6 |
| 設定頁主題／主題色／字體／語言四項都顯示已載入的值 | A2 |
| 音訊品質頁三組優先級都填好 | A5（`audioSettingsProvider`，會碰 secure storage 的那一個） |
| 音樂庫列出歌單、歌單詳情載入曲目與時長 | A4（`playlistListProvider` 的 Isar `watchAll()` 訂閱、`playlistDetailProvider` family） |
| 播放本機檔案成功，`dumpsys media_session` = `state=PLAYING(3), position=8389`；迷你播放器語意節點 `'0:07, 播放進度'` | A8 ＋ A1（`queueStateProvider` 投影）；順帶確認 Phase 5f 的 slider 語意沒有回歸 |
| `[RadioController] 載入 1 個電台` / `watchAll 觸發`，且**進電台頁時音樂持續播放** | A7 的 `build()` 分支；同時是第 8 點那個坑的反證 —— 沒有誤觸 `AudioController` 的 teardown |
| 搜尋紀錄「hello」顯示、搜尋回「線上結果 (60)」 | A3 |
| 曲目播完 → `playing=false, processingState=ready` | `_onTrackCompleted` 在單曲佇列末端暫停，行為未變 |

**本輪發現、未修的既有問題**（都與本輪無關，記在這裡以免下一輪重新診斷）：

1. ~~**`test/bilibili_source_test.dart` 有兩條真連網測試沒有標 `tags: 'live'`**
   （`should fetch audio URL for valid bvid`、`refreshAudioUrl should refresh
   audio URL for track with expired URL`；`:819` 的註釋自承「此测试需要网络连接」）。~~
   **這一條寫錯了，Round B 開工時更正**：被點名的那兩條**早就標了** ——
   `git blame` 顯示 `:849` 與 `:979` 的 `tags: 'live'` 來自 2026-09-01 的
   `598fce27`。真正沒標的是**另一條**：`should throw BilibiliApiException for
   invalid bvid`（`:851`），它同樣用 `setUp`（`:31`）建的無假 adapter
   `BilibiliSource()`，而且 `expect(() => ..., throwsA(...))`（`:854`）沒有
   `await expectLater`。→ **issue #56**。
2. **`test/services/audio/playback_handoff_gate_test.dart` 的
   `a seek right after navigation waits out the stabilization window`
   在完整套件負載下偶發失敗**，單獨跑通過。原因是 `stabilizationDelay` 是
   40ms 的真計時器（`:19`、`:29`），而 `settled()` 用固定 10 圈的
   `pumpEventQueue`（`:37`）去斷言「還沒完成」。與 issue #43 同一類。
   → **issue #55**。
3. 首頁的 Bilibili 排行榜在本輪實機期間一直是
   `BilibiliApiException(-352): 請求過於頻繁` —— 開發機的風控狀態，不是回歸。

**沒有做的**：`FmpAudioService` 的佇列語意（Round B）。Phase 4 按其本節定義仍差這一項。

---

### 6.13 執行時的失效重核（2026-09-07，Phase 4 收尾 Round B：後端佇列語意）

Phase 4 列出但從未開工的兩項裡的第二項，也是本輪**唯一的行為變更**。介面落在
`setNextMedia(PreparedPlaybackMedia?)` ＋ `Stream<PreparedPlaybackMedia>
advancedToNext`，不是原本寫的 `setQueue(List)` ＋ `supportsQueue`。

#### 這是控制流倒轉，不是加兩個方法

一旦第二個媒體進了後端的播放清單，`ConcatenatingAudioSource` 與 mpv playlist
就會**自己**在交界處推進 —— 兩個套件都沒有「播到項目邊界就停」的模式。所以
「只做預緩衝、不倒轉控制流」這個中間選項不存在：控制器從「決定並發起下一首」
改成「決定下一首、交給後端、事後跟隨」。

#### 十條要更正的說法

| # | 開工前的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | 02 §6.3 階段 4 第 12 項：`setQueue(List<PreparedPlaybackMedia>)` | **這個簽名做不到。** 串流 URL 每首要一次網路解析、簽名有效期 1–2 小時、會被風控、未過期也可能 403（所以才有 `invalidateStream`）。佇列上限 1000 首 | 改成一次只交**一個**前瞻項目 |
| 2 | 02 §609：介面要加 `supportsQueue` 這類能力查詢 | **兩個後端都會回 `true`** | 不加。兩邊都真的布林是替想像中的第三個後端保留位置 |
| 3 | 「`supportsQueue` 可能該放進 `PlaybackCapabilities`」 | 不該。那個型別講的是「系統媒體鍵在當前播放模式下能做什麼」（`playback_capabilities.dart:13-45`），消費者只有 `NowPlayingPublisher` 與 SMTC，兩個後端都沒 import 它 | 軸不同，不放 |
| 4 | 「just_audio 用 `ConcatenatingAudioSource`」講得像現況 | **FMP 完全沒用它。** 四條開媒體路徑都是 `setAudioSource(AudioSource.uri(...))` 單一來源（`just_audio_service.dart:556-560` 等） | Android 後端改成「永遠一個 `ConcatenatingAudioSource`，平常只有一個 child」。**這本身就是行為變更**，B1 獨立成一個 commit 並上機驗過 |
| 5 | — | `ConcatenatingAudioSource` 的文件原文：「Playback between items will be **gapless on Android, iOS and macOS**」（`just_audio.dart:2544-2546`）；但 `add` / `insert` / `removeAt` 的註釋開頭都是 `/// (Untested)`（`:2597` 起） | 用了，並在實機上確認過（下方「實機」第 3 點） |
| 6 | 「media_kit 用 `Player.add` 追加即可」 | 對，但 `add()` 走 `loadfile <uri> append`（`native/player/real.dart:477`），**命令本身不帶 headers**。headers 是靠 mpv 的 `on_load` hook 從 `Media` 的全域 map 取出來設進 `http-header-fields`（`real.dart:2137-2180`），並在 `on_unload` 重設成 NONE | 與第 7 點直接衝突，成為本輪最大的風險 |
| 7 | — | **mpv 的 `--prefetch-playlist` 預設 `no`，media_kit 從沒設過它。** 手冊原文：「This merely opens the URL of the next playlist entry as soon as the current URL is fully read.」／「**This can give subtly wrong results if per-file options are used**…」／「**Highly experimental.**」 | 自己設 `yes`，並**先用實機把 header 問題問清楚**才往下做（結果見下方） |
| 8 | 計畫寫「B3 要同步 `PlaybackRecoveryCoordinator.clearForNewPlayback(track)`」 | **那個方法是死的**：完全沒用它的 `track` 參數，函式體與 `reset()` 逐字相同，production 零呼叫者 | 連同它的測試一起刪掉 |
| 9 | 計畫寫「在預取的掛點上把 `selectPlayback` 出來的 media 交給 `setNextMedia`」，並擔心預取快取是**單次使用**的 | 掛點手上確實沒有 media（`_prefetchNextIfRequested` 只吃一個 `bool`）。但**快取不是單次使用的** —— `_reusableResolution`（`stream_resolution_service.dart:325-341`）的 `remove` 後面緊接著 `_resolvedStreams[key] = cached`，那是更新 LRU 順序，不是取用即丟 | arm 時直接再呼叫一次 `selectPlayback` 就好，不必改串流層的管線。測試斷言下一首只解析一次 |
| 10 | — | **1 秒輪詢備援是全程開著的**（`initialize():352` 起，只在 `_teardown()` 停），而且它直接合成 `EndedNaturally`，**繞過兩個後端的 `_classifyCompletion`** | arm 期間讓路，但**不是無限期**：連續三格（3 秒）還停在結尾就收回推進權。那個備援本來就是為了「後台 completed 事件丟失」而存在的 |

#### 實機上才發現的一件事

**跟隨完成之後沒有人 arm 再下一首**，所以一條佇列只有**第一個**交界是 gapless。
平常的 arm 掛在 `PlaybackRequestSession` 的預取上，而跟隨路徑刻意不發請求（後端
已經在播了）。單元測試看不出來 —— 它們只驗一個交界。修在
`fix(audio): arm the boundary after the one just crossed`。

#### disarm 的網掛在哪裡

不在七個佇列命令上各掛一次，而是掛在 `_updateQueueState()` —— 佇列的每一次變動
（命令、shuffle、loop、Mix 補歌）都會經由 `QueueManager.stateStream` 走到那裡。
一個純比較（「現在的下一首還是不是當初交出去的那一個」）就夠了，不需要網路。
另外 `_startSessionLoadingState` 一定 disarm，因為 `_stopForRequest` 的無條件
`stop()` 本來就會清掉後端的播放清單。

不 arm 的條件：`LoopMode.one`（`getNextIndex()` 根本不看它，照著 arm 就是播錯歌）、
`_isPlayingOutOfQueue`（temporary / detached）、電台占用後端、Mix 正在補歌。

#### 驗收

`flutter analyze` 全綠；`flutter test --exclude-tags live` **1482 通過**
（Round A 之後的基準 1466 ＋ 16 條新測試）。三條守門測試各自用「刻意改壞再改回來」
確認會紅：loop-one 不 arm、佇列變動要 disarm、切到 loop-one 要 disarm。

**Windows（media_kit / 真 libmpv）**：用一個**要求 `Referer` 才給檔案**的本機
HTTP 伺服器直接驗 mpv 的行為，不動使用者的音樂庫（開發機當時正被 B 站風控擋，
而且問題本身與 B 站無關 —— 要問的是「header 有沒有跟著送出去」）。

| 量到的 | `prefetch-playlist=yes` | 沒有它（對照組） |
|---|---|---|
| 第二個 URL 何時被開啟（交界在 ≈6.0s） | **+937ms / +949ms** | **+5912ms / +5893ms**（交界當下才開） |
| 兩次請求都帶著 `Referer` / `Origin` | ✅ | ✅ |
| 交界處的時間軸接縫（對每一段的 `(wallclock, position)` 做最小平方擬合取截距） | **0.0ms / −0.1ms** | −199.9ms / −209.9ms |

→ **重核 #6 ＋ #7 那個風險不成立**：mpv 的 `on_load` hook 對被預先開起來的項目
**有跑**，per-file 的 `http-header-fields` 跟著送出去了。Windows 拿到完整的
gapless，不必退成「只對本機檔案 arm」。

**要誠實說的**：對照組那個 −200ms 是**方法的系統性偏差**（mpv 的 `completed`
比位置抵達名目時長早約 200ms 發出），不是「舊路徑比新路徑還快」。在**本機檔案**
上兩條路徑的接縫都在這個方法的解析度以內 —— 真正量得到的差別是**開流的提前量**
（提早約 5 秒），而那正是真實串流上 DNS / TLS / CDN 握手要花的時間。

**Android 模擬器（just_audio / 真 ExoPlayer）**：

1. B1 的單 child 包裝零回歸 —— 從 VM Service 讀到活著的
   `_playlist` 是 `ConcatenatingAudioSource`、`children.length == 1`、
   `useLazyPreparation == false`，同時 `dumpsys media_session` =
   `state=PLAYING(3), position=4862`。
2. arm 之後 `children.length == 2`（`ProgressiveAudioSource` ×2），
   `_nextMedia` 是 `LocalPlaybackMedia` —— 套件標「(Untested)」的 `add` 可用。
3. **連續五個交界**，每一個都是
   `[JustAudioService] Backend advanced to next medium` →
   `[AudioController] Following the backend across a gapless boundary` →
   `[FmpAudioHandler] Updated media item` → `Armed the next medium`。
   **其中後三個是在 app 被 HOME 鍵切到背景之後發生的**
   （`mCurrentFocus` = launcher），播放全程沒有中斷
   （`state=PLAYING(3)`）。
4. 整段 log 裡**零** `PlayerState changed: ... loading`、**零**
   `Track completed`、**零** `Position check triggered auto-next` ——
   交界沒有回到載入狀態，完成路徑與輪詢備援都沒有插手，沒有二次前進。

**沒有做的**：**沒有去驅動使用者在 Windows 上那個真的 FMP**（SMTC 的
`IsNextEnabled`）。理由是那會動到使用者真實的播放佇列與設定，而這一輪對
`PlaybackCapabilities` 與 `NowPlayingPublisher` 一行都沒改，交界處的發佈走的是
跟以前完全相同的 `_updatePlayingTrack` → `publishTrack`，而那條路已經在 Android
上驗過五次（`FmpAudioHandler Updated media item`）。後端本身則是用真的 libmpv
＋ 出貨用的那組參數驗的。**這是刻意留下的缺口，不是「測試通過」的代稱。**

#### 順帶發現、未修的既有問題

- **佇列還不存在時按迴圈按鈕，UI 會顯示新模式但實際沒有生效。**
  `QueueManager.setLoopMode`（`queue_manager.dart:712`）在 `_currentQueue == null`
  時直接 return，而 `AudioController.setLoopMode` 照樣
  `_emitQueueState(...)` 把新模式投影出去。本輪實機期間踩到：按了「列表循環」，
  按鈕變了，但 `PlayQueue.loopMode` 還是 `none`。與本輪無關。

---

### 6.14 執行時的失效重核（2026-09-07，落地 + Phase 7 授權與揭露）

本輪的起點不是程式碼：`origin/main` 停在 `598fce27`（2026-09-01），**Phase 0–5
的 143 個 commit 從來沒有推上去過**。先把它們落地，再做 Phase 7。

#### 一、落地時才浮出來的事

**1. issue #53 的根因找到了，而且 CI 當場就紅。**

`origin/main` 的 `sdk` 下界是 **3.5**，Phase 2 的 `3b1c7244`
（`chore(deps): move off the dormant isar to isar_community`）把它抬到 **3.9**。
`dart_style` 從語言版本 **3.7** 起改用 tall style —— 所以 formatter 的風格在
Phase 2 那個 commit 默默換過了，而 CI 從那之後就沒看過這棵樹。#53 當時比對的
「CI 上綠的 main」是抬升**前**的遠端 main，所以那份紀錄看起來自相矛盾。

PR #57 第一次讓 CI 看到這批程式碼，`Check formatting` 在 42 秒內失敗。

量到的兩個選項都不是零成本（553 個已追蹤的 `.dart`）：

| 風格 | 要重排的檔案 |
|---|---:|
| tall（語言版本 3.9 的實際預設） | **476** |
| short（`--language-version=3.6` 釘住） | **88** |

那 88 個全部是 Phase 0–5 期間手寫的 —— 因為 #53 當時的結論就是「不要跑
`dart format`」。**已定案：採用 tall style**（`eaa6870f`），並把兩個全樹重排
commit 寫進 `.git-blame-ignore-revs`。釘住 short style 只是把 #53 的陷阱留著：
任何人順手跑一次不帶 flag 的 `dart format` 還是會把檔案重排成另一種風格。

**2. 重排打掉 11 條測試，全部是同一類。** 靠原始碼字串比對的靜態規則測試釘的是
formatter 當下的換行決定，例如 `contains('playFile(path, track: track)')` 或
`contains('child: const PlayerPage(),')`。修法**不是**把新的排版重新釘一次，而是
改成不受換行影響的形式：單行的結構片段（`LocalPlaybackMedia(:final path, ...) =>
playFile(`）或帶 `\s*` 的 regex。另外 `app_layout.dart` 有一個 `if` 因為函式體被
移到下一行而觸發 `curly_braces_in_flow_control_structures`，補上大括號。

**3. `logger` 這個 dependabot PR（#49）本來就不該存在。** Phase 0 的 `364c7319`
已經把它移除，`pubspec.yaml` 與 `pubspec.lock` 都沒有它 —— dependabot 自己也在
main 落地後把 PR 關掉了。剩下六個已分流並逐一在 PR 上留了狀態，本輪不做任何實際
升級（`go_router` 14→18 是真正的遷移，`window_manager` 0.4→0.5 在 pub 語意下
等同破壞性變更）。

**4. 推之前掃到三行本機絕對路徑**（`docs/review/01-*.md`、`02-*.md`），含
Windows 帳號名。repo 是公開的，已遮成 `<user>`（`a9f32737`）。憑證類掃描
（SESSDATA / MUSIC_U / Bearer / VM Service token 形狀）命中的全是遮蔽機制的
說明文字與假測試值。

#### 二、Phase 7 執行時與計畫不符的地方

| # | 路線圖說 | 實況 |
|---|---|---|
| 1 | 7.3 要「CHANGELOG 記一筆」 | **`CHANGELOG.md` 不存在**，release note 由 `release.yml` 從 `git log` 動態產生。這一項刪掉，不為了它新建一個檔案 |
| 2 | 驗收要「`showLicensePage()` 之外另有一個第三方授權頁」 | 改用 **`LicenseRegistry.addLicense`** 併進現有的「開源授權」頁。那是 Flutter 為此設計的擴充點，零新頁面、零新 i18n 字串、零新入口，而使用者只要記一個地方 |
| 3 | 「206 個 Dart 依賴」 | `pubspec.lock` 現在是 **207**（42 direct main + 7 direct dev + 158 transitive；202 hosted + 5 SDK） |
| 4 | 7.1 要列「206 個依賴的授權清單」 | 全文不重抄 —— app 內的 `showLicensePage` 已經自動收錄每個 pub 套件自帶的 `LICENSE`。`THIRD_PARTY_LICENSES.md` 只給分佈與指路 |

**依賴授權重新逐檔清點**（讀本機 pub cache 每個 hosted 套件的 `LICENSE`，
202 個全部有檔、零 UNKNOWN）：

| 授權 | 套件數 |
|---|---:|
| BSD-3-Clause | 116 |
| MIT | 60 |
| Apache-2.0 | 19 |
| BSD-2-Clause | 6 |
| CC0-1.0 | 1 |
| **GPL / LGPL / MPL / AGPL** | **0** |

**libmpv / FFmpeg 的建置旗標這次是第一手讀的**，不是沿用 03 的紀錄：
`media-kit/libmpv-win32-audio-build`（master，已封存、無 LICENSE 檔）的
`packages/mpv.cmake:29` 是 `-Dgpl=false`，`packages/ffmpeg.cmake:34-36` 是
`--disable-gpl --disable-nonfree --enable-version3`。結論不變：**LGPL 不是 GPL**。

**7.2 沒有照譜系 A 抄，改寫成獨立表達。** 路線圖建議照 `AynaLivePlayer/miaosic`
（MIT）的寫法重寫，但那仍然要背一份 attribution。實際做法是用標準庫重寫：
`_k1` 那張十六進位對照表整張消失（`digest.bytes[i]` 就是那個位元組），手寫的
6 次 base64 迴圈換成 `base64.encode(...)` 加一次 `replaceAll(RegExp(r'[+/=]'), '')`
—— 等價性是可證的，因為原本的 `i == 5` 特判正是「尾端單一位元組產 2 字元、不補
`=`」。89 行降到 44 行。**等價性有兩層證據**：6 組從改寫前實作抓下來的 golden
向量（含空字串、CJK、長字串、真實 API payload），以及 2000 組隨機輸入的新舊交叉
比對，全部逐字元相同。

#### 三、實機驗證

| 平台 | 觀察到的 |
|---|---|
| Android 模擬器 | 設定 → 關於 → 開源授權：**`Protocol research` 在列**（`process_runner` 與 `pub_semver` 之間），內文含 `bilibili-API-collect`、`CC BY-NC 4.0` 與 netease 兩則。`l` 區是 `libjxl → libpng`，**沒有 `libmpv / FFmpeg`** —— 正確，Android 走 ExoPlayer，整包裡沒有 libmpv |
| Windows | 同一頁：**`libmpv / FFmpeg`（3 個授權）在 `libpng` 上方**，內文是建置旗標說明加上從 asset 載入的 **GNU LESSER GENERAL PUBLIC LICENSE Version 2.1** 全文 |

**驅動 Windows 時踩到的**：`--restore-window` 前三次都截到別的視窗（使用者正在用
這台機器，Windows 的前景鎖擋掉了 raise）。第四次才成功，而中途有一次 `scroll`
整個送到別的視窗去、FMP 完全沒動。**在 Windows 上每一次 click / scroll 之後都要
用截圖確認落在對的視窗**，不能假設指令送到了。

#### 四、順手處理與未處理

- `windows/runner/Runner.rc:96` 原本寫 `Copyright (C) 2026 com.personal. All
  rights reserved.` —— 「All rights reserved」與 MIT 直接矛盾，一併改掉。
  `CompanyName` 維持 `com.personal` 不動，它與 `AppUserModelID` 綁在一起。
- **`NOTICE` 與 `THIRD_PARTY_LICENSES.md` 只做一份**（後者）。兩份重疊的揭露文件
  一定會漂移，而路線圖本來就寫的是「`NOTICE` / `THIRD_PARTY_LICENSES.md`」二選一。
- `licenses/` 同時是 repo 目錄與 Flutter asset（`pubspec.yaml` 的 `- licenses/`），
  所以授權全文只有一份來源；`release.yml` 在打包**之前**把它與 `LICENSE`、
  `THIRD_PARTY_LICENSES.md` 複製進 `build\windows\x64\runner\Release`，可攜版 zip
  與 InnoSetup 安裝檔因此帶到同一批檔案。
