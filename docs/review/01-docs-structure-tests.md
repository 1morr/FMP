# 01 — 文檔體系、目錄結構與測試資產審查

- **審查日期**：2026-08-30（實機驗證與 Isar 實測補做於 2026-09-01）
- **審查基準 HEAD**：`b93f72c7`（工作樹乾淨）
- **提交時的 repo HEAD**：`598fce27` —— 遠端歷史在本輪期間被改寫，且在審查基準之上
  多了 10 個 commit。**§0 逐項列出哪些發現已因此失效、哪些仍然成立。**
- **範圍**：純讀碼 + 跑測試。§1.6（Android/Windows 實機）與 §1.7（Isar 遷移實測）為
  後續補做，各自註明。除本報告外未修改任何專案檔案。
- **環境**：Flutter 3.47.1 / Dart 3.13.1 / Windows 11 / 32 邏輯核心

> 標記約定：**【事實】**＝有指令輸出或 `file:line` 佐證；**【推論】**＝由事實推導；**【建議】**＝行動提案，附成本（S/M/L）、風險、可逆性。
> 未經驗證的一律標「未驗證」。

---

## 目錄

0. [基準差異：`b93f72c7` → `598fce27`](#0-基準差異b93f72c7--598fce27)
1. [驗證記錄](#1-驗證記錄)
2. [現況（附證據）](#2-現況附證據)
3. [問題清單 P0–P3](#3-問題清單-p0p3)
4. [成熟做法對照](#4-成熟做法對照)
5. [建議方案](#5-建議方案)
6. [重寫 vs 漸進重構](#6-重寫-vs-漸進重構)
7. [需要你決策的點](#7-需要你決策的點)
8. [Quick wins](#8-quick-wins)
9. [三個 issue 的裁決](#9-三個-issue-的裁決)
10. [附錄 A：方法與可信度](#附錄-a方法與可信度)
11. [附錄 B：本輪未完成的部分](#附錄-b本輪未完成的部分)

---

## 摘要

五件本輪最重要的發現。前三件不在原本要查的清單上；後兩件是你放行後補做的實機驗證，
而且**兩件都推翻了我自己先前的推論**：

1. **`flutter test` 會對 Bilibili 生產 API 發真實網路請求。** `test/demo/bilibili_info_test.dart` 因為檔名符合 `*_test.dart` 被 CI 誤收，實際回應已從三次測試的 `--machine` 輸出中撈出來作證（§1.5）。改一個檔名解決。
2. **`test/performance/` 的 wall-clock 斷言在負載下 4/4 必失敗**，且乾淨的 32 核機器上餘裕只有 1.48x（§1.3）。GitHub Actions 是 4 vCPU。改兩個檔名解決。
3. **issue #43 的根因推測是錯的。** CI 在 2026-07-27 真的失敗過一次，log 顯示是 `IsarError: Isar instance has already been closed` 造成的測試生命週期洩漏，不是 pump 圈數不夠 —— 而且失敗的那條測試**已經在用** issue 建議的條件式 helper（§9）。
4. **（實機補做）Isar 換 `isar_community` 的資料風險是零，但代價藏在別處。** 拿真實生產資料庫（1,523 筆）做 A/B 實測：11 個 collection 逐項一致、檔案大小不變、`flutter analyze` 全綠。真正的成本是它會**強制把 slang 3.32 升到 4.19**（`build ^4` 依賴鏈無法繞過），而 slang 4 會讓 `main.dart:137` 的 `useDeviceLocale()` 變成未 await 的 Future —— 且 `flutter analyze` 對此完全沉默（§1.7）。
5. **（實機補做）通知頻道名稱永遠是英文，與裝置語系無關。** `main.dart:91` 在 locale 初始化前 46 行讀 `t.`，而 slang 在 locale 未定時會因為 `en` 是唯一沒宣告 `countryCode` 的 locale 而回傳英文（不是文檔上寫的 base locale zh-CN）。已在模擬器上切 per-app locale 到 zh-CN 確認：UI 變簡中、頻道名不變（§1.6a）。移動一行即可修好。

其餘：agent 指令 76 條抽驗 83% 正確，1 條硬性錯誤（`playlistProvider` 不存在）；`CLAUDE.md` 只放 `@AGENTS.md` 經官方文檔核對**是正確做法**，但 6 個子樹 `AGENTS.md` 不享有 harness 保證的自動載入；`services/` ↔ `providers/` 邊界已實證失效（6 檔 14 處反向依賴）；測試套件體質良好（78.3% 行為測試、0 檔無法理解）。

---

## 0. 基準差異：`b93f72c7` → `598fce27`

**【事實】** 本報告寫完之後才發現，`origin/main` 的歷史在這期間被整段改寫（本地與遠端
`ahead 929 / behind 939`，共同祖先 `ddbf0405`，2026-02-12）。核對確認**改寫沒有丟失任何
內容**：本地 tip `b93f72c7` 與遠端對應的 `395305bd` 內容 byte 級相同，且本地沒有任何
commit subject 在遠端缺席。差別在於遠端在改寫後**又多了 10 個 commit**，而它們幾乎正好
打在本報告的分析對象上。

```
598fce27 test: add a live audio-source suite and stop network tests gating CI
c1fc0b4b ci: scope the format gate to lib and test
0089fe45 style: run dart format across the tree
ca1d4a0d docs: rewrite readme in english with a traditional chinese mirror
75255079 docs: retake the screenshots in english and halve their weight
96e19a2d docs: merge the build guides and finish the traditional chinese conversion
ce100d32 ci: delete a check that could not fail, and pin the actions
8d04147e fix: sync the app version so the updater stops crying wolf
45f9f1fe fix: check mounted before setState in four async handlers
d61e602d docs(youtube): say why the hardcoded api key is not a leak
395305bd docs(agents): add verify-on-device skill ...   <- 本報告的審查基準
```

以下是逐項複查結果（在 `598fce27` 上重跑檢查，非推測）。

### 0.1 已修復 —— 這些結論**不要再照著做**

| 原編號 | 原結論 | 現況（`598fce27`） |
|---|---|---|
| **issue #38 / §1.4** | CI 的 `Verify generated files are committed` 名不副實 | ✅ **該 step 已整個刪除**（`rg "Verify generated files" .github/` 無結果）。commit `ce100d32` 訊息即「delete a check that could not fail」 |
| **P1-7** | 兩份 workflow 完全沒有 `timeout-minutes` | ✅ **8 個 job 全數加上**（`ci.yml` 3 個：15/20/20 分；`release.yml` 5 個：5/25/15/25/10 分）。同一個 commit 還把所有 action **pin 到 commit SHA**，這是我沒提到的額外強化 |
| **§5.2 / §2.3** | `build-guide.md` 與 `build-and-release.md` 內容重疊，建議合併 | ✅ **`build-guide.md` 已刪、`building.md` 已建**（commit `96e19a2d`） |
| **§2.3** | `docs/history/refactoring-log.md`（1046 行）是存檔背景，不是現行指引 | ✅ **整個 `docs/history/` 目錄已刪除** |
| **§7 決策點 3** | 繁簡混用要不要統一 | ✅ **已定案**：`README.md` 改為英文主檔 + `README.zh-Hant.md` 繁中鏡像（commit `ca1d4a0d`）。這個決策點可以劃掉 |
| **P3-6（部分）** | 截圖全是桌面版、`home_desktop.png` 與 `home-page.png` 重複 | ⚠️ **已重拍**：8 張換成 10 張（新增 `explore-page.png`、`history-page.png`），尺寸 2560x1380 降到 1280x690、檔案大小約砍半。**但兩點仍成立**：全部仍是 1280x690 的桌面版截圖、**零 Android 畫面**；`home_desktop.png`（1600x1000）與 `home-page.png` 仍並存 |

### 0.2 部分修復 —— 機制換了，但原問題還在

| 原編號 | 現況 |
|---|---|
| **P0-2 / §1.5**（`flutter test` 會發真實網路請求） | 新增了 `test/live/sources_live_test.dart`（唯一帶 `@Tags` 的檔）、`dart_test.yaml` 宣告 `live` tag，CI 改成 `flutter test --coverage --exclude-tags live`。**方向正確，但沒蓋到原本那個檔**：`test/demo/bilibili_info_test.dart` **沒有被標 tag**，仍符合 `*_test.dart`、`main()` 裡仍直接 `dio.get('https://api.live.bilibili.com/room/v1/Room/room_init')`（`:17-18`、`:26-27`）。它照樣會被 CI 收進去跑。**原發現與修法仍然有效** |
| **Quick win #23**（demo 檔缺 `ignore_for_file: avoid_print`） | 6 個 demo 檔已有 5 個補上，**只剩 `bilibili_live_api_lookup_demo.dart` 沒有** —— 而它正是 §1.1b 那 95 條 `avoid_print` 的唯一來源 |

### 0.3 完全未動 —— 這些結論原封不動仍然成立

在 `598fce27` 上逐條重新驗證過：

| 原編號 | 重驗結果 |
|---|---|
| **P0-1** | `test/performance/` 的 wall-clock 斷言**一條都沒改**。`git diff` 顯示這兩個檔只被 `dart format` 動過（`expect(elapsed, lessThan(5000), ...)` 只是換行位置變了）。門檻 5000/3000 ms 全數保留 |
| **P1-5** | `analysis_options.yaml:13-14` 仍是 `exclude: - test/**` |
| **P1-9** | `main.dart:91` 讀 `t.notification.channelName`、`:137` 才 `useDeviceLocale()` —— 行號完全沒變 |
| **P1-10** | Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 全部未動 |
| **P1-11** | `rg -l "isar_flutter_libs" test/` 仍是 **40 個檔** |
| **P1-4 / §1.7** | `pubspec.yaml:22-23,95` 仍是 `isar` / `isar_flutter_libs` / `isar_generator` `^3.1.0+1` |

### 0.4 對報告其餘部分的時效性提醒

**【事實】§1.1 與 §1.2 的量測數字（`flutter analyze` 386.9s、178 suites / 1241 tests）是在
`b93f72c7` 上取得的。** `598fce27` 之後樹上多了 `test/live/` 一個 suite、並跑過一次全樹
`dart format`，所以那些絕對數字需要重跑才能沿用。**但結論不受影響** —— §1.3 的壓力重現
（4/4 必失敗）針對的是 `test/performance/` 的斷言結構，而該結構完全沒變（§0.3）。

**未驗證**：我沒有在 `598fce27` 上重跑 `flutter analyze` 與完整 `flutter test`，本節只做了
針對性的靜態複查。

---

## 1. 驗證記錄

### 1.1 `flutter analyze`

```
Flutter 3.47.1 • channel stable • revision 6655482ec0 (2026-08-19)
Engine 11d79658c444 • Tools • Dart 3.13.1 • DevTools 2.60.0

$ flutter analyze
No issues found! (ran in 386.9s)
real 6m45.202s   exit=0
```

**【事實】乾淨，但涵蓋範圍比表面小**：`analysis_options.yaml:14` 有 `exclude: - test/**`。46,357 行測試碼完全不受靜態分析。根 `AGENTS.md:94` 把 `flutter analyze` 列為 UI 變更的驗證手段之一，這個前提對 `test/` 不成立。

### 1.1b `exclude: test/**` 實際隱藏了什麼

**【事實】** `dart analyze test` 直接跑會回報 `No issues found!`（4.1 秒）—— 那是因為它仍然套用根設定的 `exclude`，實際一行都沒分析。我在 `test/` 放了一個暫時的巢狀 `analysis_options.yaml`（同樣的 `flutter_lints` + 2 條 const 規則，無 exclude），跑完立刻刪除，`git status` 已確認工作樹乾淨。

```
$ dart analyze test        # 繞過 exclude 後
146 issues found.          # 0 error / 14 warning / 132 info   (8.7s)
```

| 規則 | 次數 | 說明 |
|---|---:|---|
| `avoid_print` | **95** | **全部集中在單一檔案** `test/demo/bilibili_live_api_lookup_demo.dart` —— 它是唯一沒有 `// ignore_for_file: avoid_print` 的 demo 檔 |
| `prefer_const_constructors` | 19 | 純風格 |
| `unused_import` | 6 | 死 import |
| `prefer_interpolation_to_compose_strings` | 6 | 純風格 |
| **`override_on_non_overriding_member`** | **5** | **測試替身已與正式介面漂移** |
| `unnecessary_import` | 3 | |
| `prefer_const_declarations` | 2 | |
| `depend_on_referenced_packages` | 2 | |
| `dangling_library_doc_comments` | 2 | |
| `unrelated_type_equality_checks` | 1 | 泛型未綁定造成的誤報，**非缺陷**（見下方更正） |
| `unused_element` / `unused_element_parameter` / `unnecessary_non_null_assertion` / `overridden_fields` / `curly_braces_in_flow_control_structures` | 各 1 | |

**扣掉那個 demo 檔的 95 條，真正的測試碼只有約 50 條問題** —— 以 46k 行來說不算糟。但其中兩類有實質意義：

**1 條 `unrelated_type_equality_checks` —— 我原本判定為缺陷，實測後推翻**：

```
info - services/radio/radio_controller_phase2_import_test.dart:195:18
  The type of the right operand ('Provider<BilibiliAccountService>') isn't a subtype
  or a supertype of the left operand ('ProviderListenable<T>').
  - unrelated_type_equality_checks
```

**我原本的【推論】是：** 兩個型別不相關 → `==` 永遠 false → 該處是空斷言。**這條推論是錯的**，
原因有兩個，都是我當初只看 lint 輸出、沒有看程式碼上下文造成的：

**【事實】1：那不是斷言。** 它是 fake `Ref` 的 `read` 分派實作（現位於 `:217-221`，
`dart format` 後行號從 195 移到 219）：

```dart
class _FakeRef implements Ref {
  @override
  T read<T>(ProviderListenable<T> provider) {
    if (provider == bilibiliAccountServiceProvider) return accountService as T;
    throw UnimplementedError('Unexpected provider: $provider');
  }
}
```

**【事實】2：這個 `==` 在執行期為 true，已實跑證明。** 如果它永遠 false，控制流會走到
`throw UnimplementedError` 讓測試**大聲失敗**，不可能靜默通過。實測：

```
$ flutter test test/services/radio/radio_controller_phase2_import_test.dart
[INFO] [RadioController] 載入 1 個電台
[INFO] [RadioController] watchAll 觸發: 2 個電台
00:00 +3: All tests passed!
```

log 顯示 `RadioController` 真的拿到了 account service 並載入電台 —— 證明分支命中。

**【推論】** lint 是誤報：`read<T>` 的 `T` 在宣告處未綁定，分析器無法證明
`Provider<BilibiliAccountService>` 與 `ProviderListenable<T>` 相關；但呼叫端傳入時
`T` 會被推導成 `BilibiliAccountService`，而 `Provider<X>` 本來就是
`ProviderListenable<X>` 的子型別，物件同一性比較成立。

**這條記在這裡當作方法論的反例**：`exclude: test/**` 確實藏住了 146 條問題（P1-5 的論據
不變），但「lint 有輸出」不等於「程式有缺陷」—— 我當初把 lint 訊息直接當成結論，違反了
本輪自己訂的「每條結論附證據」。

**【事實】5 條測試替身漂移**：

```
warning - services/audio/playback_request_session_test.dart:888:48, 910:31
warning - services/audio/temporary_play_handler_test.dart:351:17, 361:24, 371:8
  The method doesn't override an inherited method.
  - override_on_non_overriding_member
```

**【推論】** 這兩個檔的 fake/stub 上有 `@override`，但正式介面已經沒有對應方法了 —— 正式碼改過、測試替身沒跟上。那些方法現在是死的，永遠不會透過介面被呼叫。

**【事實】2 條未宣告的套件直接 import**：`test/demo/bilibili_live_api_lookup_demo.dart:5` import `http`（pubspec 完全沒有）、`test/providers/import_playlist_provider_phase2_test.dart:14` import `riverpod`（pubspec 只有 `flutter_riverpod`）。兩者都靠 transitive 解析才能編譯。

### 1.2 `flutter test`（乾淨環境，連跑 3 次）

| 回合 | suites | 可見測試 | 失敗 | runner 時間 | wall clock |
|---|---:|---:|---:|---:|---:|
| 1 | 178 | 1241 | 0 | 107.4s | 1m58.8s |
| 2 | 178 | 1241 | 0 | 95.7s | 1m45.5s |
| 3 | 178 | 1241 | 0 | 89.6s | 1m38.2s |

**【事實】** 178 suites = 178 個 `*_test.dart`（`test/` 共 184 個 `.dart`，扣掉 5 個 `test/demo/*_demo.dart` 與 1 個 `test/support/fakes/fake_audio_service.dart`）。

### 1.3 高負載重現（依 issue #43 描述的條件）

方法：24 個 Python 忙迴圈佔滿 32 核中的 24 核；偶數回合另外並行跑一個 `flutter analyze`。

| 回合 | 負載 | wall clock | exit | 可見測試 | 失敗數 | 失敗 suite |
|---|---|---:|---:|---:|---:|---|
| 1 | 24 核 CPU 飽和 | 3m15.2s | **1** | 1241 | 3 | `list_scrolling_benchmark_test.dart` |
| 2 | 24 核 + 並行 analyze | 3m10.4s | **1** | 1241 | 3 | 同上 |
| 3 | 24 核 CPU 飽和 | 2m58.1s | **1** | 1241 | 3 | 同上 |
| 4 | 24 核 + 並行 analyze | 3m13.0s | **1** | 1241 | 3 | 同上 |

**【事實】4/4 回合失敗完全一致 —— 同一個 suite、同樣 3 條、同樣順序。這不是「偶發」，是負載下的必然。**

重現到的失敗：

```
FAIL test/performance/list_scrolling_benchmark_test.dart
  · List Rendering Performance > Scroll performance with 1000 items
  · Widget Build Performance > Repeated widget rebuilds
  · Data Processing Performance > Track search/matching performance
    Expected: a value less than <3000>
      Actual: <12488>   (回合 1) / <12517> (回合 2)
    Which: is not a value less than <3000>
    at test/performance/list_scrolling_benchmark_test.dart:361
```

同一測試在乾淨環境 vs 負載下的實測數字：

| 量測項 | 乾淨 | 負載下 | 門檻 | 乾淨時餘裕 |
|---|---:|---:|---:|---:|
| 10 scroll ops / 1000 items | 1230ms | 7978ms | 5000ms | 4.1x |
| 100 widget rebuilds | 2637ms | 21559ms | 5000ms | 1.9x |
| 500 searches / 5000 tracks | **2028ms** | 12488ms | **3000ms** | **1.48x** |
| Initial render 100 items | 1033ms | 933ms | 5000ms | 4.8x |

**【事實】** `test/performance/` 兩個檔共 12 條 wall-clock `expect(elapsed, lessThan(N))` 斷言（`list_scrolling_benchmark_test.dart:58,99,153,239,283,327,361` 等；`startup_benchmark_test.dart:39,72,100,130,157,181`）。這些跑在預設 `flutter test` 套件裡，也就是 CI 的每一次 push/PR。

**【推論】** 在一台 32 核開發機上「500 searches」只有 1.48x 餘裕；GitHub Actions `ubuntu-latest` 是 4 vCPU 共享機器，慢 3 倍以上是常態 → CI 隨時可能踩到。這不是「偶發 flaky」，是**門檻設計錯誤**。

### 1.3b CI workflow 本身的缺口

**【事實】** `ci.yml` 與 `release.yml` 兩份 workflow：

- **任何 job、任何 step 都沒有 `timeout-minutes`** → 沿用 GitHub 預設的 360 分鐘上限。搭配 §1.5 的真實網路請求，一個掛住的 socket 可以吃掉 6 小時。
- **沒有任何失敗重跑機制**（無 `nick-fields/retry` 之類）。上述任一 flaky 觸發 → 只能人工重跑整個 workflow。
- **測試只在 `ubuntu-latest` 跑。** `build-windows`（`windows-2022`）只做 `flutter build windows --release`，`build-android` 只做 `flutter build apk` —— **CI 從未在 Windows 或 Android 上執行過 `flutter test`**。`AGENTS.md` 提到的 Windows 特有行為完全依賴人工 on-device 驗證。
- `flutter test --coverage` 沒有 `--tags` / `--exclude-tags`，也沒有 `dart_test.yaml` 排除清單 → 用 Dart test 預設的 `**/*_test.dart` 規則跑遍全部 178 個符合命名的檔案。`test/demo/bilibili_info_test.dart` 與 `test/performance/*` 因此被一起收進去。

### 1.4 CI 歷史

**【事實】** 最近 20 次 `ci.yml` 有 2 次失敗：

- `30295715652`（2026-07-27）— 失敗在已被移除的 `Linux Build Smoke` job（`hotkey_manager_linux` CMake）。與本輪無關。
- `30280237603`（2026-07-27）— **`Analyze and Test` job 失敗**：`##[error]1239 tests passed, 1 failed, 1 skipped`。觸發 commit 是一個純文檔改動（`docs(debugging): correct the vm service guide again`）。

失敗的那一條（完整 log 節錄）：

```
❌ test/services/audio/audio_controller_phase1_test.dart:
   AudioController phase 1 regressions
     superseded playback-starting callback does not stop the newer request (failed)

[ERROR] [AudioController] Failed to play track: Callback First Track
  Error: IsarError: Isar instance has already been closed
  StackTrace:
   #0 Isar.requireOpen (package:isar/src/isar.dart:154:7)
   #2 GetPlayQueueCollection.playQueues (package:fmp/data/models/play_queue.g.dart:13:52)
   #3 QueueRepository.save.<anonymous closure> (queue_repository.dart:30:39)
   #7 QueuePersistenceManager.persistQueue (queue_persistence_manager.dart:89:5)
   #8 QueueManager._persistQueue (queue_manager.dart:828:5)
   #9 QueueManager.playSingle (queue_manager.dart:402:5)
   #10 AudioController.playSingle (audio_provider.dart:704:26)

Bad state: Condition was not met after 50 event pumps
  test/services/audio/audio_controller_phase1_test.dart 1775:3  _pumpUntil
Bad state: Tried to use AudioController after `dispose` was called.
```

這段是本輪最有價值的單一證據，見 §9 對 issue #43 的裁決。

### 1.5 `flutter test` 會發真實網路請求

**【事實】** `test/demo/bilibili_info_test.dart` 檔名符合 `*_test.dart`，因此被 `flutter test` 載入執行。它沒有任何 `test()` / `group()`，是一支裸 `main()` 腳本，對 Bilibili 生產 API 發三個以上請求（`bilibili_info_test.dart:14,24,40`）：

```dart
const roomId = '2388053';
await dio.get('https://api.live.bilibili.com/room/v1/Room/room_init', ...)
await dio.get('https://api.live.bilibili.com/room/v1/Room/get_info', ...)
await dio.get('https://api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room', ...)
```

從我這三次乾淨測試的 `--machine` 輸出裡撈出的實際回應（每回合 19 個 print 事件）：

```
RUN1 PRINT: realRoomId: 2388053, uid: 4272126
RUN1 PRINT: title: 呐，我好想你呀……
RUN1 PRINT: area_name: 虚拟Singer
RUN2 PRINT: realRoomId: 2388053, uid: 4272126   (同上)
RUN3 PRINT: realRoomId: 2388053, uid: 4272126   (同上)
```

前三個請求都沒有 try/catch（第 4 個才有）。**【推論】** 一旦 Bilibili 風控（`AGENTS.md` 自己記載的 `-352 / -412 / -509 / -799`）、網路不通、或該直播間被刪，`main()` 直接 throw → suite 載入失敗 → `flutter test` 非零退出 → CI 紅燈，而且錯誤訊息跟 FMP 的程式碼毫無關係。

---

### 1.6 實機驗證（Android 模擬器，本輪補做）

環境：AVD `Medium_Phone`（`sdk gphone16k x86 64`，1080x2400），
`flutter run -d emulator-5554` debug 模式，HEAD `b93f72c7`。

#### 1.6a 通知頻道名稱**永遠是英文**，與裝置語系無關 —— 已在裝置上確認

**【事實】實測步驟與觀察**：

| 步驟 | 指令 / 觀察 | 結果 |
|---|---|---|
| 1 | `adb shell getprop ro.product.locale` | `en-US` |
| 2 | 跑當前 build，`adb shell dumpsys notification` | `mName=FMP Audio Playback` |
| 3 | `adb shell cmd locale set-app-locales com.personal.fmp --locales zh-CN` | `[zh-CN]` |
| 4 | `am force-stop` + 重新啟動，`ax` 讀語意樹 | UI 已變簡中：`近期热门`、`查看全部`、`哔哩哔哩`、`显示菜单`、`274.2万` |
| 5 | 再讀 `dumpsys notification` | **`mName=FMP Audio Playback`（仍是英文）** |

步驟 4 證明 `LocaleSettings.useDeviceLocale()` 本身運作正常；步驟 5 證明通知頻道
名稱沒有跟著走。（測試後已用 `set-app-locales --locales ""` 還原。）

**【事實】根因 —— 從 pub cache 內實際使用的 `slang-3.32.0` 原始碼逐層追出**：

1. `lib/main.dart:91,93` 在 `AudioServiceConfig` 讀 `t.notification.channelName` /
   `channelDescription`。這是整個 `main()` 中**唯二**在
   `LocaleSettings.useDeviceLocale()`（`main.dart:137`）之前讀 `t.` 的地方 ——
   兩者相隔 46 行。
2. `lib/i18n/strings.g.dart:52`：`Translations get t => LocaleSettings.instance.currentTranslations;`
3. `slang-3.32.0/lib/api/singleton.dart:237-239`：`currentTranslations` 取 `translationMap[currentLocale]!`
4. 同檔 `:210-213`：`currentLocale` 取 `utils.parseAppLocale(GlobalLocaleState.instance.getLocale())`
5. `slang-3.32.0/lib/api/state.dart:17`：初值 `_currLocale = BaseAppLocale.undefinedLocale`
6. `slang-3.32.0/lib/api/locale.dart:82-83`：`undefinedLocale = FakeAppLocale(languageCode: 'und')`
7. `singleton.dart:54-64`：轉呼叫 `parseLocaleParts(languageCode: 'und', scriptCode: null, countryCode: null)`
8. `singleton.dart:82-97`：`'und'` 對不到任何 locale，`candidates` 為空，於是走
   **只比對 countryCode** 的分支：

   ```dart
   if (candidates.isEmpty) {
     // no matching language, try match country code only
     return locales.firstWhereOrNull((supported) {
           return supported.countryCode == countryCode;   // countryCode == null
         }) ??
         baseLocale;
   }
   ```

9. `strings.g.dart:28-30` FMP 的三個 locale：

   ```dart
   zhCn(languageCode: 'zh', countryCode: 'CN', ...),
   en(languageCode: 'en', ...),                    // countryCode 未給 -> null
   zhTw(languageCode: 'zh', countryCode: 'TW', ...);
   ```

   `en` 的 `countryCode` 是 `null`，`null == null` 成立 -> **回傳 `AppLocale.en`，
   根本走不到 `?? baseLocale`**。

**【推論】** 這比「base locale 洩漏」更隱蔽：`slang.yaml:1` 寫 `base_locale: zh-CN`、
`strings.g.dart:19` 也是 `_baseLocale = AppLocale.zhCn`，任何人讀設定都會預期 locale
初始化前拿到簡中；實際拿到的卻是**英文**，只因為 `en` 是唯一沒宣告 `countryCode` 的
locale。這是 slang 的行為細節，不是 FMP 寫錯，但後果由 FMP 承擔。

**【推論】影響面**：所有非英文使用者在系統「應用程式 -> 通知」設定頁看到的頻道名稱與
說明都是英文。範圍侷限在這一對字串（其餘 UI 都在 `runApp` 之後、locale 已就緒），但
這個**模式**是陷阱 —— 日後任何人在 `main()` 早期多加一處 `t.`，都會靜默拿到英文。

**【推論】修法**（本輪不動手，僅記錄）：把 `LocaleSettings.useDeviceLocale()` 移到
`AudioService.init()` 之前即可，兩者無先後依賴。附帶好處是消滅整個「早期讀 `t.`」的
類別。

#### 1.6b 截圖現況

**【事實】`screenshots/` 共 8 張，全部是 Windows 桌面版截圖，沒有任何 Android 畫面**
—— 我實際開啟 `screenshots/home-page.png` 檢視，畫面上有 Windows 標題列（FMP +
最小化/最大化/關閉按鈕）與桌面三欄佈局（左側導航 + 中央內容 + 右側「正在播放」面板）。
README 卻把其中 7 張排在 2 欄表格裡、與獨立的「FMP 桌面首頁」並列，讀者容易誤以為那
7 張是手機畫面。Android 是專案兩個目標平台之一，卻一張截圖都沒有。

| 檔案 | 最後更新 | commit | 尺寸 |
|---|---|---|---|
| `home_desktop.png` | 2026-02-13 | `e1c3db96` | 1584x991 |
| `home-page.png` | 2026-05-25 | `09000639` | 2560x1380 |
| `library-page.png` | 2026-05-25 | `09000639` | 2560x1380 |
| `lyrics-features.png` | 2026-05-25 | `09000639` | 2560x1380 |
| `queue-page.png` | 2026-05-25 | `09000639` | 2560x1380 |
| `radio-page.png` | 2026-05-25 | `09000639` | 2560x1380 |
| `search-page.png` | 2026-05-25 | `09000639` | 2560x1380 |
| `settings-page.png` | 2026-05-25 | `09000639` | 2560x1380 |

**【事實】`home_desktop.png` 與 `home-page.png` 拍的是同一個畫面（桌面首頁）**，但相差
3 個月、尺寸不同，README `:40` 與 `:45` 分別以「FMP 桌面首頁」和「首頁與排行榜」呈現。
至少有一張是冗餘的。

**【事實】截圖後 `lib/ui/` 有 84 個 commit**，被拍到的頁面原始碼都經歷大幅改寫：

```
$ git diff --stat 09000639..HEAD -- lib/ui
lib/ui/pages/settings/settings_page.dart        | 2532 +-------------
lib/ui/pages/player/player_page.dart            | 1661 ++++---------
lib/ui/pages/settings/database_viewer_page.dart | 1092 +--------
lib/ui/pages/radio/radio_player_page.dart       | 1080 +++------
lib/ui/pages/home/home_page.dart                |  689 ++----
lib/ui/pages/library/playlist_detail_page.dart  |  547 ++---
lib/ui/pages/radio/radio_page.dart              |  505 +---
lib/ui/pages/library/library_page.dart          |  307 +--
lib/ui/pages/search/search_page.dart            |  230 +-
lib/ui/pages/queue/queue_page.dart              |   73 +-
lib/ui/layouts/responsive_scaffold.dart         |   20 +-
```

**【推論】** 大量減號說明主要是「抽出子 widget」式的重構，行數變動**不能直接推論視覺
變動**。導航列本身沒變（`responsive_scaffold.dart:31-56` 仍是 home / search / queue /
library / radio / settings 六項，與截圖左欄一致）。

**【事實】附帶發現**：`lib/i18n/zh-TW/nav.i18n.json` 有 `"explore": "探索"` 這個 key，
但 `responsive_scaffold.dart` 的 6 個導航項沒有用到它。屬 §2.8 i18n 死 key 的同類。

#### 1.6c 截圖是否過時 —— 實跑桌面版比對後：**結論與我原本的預期相反**

**【事實】方法**：`flutter run -d windows`（HEAD `b93f72c7`），用
`orca computer get-app-state --app pid:50708` 擷取 1920x1200 原尺寸畫面
（存檔 `scratchpad/windows_home_current_20260901.png`），與 `screenshots/home-page.png`
（2026-05-25，`09000639`）逐區比對。

第一次擷取抓到的是別的視窗內容（`scale 0.409`、786x491）；用 Win32 `SetForegroundWindow`
把 FMP 視窗帶到前景後重擷才正確（`scale 1`、1920x1200）。這印證了
`.claude/skills/verify-on-device/SKILL.md` §6 的警告：Windows 端一律要用新截圖確認動作結果。

**【事實】同時確認 SKILL.md §6「Windows 無語意樹」的說法為真**：
`get-app-state` 回傳 `elementCount = 2`，`treeText` 只有
`0 window FMP - Flutter Music Pl`，沒有任何可斷言的元素。

**【事實】結構逐項比對** —— 兩張圖一致的部分：

| 區塊 | 2026-05-25 截圖 | 2026-09-01 實跑 |
|---|---|---|
| 左側導航列 | 漢堡鈕 + 首頁/搜尋/佇列/音樂庫/電台/設定 六項 | **完全相同** |
| 「近期熱門」區 | 標題 + 右側「查看全部」，多欄排行榜，每列 序號/縮圖/標題/UP主/播放數/三點選單 | **完全相同** |
| 「我的歌單」區 | 標題 + 「查看全部」，方形封面卡片 + 標題 + 「N 首」 | **完全相同** |
| 「正在播放」區 | 有 | **有** |
| 底部播放列 | 縮圖/標題/作者 + 隨機/上一首/播放/下一首/循環/音質/音量 | **完全相同** |
| 右側面板 | 存在，寬度相近 | **存在** |

**【事實】兩張圖不同的部分，逐項都能歸因到「執行時狀態」而非 UI 結構**：

| 差異 | 歸因 |
|---|---|
| 深色 vs 淺色主題 | 使用者主題設定（`preloadedThemeMode`），非程式碼變更 |
| 排行榜 3 欄（含網易雲音樂）vs 2 欄 | 本機未登入網易帳號；且首頁排行榜本來就有設定頁（`lib/ui/pages/settings/home_ranking_settings_page.dart`） |
| 歌單 6 張 vs 1 張 | 本機資料庫內容不同 |
| 右側面板顯示完整「正在播放/簡介/熱門評論」vs「載入失敗 + 重試」 | 本機該次請求失敗，是錯誤態而非版面改版 |
| 「電台」「接下來播放」區在實跑畫面看不到 | 在摺線以下，未捲動 |

**【推論】截圖並未結構性過時。** 儘管 §1.6b 顯示這些頁面的原始碼自截圖後有極大行數
變動（`settings_page.dart` -2532、`player_page.dart` -1661 等），首頁的**版面結構、
導航項、區塊順序、播放列控制項在 HEAD 上與截圖完全一致** —— 這正好佐證那些改動是
「抽出子 widget」型的重構，不是改版。

**因此 P3-6 原本「截圖可能過時」的疑慮**，就首頁而言**不成立**。P3-6 的真正問題退回到
§1.6b 已證實的兩點：**全是桌面截圖、零 Android**，以及 **`home_desktop.png` 與
`home-page.png` 重複**。

**未驗證**：我只逐項比對了首頁。其餘 6 張（音樂庫/搜尋/佇列/電台/歌詞/設定）沒有逐頁
比對 —— 但既然改動最劇烈的 `settings_page.dart`（-2532 行）與 `player_page.dart`
（-1661 行）所屬頁面的同型重構在首頁已被證明不影響版面，其餘頁面過時的機率相應下降。

### 1.7 `isar_community` 遷移實測（獨立 worktree，你放行後補做）

**方法**：`git worktree add --detach` 開一個丟棄式 worktree（主工作樹全程零改動），
生產資料庫 `C:/Users/Roxy/Documents/FMP/fmp_database.isar`（5,242,880 bytes）**複製兩份**
到 scratchpad，原始檔全程未開啟、mtime 未變。探測用測試 `test/isar_compat_probe_test.dart`
只存在於該 worktree，用**生產環境真正的** `fmpDatabaseSchemas`（11 個 collection）開檔，
逐 collection 計數，並實際取出記錄欄位（避免「開得起來但解碼成空值」被誤判成成功）。

#### 1.7a 結論：`.isar` 檔案格式**完全相容，不需要任何遷移**

| 指標 | `isar` 3.1.0+1（baseline） | `isar_community` 3.3.2 |
|---|---|---|
| 開檔耗時 | 55 ms | 25 ms |
| collection 數 | 11 | 11 |
| 總記錄數 | **1,523** | **1,523** |
| Track / PlayHistory / Playlist | 1194 / 323 / 1 | **1194 / 323 / 1** |
| Settings / SearchHistory / Account | 1 / 2 / 1 | **1 / 2 / 1** |
| DownloadTask / RadioStation / LyricsMatch / LyricsTitleParseCache | 0 / 0 / 0 / 0 | **0 / 0 / 0 / 0** |
| 檔案大小（開檔前 → 關檔後） | 5242880 → 5242880 | 5242880 → 5242880 |

取樣記錄逐字一致，含 CJK 與日文標題：

```
PROBE   id=1 | title=踊り子(舞女) / Vaundy ：MUSIC VIDEO | artist=Vaundy | sourceType=SourceType.bilibili | sourceId=BV1pWNFzvEa7 | durationMs=246000
PROBE   id=2 | title=“是7co新歌，有种夏日里冰冰凉凉的感觉！！”||《真夏のパンクリアス》 | artist=星光note | sourceType=SourceType.bilibili | sourceId=BV1GxjZ6bEih | durationMs=214000
PROBE   id=1 | playedAt=2026-08-09 15:05:33.119418
PROBE   id=1 | name=Music
```

（`Track=1194` 與 §1.6c 桌面截圖上「Music 1194 首」互相印證，確認讀到的是真實生產資料。）

**【事實】** 兩邊都是 `RESULT: OK`、`All tests passed!`，且關檔後檔案大小未變 ——
**不存在 v3 → v3 的資料遷移問題**。這回答了 §7 第 4 點 (a) 裡「需實測既有 `.isar` 檔
相容性」那個前提。

#### 1.7b 但遷移有一條非顯而易見的連鎖：**會強制升級 slang 到 4.x**

**【事實】** 直接換 generator 時 pub 解析失敗：

```
Because slang_build_runner <4.8.0 depends on build ^2.2.1 and
isar_community_generator >=3.3.1 depends on build ^4.0.0,
slang_build_runner <4.8.0 is incompatible with isar_community_generator >=3.3.1.
```

**【事實】generator 無法繞過。** 我試過保留 `isar_generator` 3.1.0 產生的 `.g.dart`
只換 runtime，編譯期即被擋下：

```
lib/data/models/track.g.dart:16:21: Error: Constant evaluation error:
isar_community-3.3.2/lib/src/schema/collection_schema.dart:24:24: Context:
  This assertion failed with message: Outdated generated code.
  Please re-run code generation using the latest generator.
          Isar.version == version,
```

`CollectionSchema` 建構式有 `assert(Isar.version == version)`，11 個模型全數被拒。
所以 **`isar_community` → `isar_community_generator` → `build ^4` → `slang 4.x` 是一條
不可切斷的鏈**。實測把 `slang_flutter` / `slang_build_runner` 一起升到 `^4.19.0` 後
解析成功。

#### 1.7c 遷移後的實測結果

`flutter analyze`（worktree，已完成全部改動）：

```
No issues found! (ran in 164.5s)
```

`flutter test`（worktree）：179 suites / 948 個可見測試 / **902 success、45 error、1 failure**。
失敗原因歸類後只有三類：

| 原因 | 次數 | 性質 |
|---|---:|---|
| `Bad state: Unsupported platform for Isar test setup` | 31 | **機械性** —— helper 找不到套件而 fall through |
| `Package not found in package_config.json: isar_flutter_libs` | 9 | **機械性** —— 同一個 helper 的另一種變體 |
| slang 4 的 lazy 載入留下 pending timer | 2 | **真實破壞**，見 1.7d |
| `BilibiliApiException(-429): 请求过于频繁` | 2 | 與遷移無關 —— 是 §1.5 那個真實網路請求問題又被觸發 |
| 探測測試自己（全套跑時沒給 `FMP_PROBE_DB_DIR`） | 1 | 預期內，非缺陷 |

**【事實】那 40 次機械性失敗全部來自同一個被複製 40 次的 helper。** `rg -l
"isar_flutter_libs" test/` 在主工作樹回報 **40 個檔案**，每個都自帶一份約 15 行的
「從 `package_config.json` 找出原生庫路徑」邏輯（兩種變體：35 個用
`Unsupported platform for Isar test setup` 當 fall-through 訊息、9 個用
`Package not found in package_config.json`）。

**【事實】社群版把 Windows 原生庫改名了**：上游是
`isar_flutter_libs-3.1.0+1/windows/isar.dll`，社群版是
`isar_community_flutter_libs-3.3.2/windows/libisar.dll`。那 40 個 helper 全部硬編
`isar.dll`。

**【推論】** 這 40 個失敗的真正成本不是 40 個檔案，而是**先抽出一個共用 test helper，
再改 1 個地方**。這件事本身就該做（見 §2.6 的測試重複問題），與 Isar 決策無關。

#### 1.7d slang 4 帶來的兩項真實破壞（`flutter analyze` 看不見）

**【事實】1：`useDeviceLocale()` 從同步變成非同步，而呼叫點沒有 `await`。**

slang 4.19.0 產生的 API：

```dart
static Future<AppLocale> useDeviceLocale() => instance.useDeviceLocale();   // :163
static AppLocale useDeviceLocaleSync() => instance.useDeviceLocaleSync();   // :174
```

`lib/main.dart:137` 的呼叫點是裸述句 `LocaleSettings.useDeviceLocale();`。在 slang 3
它同步完成後才走到 `:139` 的 `runApp()`；升到 slang 4 之後它變成 fire-and-forget
Future，**`runApp()` 可能在 locale 套用之前就執行**。

而 `analysis_options.yaml` 既沒開 `unawaited_futures` 也沒開 `discarded_futures`，
所以 `flutter analyze` 對此**完全沉默**（實測 `No issues found!`）。修法是改用
`useDeviceLocaleSync()` 或加 `await`。

**這正好是 P1-5（analysis 太寬鬆）預測會發生的那類問題，而且和 P1-9 是同一段程式碼。**

**【事實】2：slang 4 改用 lazy / deferred 載入翻譯，widget 測試會留下 pending timer。**

```
Pending timers:
#7      _loadLibrary (dart:core-patch/lib_prefix.dart:81:9)
#8      AppLocale.build (package:fmp/i18n/strings.g.dart:60:5)
#9      LocaleSettingsExt.loadLocale (package:slang/src/api/singleton.dart:310:30)
#10     LocaleSettingsExt.setLocale (package:slang/src/api/singleton.dart:390:7)
...
A Timer is still pending even after the widget tree was disposed.
```

（`test/ui/pages/home/home_ranking_sources_test.dart`，單獨重跑仍失敗。）這需要改測試
的 locale 設定方式，不是換個名字就能解決的。

#### 1.7e 對 §7 第 4 點的補充

原本 (a) 的成本標「M，需實測既有 `.isar` 檔相容性」。實測後可以拆得更精確：

| 工作 | 成本 | 性質 |
|---|---|---|
| `.isar` 資料遷移 | **零** | 已證實不需要 |
| 86 個檔的 import 改寫 | S | 一行 sed，可機械驗證 |
| pubspec 三個依賴替換 | S | — |
| 40 個測試 helper → 抽成 1 個共用 helper + 改 DLL 名 | S–M | 本來就該做 |
| **被迫升級 slang 3.32 → 4.19** | **M** | 非自願，是 `build ^4` 的傳遞後果 |
| 修 `useDeviceLocale()` 未 await | S | 但**必須知道它存在**才會去修 |
| 修 slang 4 lazy 載入造成的 widget 測試失敗 | M | 數量未完整盤點（本次只跑到 2 個） |

**【推論】** 換 `isar_community` 本身很乾淨（資料零風險、analyze 全綠）；真正的成本在
**被綁進來的 slang 4 升級**。如果打算做，建議**先單獨把 slang 升到 4.x 並穩定下來**，
再換 Isar —— 這樣兩個變更各自可回退，而不是一次吞下一個混合的大 diff。

**未驗證**：我沒有在 Android 上跑遷移後的 build（`isar_community` 宣稱修好 16KB page
size，這點無法從 Windows 桌面測試證實）；也沒有完整盤點 slang 4 會影響多少個 widget
測試。

---

## 2. 現況（附證據）

### 2.1 Agent 指令體系

#### 規模與載入行為

| 檔案 | 行 | bytes | ~tokens | 啟動時載入？ |
|---|---:|---:|---:|---|
| `CLAUDE.md` | 1 | 12 | ~3 | 是 |
| `AGENTS.md`（根） | 185 | 10,014 | ~2,500 | 是（經 `@AGENTS.md` 展開） |
| `lib/data/AGENTS.md` | 94 | 4,528 | ~1,130 | **否** |
| `lib/data/sources/AGENTS.md` | 222 | 12,310 | ~3,080 | **否** |
| `lib/providers/AGENTS.md` | 83 | 4,535 | ~1,130 | **否** |
| `lib/services/AGENTS.md` | 223 | 11,914 | ~2,980 | **否** |
| `lib/services/audio/AGENTS.md` | 208 | 10,057 | ~2,510 | **否** |
| `lib/ui/AGENTS.md` | 305 | 15,677 | ~3,920 | **否** |
| **合計** | **1,320** | **69,035** | **~17,250** | 只有 185 行是常駐 |

**【事實 — 官方文檔逐字】**（https://code.claude.com/docs/en/memory，我自己 WebFetch 核對過，非轉述）：

> "Claude Code reads `CLAUDE.md`, not `AGENTS.md`. If your repository already uses `AGENTS.md` for other coding agents, create a `CLAUDE.md` that imports it..."

> "**Size**: target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence."

> "Claude also discovers `CLAUDE.md` and `CLAUDE.local.md` files in subdirectories under your current working directory. Instead of loading them at launch, they are included when Claude reads files in those subdirectories."

> "Imported files are expanded and loaded into context at launch... with a maximum depth of four hops."

> "Splitting into `@path` imports helps organization but doesn't reduce context, since imported files load at launch."

**結論（三點，都可驗證）**：

1. **`CLAUDE.md` 只放 `@AGENTS.md` 是正確的，不是多餘，也不會載入兩次。** 官方 AGENTS.md 小節給的範例就是這一行，且 Windows 上官方明說要用 import 而非 symlink（symlink 需要管理員權限）。沒有這行的話，`AGENTS.md` 在 session 啟動時根本不會進 context。
2. **185 行的根 `AGENTS.md` 在 200 行預算內，1,320 行從來不會一次載入。** 「1313 行超出 agent 上下文」這個擔憂在載入量上不成立。
3. **但 6 個子樹 `AGENTS.md` 完全不享有 harness 保證的自動載入。** 官方的「子目錄自動載入」只認 `CLAUDE.md` / `CLAUDE.local.md` 兩個檔名。FMP 的子樹檔能不能進 context，**完全取決於模型是否自願遵循根檔那張路由表去 Read**。這是 prompt-level 的自願遵循，不是機制保證。
   **本 session 就是活證據**：我的 context 裡有根 `AGENTS.md` 全文，6 個子樹檔一個都沒有。

**【事實】** 官方對這個需求有正式機制：`.claude/rules/*.md` 配 `paths:` frontmatter —— "Path-scoped rules trigger when Claude reads files matching the pattern, not on every tool use."，而且官方在 Size 那段直接推薦它當作檔案過大的解法。FMP 目前 `.claude/` 底下只有 `skills/verify-on-device/`，沒有 `rules/`（`git ls-files .claude/` 只有 2 個檔）。

#### 規則抽驗：76 條

我派了兩個 opus 子代理逐條抽驗，並自己複驗了 9 條關鍵結論（`playlistProvider`、`_FmpImageCacheManager` 位置、`download_filenames.dart` 內容、slang 依賴型別、`source_capabilities.dart` 介面數、`audio_playback_types.dart` 行數、i18n key 對齊、空 catch 數、`.select(` 數）。抽驗結果全部吻合。

**總計 76 條斷言：63 條 ✅ 一致、12 條 ⚠️ 部分不符、1 條 ❌ 錯誤。**

準確率 83% 完全一致 —— 以 1,320 行、最後大改在 4 週前的 agent 指令來說，這是**相當好**的數字。但錯的那些有共同形狀，值得單獨說。

**❌ 唯一硬性錯誤 — `AGENTS.md:149`**

```
| `playlistProvider` / `playlistDetailProvider` — playlist management
```

`rg "\bplaylistProvider\b" lib` **零命中**。實際識別字是 `playlistListProvider`（`lib/providers/library/playlist_provider.dart:201`）。`playlistDetailProvider`（同檔 `:537`）是對的。
**【推論】** agent 照這個名字 grep 會直接落空，然後開始亂猜。這是 agent 文檔最糟的錯誤類型 —— 錯的識別字比沒有識別字更傷。

**⚠️ 12 條部分不符，歸成四類：**

| 類型 | 案例 | 問題 |
|---|---|---|
| **指錯位置** | `lib/services/AGENTS.md:221` 說 `_FmpImageCacheManager` 在 `image_loading_service.dart` | 實際在 `lib/core/services/network_image_cache_service.dart:431`；`image_loading_service.dart:33` 只有一行指向它的註釋 |
| | `lib/data/sources/AGENTS.md:32` 把 `ensureAudioUrl()` 寫在 Bilibili 章節 | 實際定義在 `lib/services/audio/audio_stream_manager.dart:124`，`lib/data/sources/` 內查無此識別字 |
| | `lib/services/AGENTS.md:177` § Windows Sub-Windows | 實作主體在 `lib/ui/windows/`，`lib/services/` 下沒有 `windows/` 子目錄 —— 依路由表走的 agent 會被導到錯的 scoped 檔 |
| **誇大範圍** | `lib/services/AGENTS.md:17-21` 說 6 個下載檔名都是 `download_filenames.dart` 的常數 | 實際只有 3 個（`cover.jpg` / `avatar.jpg` / `metadata.json`，`download_filenames.dart:11,14,17`）。`audio.m4a` / `P{NN}.m4a` 硬編在 `download_path_utils.dart:41,44`；`metadata_P{NN}.json` 硬編在 3 個檔 |
| | `lib/data/sources/AGENTS.md:122-125` 列 5 個窄能力介面，句式讀起來像完整清單 | `source_capabilities.dart` 實際宣告 **12 個**，漏了 `TrackDetailSource:55`、`PagedVideoSource:62`、`DynamicPlaylistSource:69`、`RankingSource:92`、`LiveSource:96`、基底 `SourceCapability:7` |
| | `lib/services/audio/AGENTS.md:80-82` 稱 `audio_playback_types.dart` 是「playback request/mode DTOs」 | 該檔**全長 6 行**，只有 `enum PlayMode`，零 DTO |
| **誇大強制力** | `lib/ui/AGENTS.md:44-46` 說 `ImageTargetSizes` 不得在 page 使用「is enforced by `ui_consistency_static_rule_test.dart`」 | 該測試 22 條 case 沒有任何一條掃 page 裡的 `ImageTargetSizes` 使用。真正強制的是「只有 5 個 `widgets/images/*` 可呼叫 `ImageLoadingService`」（test:451）與「呼叫必須帶 `targetDisplaySize`」（test:538）。規則現況成立，但沒有測試在守 |
| **描述指向空殼** | `lib/data/AGENTS.md:70-72` 說 `_migrateDatabase()` 是「the authoritative list of repaired fields」 | `_migrateDatabase()`（`database_provider.dart:215-217`）只有一行轉呼 `initializeDatabaseDefaults(isar)`；修復清單在 `_initializeDatabaseDefaultsInTxn`（`:170-203`）。agent 打開會看到空殼 |
| **覆蓋缺口** | `AGENTS.md:167-184` Key Paths 列 8 個 `lib/services/` 子目錄 | 實際有 16 個。未列：`cache/`、`database/`、`import/`、`library/`、`network/`、`platform/`、`refresh/`、`search/`、`update/`。其中兩處自相矛盾：`lib/providers/AGENTS.md:44-47` 要求 agent 操作 `RankingCacheService`（住在未列的 `services/cache/`）；`AGENTS.md:61` 把 "update" 列為需維護的變更區（`services/update/` 未列） |

#### 規則重複：根檔自己定的規矩被自己違反

**【事實】** `AGENTS.md:66-69` 寫著：

> "State each rule in exactly one file and cross-reference it from the others instead of restating it."

實測至少 **11 條規則**在 2–3 個檔被**完整重述**而非交叉引用：

| 規則 | 重複處 | 重數 |
|---|---|---:|
| UI 必須經 `AudioController`、不得直呼 `FmpAudioService` | `AGENTS.md:131` + `AGENTS.md:141-144` + `lib/services/audio/AGENTS.md:25-27` | 3 |
| Radio 是刻意例外 | `AGENTS.md`(Architecture Map) + `audio/AGENTS.md:29-31` + `services/AGENTS.md:173-175` | 3 |
| AXTree log spam 不得「修」 | `AGENTS.md:135-137` + `services/AGENTS.md:188-191` + `docs/troubleshooting.md` | 3 |
| 禁止 ad-hoc 開 Isar | `AGENTS.md:132` + `data/AGENTS.md:85-86` + `providers/AGENTS.md:66-68` | 3 |
| schema 變更 → build_runner + 兩個測試 | `AGENTS.md:93` + `data/AGENTS.md:80-82` + `providers/AGENTS.md:79-82` | 3 |
| 禁止 `Image.network()` / `Image.file()` | `AGENTS.md:134` + `ui/AGENTS.md:29-30` | 2 |
| 禁止隱藏全域 enabled-source 過濾 | `AGENTS.md:133` + `providers/AGENTS.md:50-52` | 2 |
| 下載封面 `high` / 頭像 `low` | `services/AGENTS.md:48-51` + `ui/AGENTS.md:59-61` | 2 |
| device DPR 只做 decode/disk sizing | `services/AGENTS.md:200-203` + `ui/AGENTS.md:66-69` | 2 |
| 驗證指令表 | `AGENTS.md:88-96` + `audio/AGENTS.md:200-207` + `ui/AGENTS.md:221-223,298-300` | 3 |
| on-device 驗證強制 | `AGENTS.md:98-110` + `ui/AGENTS.md:302-304` | 2 |

另外一處自我否定的寫法：`lib/ui/AGENTS.md:11` 說「Use `rg`/`ls` for the current inventory rather than trusting a list here」，但 `:9-10` 就列了完整的 14 個目錄清單（清單目前是準確的）。

#### 文體：散文太多

| 檔案 | 行 | 標題 | 條列 | 表格列 | 程式碼 | **散文** |
|---|---:|---:|---:|---:|---:|---:|
| `AGENTS.md` | 185 | 9 | 29 | 23 | 27 | 85 |
| `lib/data/AGENTS.md` | 94 | 6 | 7 | 17 | 0 | 41 |
| `lib/data/sources/AGENTS.md` | 222 | 9 | 38 | 4 | 0 | **134** |
| `lib/providers/AGENTS.md` | 83 | 4 | 23 | 6 | 0 | 35 |
| `lib/services/AGENTS.md` | 223 | 10 | 36 | 4 | 0 | **133** |
| `lib/services/audio/AGENTS.md` | 208 | 11 | 37 | 0 | 30 | **118** |
| `lib/ui/AGENTS.md` | 305 | 17 | 30 | 14 | 14 | **183** |
| 合計 | 1,320 | 66 | 200 | 68 | 71 | **729** |

**【推論】** 729 散文行 vs 200 條列行。上面所有「誇大範圍」「誇大強制力」的錯誤，都出在散文句子（"Shared names are constants in..."、"this is enforced by..."），不出在表格或條列。散文容易寫出無法逐條驗證的複合斷言 —— 這就是它腐爛得比表格快的原因。

### 2.2 `CONTEXT.md` / `docs/agents/` / `docs/adr/`

#### engineering skills 確實有安裝

**【事實】** `~/.claude/settings.json:161-164`：

```json
"enabledPlugins": {
  "mattpocock-skills@claude-plugins-official": true,
  "wayfinder-view@wayfinder-view": true
}
```

`mattpocock-skills` v1.2.3，`plugin.json` 宣告 25 個 skill，其中 `triage`、`wayfinder`、`to-tickets`、`to-spec`、`code-review`、`domain-modeling` 都在。**所以 `CONTEXT.md` 與 `docs/agents/*` 有真實消費者，不該刪。**

#### 但 `docs/README.md:39` 點名了一個不存在的 skill

**【事實】**

```
docs/README.md:39: `docs/agents/` 是 engineering skills（`/triage`、`/to-tickets`、
                   `/to-spec`、`/qa`、`/wayfinder` 等）讀取的專案設定
```

實測 v1.2.3 的 `skills/engineering/` 目錄：`triage` ✅、`to-tickets` ✅、`to-spec` ✅、`wayfinder` ✅、**`qa` ❌ 不存在**。

#### `CONTEXT.md` 已凍結

**【事實】** `git log -- CONTEXT.md`：只有 2 個 commit，都在 **2026-06-11**，之後 2.5 個月沒動過。`docs/agents/*` 三個檔各 1 個 commit，都在 **2026-07-27**（setup skill 跑那次），從未修訂。

**【事實】** `CONTEXT.md` 定義的 5 個術語與程式碼識別字的對照：

| CONTEXT.md 術語 | 程式碼對應 | 一致？ |
|---|---|---|
| Source Auth Context | `SourceAuthContext`（`lib/services/account/source_auth_context.dart:107`） | ✅ |
| Media Handoff | `MediaHandoff`（`lib/services/media/media_handoff.dart:50`） | ✅ |
| Stream Resolution Auth | 無同名識別字；概念散在 `StreamResolutionService` + `authForPlay()` | ⚠️ 概念存在、無識別字 |
| Auth For Play | `Settings.useAuthForPlay(sourceType)`（`settings.dart:593`）、`SourceAuthContext.authForPlay()` | ✅ |
| Media Request Credentials | 無同名識別字；實作是 `SourceHttpPolicy.mediaHeaders()` + allowlist（`source_http_policy.dart:34,143-146`） | ⚠️ 概念存在、無識別字 |

5 個術語 3 個有對應識別字，2 個是純概念詞。以 ubiquitous language 的用途（讓 agent 在 issue 標題、重構提案裡用一致的詞）而言，這是可接受的 —— 但那 2 個沒有識別字錨點的詞，會隨時間漂移。

#### `docs/adr/` 是本機幽靈目錄

**【事實】**

```
$ ls -la docs/adr        → 空目錄（只有 . 與 ..）
$ git ls-files docs/     → 10 個檔，無任何 docs/adr/*
$ git check-ignore docs/adr  → 未被 ignore，純未追蹤
```

git 不追蹤空目錄 → **clone 出來的 repo 根本沒有 `docs/adr/`**。但 `AGENTS.md:35-36` 把它跟 `CONTEXT.md` 並列為既有的 domain 文檔體系，`docs/agents/domain.md` 也叫 agent 去讀它。目前它是「規劃中」而非「現存」。

（`docs/agents/domain.md` 有寫「If any of these don't exist yet, proceed silently」，所以不會炸；但根 `AGENTS.md` 沒有這個免責。）

### 2.3 `docs/` 現況

| 檔案 | 行 | 讀者 | 語言 | 最後內容更新 | 判定 |
|---|---:|---|---|---|---|
| `README.md`（根） | 179 | 終端使用者 | **繁體** | 2026-08-25 | 健康 |
| `docs/README.md` | 49 | 人 + agent（索引） | **繁體** | 2026-08-25 | 健康（1 處錯誤，見上） |
| `docs/development.md` | 176 | 貢獻者 | **簡體** | 2026-07-27 | 大量重複 |
| `docs/build-guide.md` | 259 | 本機建置者 | **簡體** | 2026-07-27 | 與下一份重疊 38–43% |
| `docs/build-and-release.md` | 362 | 維護者/發版人 | **繁簡混用** | 2026-07-07 | 權威，2 處過期 |
| `docs/troubleshooting.md` | 45 | 開發者/agent | **繁體** | 2026-07-27 | 品質最高的一份 |
| `docs/debugging-with-vm-service.md` | 652 | agent/調試者 | **簡體** | 2026-08-25 | 保留 |
| `docs/history/refactoring-log.md` | 1046 | 歸檔 | **簡體為主、混用** | 內容停在 2026-03 | 需封存 |
| `docs/agents/*.md` ×3 | 122 | skill 工具鏈 | 英文 | 2026-07-27 | 保留 |

#### 語言：文檔自己宣稱的規則與現實不符

**【事實】** 用簡繁專屬字元計數（腳本掃全檔）：

| 檔案 | CJK 字數 | 簡體特徵字 | 繁體特徵字 | 判定 |
|---|---:|---:|---:|---|
| `README.md` | 1172 | 0 | 166 | 繁體 |
| `docs/README.md` | 846 | 0 | 128 | 繁體 |
| `docs/troubleshooting.md` | 484 | 0 | 58 | 繁體 |
| `docs/build-and-release.md` | 1740 | **140** | 100 | **混用** |
| `docs/build-guide.md` | 1196 | **139** | 0 | **簡體** |
| `docs/development.md` | 1093 | **206** | 0 | **簡體** |
| `docs/debugging-with-vm-service.md` | 2012 | **326** | 0 | **簡體** |
| `docs/history/refactoring-log.md` | 5553 | **576** | 206 | **簡體為主、混用** |
| `docs/` 全體 | 14,108 | **1,387** | 659 | **簡體是多數** |
| `lib/` 註釋（311 檔，252 檔含 CJK） | 64,484 | **7,029** | 2,749 | **簡體是多數** |

但：

- `docs/agents/issue-tracker.md`：「Issue titles and bodies are written in **Traditional Chinese** (台港用語), matching `docs/` and the root `README`.」
- `docs/agents/domain.md`：「ADRs are written in **Traditional Chinese** (台港用語), matching the rest of `docs/`.」

**「matching the rest of `docs/`」是錯的。** `docs/` 的多數（7 份中 4 份，且是字數最多的 4 份）是簡體或混用。這兩句話會讓 skill 產出的 issue / ADR 用一個與大部分現有文檔不一致的變體。

順帶：`slang.yaml:1` `base_locale: zh-CN` —— app 的 i18n 基準語系也是簡體。

**【推論】** 這不是「繁簡哪個對」的問題，是「文檔宣稱的規則與實際狀態不符」的問題。目前的真實狀態是：**新寫的（2026-07 之後）是繁體，舊的是簡體，沒有人回頭統一。** 文檔應該誠實描述這件事，或者真的統一。

#### `build-guide.md` vs `build-and-release.md`

**【事實】** 兩份逐字或近乎逐字重複約 **100–110 行**：

- 簽名金鑰（`keytool` 指令、`key.properties` 格式、`.gitignore` 警語）：`build-guide.md:64-97` ↔ `build-and-release.md:20-59`
- Windows 安裝包（方法一/二、SMTC AppUserModelID C++ 片段、`inno_bundle` yaml、相關檔案表）：`build-guide.md:120-196` ↔ `build-and-release.md:107-166`

佔 `build-guide.md`（259 行）的 **38–43%**，佔 `build-and-release.md`（362 行）的 **28–30%**。

各自獨有的部分**完全不重疊**：
- `build-guide.md` 獨有：前置條件表、Windows 原生工具（NuGet CLI / Rust toolchain）安裝、**Windows 建置排錯**（`NUGET-NOTFOUND`、`cargo` 缺失、`resolve_symlinks.ps1` warning 等）
- `build-and-release.md` 獨有：GitHub Secrets、CI 流程圖、版本號規則、Release 產物命名表（實測與線上 v1.9.1 的 10 個 asset 檔名**完全一致**）、應用內更新機制、FAQ

**【推論】** 分工線其實已經存在且清楚（`docs/README.md:35` 已定義），只是內容沒真的切乾淨。目前兩邊沒有分歧，但這是結構性風險：改一邊、另一邊悄悄過期。

#### `debugging-with-vm-service.md`（652 行）

**【事實】** FMP 特有內容約 60–90 行（**9–14%**）：§3.5–3.6 的 HTTP/Socket profiling 實測失效結論（`:257-303`，約 47 行）、§4.3 的 render tree 3.85 MB 實測（`:369-381`）、§5 的 `fmp_database` 實例名與隱私警語。其餘 85%+ 是 Dart VM Service Protocol 與 Flutter Engine Service Extensions 的通用行為。

**【事實】** §3.5–3.6 的「對 FMP 無效」寫得很紮實：2026-07-27 實測，三個音源載入上百首排行榜後 `getHttpProfile` 回 0 個請求；啟用 `httpEnableTimelineLogging`（回 `{'enabled': True}`）後仍 0；`getVMTimeline` 的 12,934 個事件裡 HTTP/Socket 相關為 0；`getSocketProfile` 回 0 sockets。文中甚至保留了一個未排除的替代解釋並說明為何站不住腳。

**【事實】** 根 `AGENTS.md:45-50` 引用它時提到的 §3.2–3.3、§3.4、§4.3（含 3.85 MB）、§5、§3.5–3.6 章節編號，**逐一核對全部正確**。這是全 repo 內 AGENTS.md 與 docs 互相引用最精確的一組。

**【建議】不要精簡篇幅。** 「85% 可從官方文檔查到」不等於「agent 會去查」。真正該做的是每次 Dart/Flutter 大版本升級時重驗 §3.5–3.6 與 §4.3 的實測結論。

#### `docs/history/refactoring-log.md`（1046 行）

**【事實】**
- 內容最後一筆是 **2026-03**（條目 #27、#28），距今 5–6 個月。檔案最後一次 git 異動 2026-07-07（加歸檔 banner，非新增內容）。
- **編號錯亂**：`:882` 條目 25（2026-02）→ `:918` 條目 **28**（2026-03）→ `:940` 插入「常用工具组件」表 → `:954` 條目 **26**（2026-02）→ `:1004` 條目 **27**（2026-03）。
- **已有失效路徑**：`:944` 的「常用工具组件」表列 `lib/ui/widgets/track_thumbnail.dart`，實際已搬到 `lib/ui/widgets/images/track_thumbnail.dart`（同表其餘 6 個路徑都存在）。
- 部分教訓已被吸收進 `AGENTS.md`（條目 8 ListTile leading Row → `ui/AGENTS.md:181-184` + static rule 測試；條目 19 FutureProvider invalidate → `providers/AGENTS.md:34`；條目 25 子視窗插件 → `services/AGENTS.md:179-182`）。
- 部分**尚未**被吸收：條目 27（Windows 全域快捷鍵序列化同步管線）、條目 28（retained context vs active ownership，雖然 `services/AGENTS.md:160-175` 有 Radio Ownership 章節但角度不同）。

### 2.4 `lib/` 目錄結構

**【事實】** 實測（排除 13 個 `.g.dart`）：

| 目錄 | 檔 | 行 | Riverpod provider 宣告 |
|---|---:|---:|---:|
| `lib/core/` | 18 | 3,044 | 2 |
| `lib/data/` | 46 | 12,121 | 3 |
| `lib/services/` | 84 | 30,948 | **29** |
| `lib/providers/` | 40 | 8,636 | 151 |
| `lib/ui/` | 121 | 39,349 | 1 |
| 合計 | 309（+main+i18n≈311） | 94,098 | |

**【事實】跨層耦合實測**：

- `lib/services/` → `lib/providers/` **反向依賴：6 檔 14 處**（下層 import 上層，layer-first 的定義性違規）：
  ```
  lib/services/audio/audio_provider.dart:18-24            ← 7 處
  lib/services/refresh/auto_refresh_service.dart:7-8      ← 2 處
  lib/services/radio/radio_controller.dart:13-14          ← 2 處
  lib/services/download/download_path_sync_service.dart:8
  lib/services/download/download_path_maintenance_service.dart:9
  lib/services/backup/backup_service.dart:18
  ```
- `lib/ui/` 121 檔中，**41 檔同時 import `services/` 與 `providers/`**（65 檔 import services、51 檔 import providers）。**對消費端而言這條邊界不存在。**
- **29 個 provider 宣告住在 `lib/services/`**：`audio/audio_provider.dart` 15 個（`:116, :3218, :3226, :3237, :3247, :3259, :3340-3378`）、`radio/radio_controller.dart` 7 個（`:1111-1155`）、`network/connectivity_service.dart` 3 個、其餘 4 檔各 1 個。

**【事實】反向的證據也成立 —— `providers/` 裡有大量業務邏輯**：

| 檔案 | 行 | 內容 |
|---|---:|---|
| `providers/download/download_scanner.dart` | 413 | `Isolate.run()` 目錄掃描 + DTO；被 `services/download/` 兩個檔反向 import |
| `providers/download/download_event_handler.dart` | 62 | **整檔沒有 `flutter_riverpod` import**，是 debounce + 批次聚合的純邏輯類 |
| `providers/download/file_exists_cache.dart` | 264 | 有界快取實作 |
| `providers/lyrics/lyrics_provider.dart:340-441` | ~100 | 多源並行 fan-out + 優先序拼接 + per-source `catchError` 降級 + `requestId` 競態取消 |
| `providers/search/search_provider.dart:230,315,407,618,667,731` | — | 多源分頁編排（`SearchService` 只有 242 行） |
| `providers/library/playlist_provider.dart:268-536` | ~270 | `PlaylistDetailNotifier` 的樂觀更新 + 回滾 |
| `providers/database/database_provider.dart` | — | Isar 開啟 + `_migrateDatabase()` + 舊值簽章偵測 → 這是**持久化層**的 migration |

**【事實】7 個單檔子目錄**（目錄名 = 檔名去掉 `_service` 後綴，一層目錄零資訊）：

| 目錄 | 檔案 | 行 |
|---|---|---:|
| `services/update/` | `update_service.dart` | 895 |
| `services/cache/` | `ranking_cache_service.dart` | 519 |
| `services/database/` | `data_integrity_service.dart` | 373 |
| `services/media/` | `media_handoff.dart` | 253 |
| `services/search/` | `search_service.dart` | 242 |
| `services/refresh/` | `auto_refresh_service.dart` | 157 |
| `services/network/` | `connectivity_service.dart` | 138 |

### 2.5 命名

**【事實】檔案與 provider 命名高度一致**：
- `lib/` 全部 311 個 `.dart` 都是 snake_case（唯一「例外」是 13 個 `.g.dart` 生成檔）。
- 190 個 provider 全部以 `Provider` 結尾，零例外。
- 19 個自訂例外全部 `XxxException`，16 個 `implements Exception`、3 個 `extends SourceApiException`。

**【事實】類別命名**：`lib/` 共 **738 個 class**（不含 `.g.dart`），其中 241 個是 private（`_` 開頭，33%）。後綴分佈：

| 後綴 | 數 | 後綴 | 數 |
|---|---:|---|---:|
| `State` | 107 | `Notifier` | 30 |
| `Tile` | 44 | `Page` | 28 |
| `Service` | 37 | `Exception` | 19 |
| `Result` | 33 | `Repository` / `Source` | 11 / 11 |
| `Handler` | 7 | `Manager` | 6 |
| `Controller` | 4 | `Coordinator` | 3 |

**【推論】** 後綴用得很有紀律，沒有 `XxxImpl` / `XxxHelper` / `XxxUtil` 這種無語意命名氾濫。**但「協作者」類的後綴有五種並存**：`Service`(37) / `Manager`(6) / `Controller`(4) / `Coordinator`(3) / `Handler`(7)，且沒有任何文檔說明它們的分工。這在 §5.3 的目錄重構時會變成實際問題 —— 決定一個類別該進 `features/<x>/` 還是 `core/` 時，名字給不出線索。**建議在重構同輪把這五個後綴的語意寫進 `AGENTS.md`（各一行），而不是現在單獨去改名。**

**【事實】** `lib/services/` 根目錄有一個散裝檔 `storage_permission_service.dart`（16 個子目錄之外）。`lib/providers/AGENTS.md:7-8` 與 `lib/ui/AGENTS.md:7-8` 都明文禁止在各自根目錄直接放 `.dart`，但 `lib/services/AGENTS.md` 沒有對應規則。

（附帶更正：本輪任務書寫「`services/` 17 個子目錄」，實測是 **16 個子目錄 + 1 個散裝檔**。`providers/` 10 個子目錄則完全吻合。）

**【事實】唯一的命名問題 —— 21 個 `*_phaseN_test.dart`**：

```
test/services/audio/audio_controller_phase1_test.dart
test/services/download/download_service_phase1_test.dart
test/providers/download_providers_phase2_test.dart
test/providers/import_playlist_provider_phase2_test.dart
test/providers/playlist_provider_phase2_test.dart
test/services/download/download_path_maintenance_service_phase2_test.dart
test/services/radio/radio_controller_phase2_import_test.dart
test/ui/pages/history/play_history_page_phase2_test.dart
test/ui/pages/search/search_page_phase2_test.dart
test/data/sources/source_ownership_phase3_test.dart
test/data/repositories/play_history_repository_phase4_test.dart
test/providers/download/file_exists_cache_phase4_test.dart
test/providers/download_providers_phase4_test.dart
test/providers/play_history_provider_phase4_test.dart
test/services/audio/audio_auth_retry_phase4_test.dart
test/services/audio/audio_runtime_platform_phase4_test.dart
test/services/import/import_service_phase4_test.dart
test/services/lyrics/lyrics_auto_match_service_phase4_test.dart
test/services/platform/windows_desktop_service_phase4_test.dart
test/ui/pages/player/player_page_phase4_test.dart
test/ui/pages/settings/download_manager_page_phase4_test.dart
```

**這些 phase 編號指向已被刪除的計劃文檔。** 完整時間軸（全部 `git log` 可查）：

| 日期 | 事件 |
|---|---|
| 2026-04-14 | `docs/review/*_review.md` 八份審查報告加入（`d3e595c1`） |
| 2026-04-15 | `audio_controller_phase1_test.dart` 加入（`df204746`） |
| 2026-04-21 | `download_providers_phase2_test.dart` + `play_history_page_phase2_test.dart` 加入（`a4dcc315`） |
| 2026-04-23 | `download_providers_phase4_test.dart` 加入（`92e5c872`） |
| 2026-04-24 | `docs/superpowers/plans/2026-04-24-review-driven-refactor-phase-1.md` 加入 |
| 2026-04-25 | phase-2 / -3 / -4 三份計劃文檔加入；`source_ownership_phase3_test.dart` 加入（`f6dee33d`） |
| **2026-04-29** | **`b160893f` "docs: delete outdated docs" —— 八份審查報告 + 四份計劃文檔全部刪除** |

**【推論 — 有一處不確定，如實標註】** 部分測試檔（如 phase4 的 `download_providers_phase4_test.dart`，04-23）**早於**同編號的計劃文檔（phase-4，04-25），所以「測試檔名 ↔ 計劃文檔」不是嚴格一對一；編號可能先來自 04-14 那批審查報告，計劃文檔後補。

但**載重的事實不受影響**：現存文檔中**沒有任何一處**解釋這個命名。`rg -ni "phase ?1|phase1|階段" docs/ AGENTS.md lib/*/AGENTS.md lib/*/*/AGENTS.md` 唯一命中是 `refactoring-log.md:514`，講的是另一件事（`_PlaybackContext` 的 Phase 1→2）。

（子代理主張 `a4dcc315` 同時加入 phase2 與 phase4 測試、因此不存在全域階段編號 —— 我核對過該 commit 的 `--stat`，它只動了 5 個檔，新增的兩個測試**都是 phase2**。這條反證不成立。）

**同類問題 —— 3 個程式碼註釋引用已刪除的文檔**：

```
lib/core/constants/download_filenames.dart:4        （C8 / 01-action-plan.md）
lib/data/repositories/search_history_repository.dart:10  （C10 / 01-action-plan.md）
test/data/sources/source_http_policy_credentials_test.dart:10  （F5 / 01-action-plan.md）
```

`docs/review/01-action-plan.md` 生於 2026-07-01（`6e3fcbe8`）、死於 2026-07-07（`2d9701fd` "delete: remove outdated documentation"）。**存活 6 天。**

**【推論】** `docs/review/` 這個目錄在本 repo 已經是第三代了（2026-04 八份 → 刪；2026-07 八份 → 刪；本輪）。前兩代都在寫完不到一個月內被刪掉，但**程式碼與測試檔名裡的引用留了下來**。這是「審查報告當一次性產物」與「程式碼引用它當永久標識」之間的結構衝突。

### 2.6 測試資產盤點

**【事實】規模**：184 個 `.dart`、46,357 行。`test(` 1,140 + `testWidgets(` 101 = 1,241 個測試案例（與 runner 回報的 1,241 完全吻合），`group(` 258。

| 一級目錄 | 檔 | 行 |
|---|---:|---:|
| `test/`（根） | 2 | 939 |
| `test/core` | 7 | 958 |
| `test/data` | 23 | 5,666 |
| `test/demo` | 6 | 2,017 |
| `test/performance` | 2 | 550 |
| `test/providers` | 25 | 5,532 |
| `test/services` | 70 | 23,298 |
| `test/support` | 1 | 397 |
| `test/ui` | 47 | 6,969 |
| `test/workflows` | 1 | 31 |

#### 分類彙總（184 檔全數分類，逐檔理由見子代理報告）

| 分類 | 檔 | 行 | 佔比 |
|---|---:|---:|---:|
| **行為測試** | 144 | 40,578 | 78.3% |
| **靜態規則 / lint 測試** | 17 | 2,485 | 9.2% |
| **實作細節測試** | 14 | 859 | 7.6% |
| **過時** | 7 | 2,028 | 3.8% |
| **重複** | 1 | 10 | 0.5% |
| （非測試：測試替身 `test/support/fakes/fake_audio_service.dart`） | 1 | 397 | 0.5% |
| **無法理解** | **0** | 0 | 0% |

**【推論】78% 是真正的行為測試、0 個無法理解 —— 這個測試套件的體質比預期好很多。** 需要處理的只有 7 個「過時」與 1 個「重複」，合計 8 檔 2,038 行（4.4%）。

**過時 7 檔**：`test/widget_test.dart`（11 行，Flutter 樣板佔位，內容是 `expect(true, isTrue)`，從未替換）+ `test/demo/` 全部 6 檔。
**重複 1 檔**：`test/services/lyrics/lyrics_window_layout_test.dart`（10 行）與 `lyrics_window_style_test.dart` 的 `'LyricsWindowLayout'` group 測同一類別，應合併。

#### 特殊目錄的存在理由

| 目錄 / 命名 | 是什麼 | 判定 |
|---|---|---|
| `*_phaseN_test.dart` ×21 | 2026-04 一系列 `refactor(...)` commit 各自留下的回歸鎖。大多數（17/21）測真實行為，4 個以掃原始碼字串為主 | **內容值得留，名字該改**（見 P0-4） |
| `test/demo/` ×6 | 手動 API 探索腳本，0 個 `test()`，真打 Bilibili / 網易雲 / QQ 音樂線上 API，檔頭註明「運行方式：`dart run test/demo/xxx.dart`」。用途已被正式實作 + mock 測試取代 | **6 個都過時**；其中 `bilibili_info_test.dart` 因檔名被 CI 誤收（P0-2） |
| `test/performance/` ×2 | 真的在量測時間，12 條硬編 wall-clock `lessThan()` | **移出預設套件**（P0-1） |
| `test/workflows/` ×1 | 讀 `.github/workflows/release.yml` **原始碼字串**做斷言。3 條都是對過去 CI bug 的迴歸防護（`commits<<EOF` heredoc 注入、changelog delimiter 換行、versionCode 公式） | **保留**。極度實作耦合，但守的是真實踩過的坑 |
| `test/ui/static_rules/` ×2 | `list_tile_leading_static_rule_test.dart`（26 行，1 條規則）+ `ui_consistency_static_rule_test.dart`（871 行，21 條規則）。合計 22 條，**0 個白名單 / 例外清單**（搜 `allowlist\|whitelist\|exempt\|excluded` 零命中） | **保留但正名**：這是 lint，不是測試 |

**【事實】「靜態掃描原始碼」不只在 `static_rules/`**：全 `test/` 有 **46 個檔**用 `readAsStringSync()` 對 `lib/` 原始碼做字串斷言。有的整檔都是（`source_ownership_phase3_test.dart`），有的只在行為測試裡夾帶 1–2 條（`library_invalidation_coordinator_test.dart`）。

**【推論】** 46/184 = 25% 的測試檔含有原始碼字串斷言。這類斷言的特性是：**重構改寫法就會紅，即使行為完全正確**。它們在守真實的架構邊界（禁止 ad-hoc 建構 Source、禁止繞過 `SourceHttpPolicy`、禁止頁面級 `ref.watch` 全狀態監聽），價值是真的；但如果做 §5.3 的目錄重構，這 46 個檔會是最大的改動面。**這是評估重構成本時必須先知道的數字。**

#### 脆弱 / flaky 訊號清單

| 風險 | 位置 | 嚴重度 |
|---|---|---|
| **真實網路** | `test/demo/bilibili_info_test.dart`（全檔） | **最高** —— 見 §1.5 |
| **硬編 wall-clock 斷言** | `startup_benchmark_test.dart:39,72,100,130,157,181`；`list_scrolling_benchmark_test.dart:58,99,153,239,283,327,361` | **最高** —— 4/4 負載回合必失敗 |
| 真實時間輪詢（`DateTime.now()` + `while` deadline） | `playlist_provider_phase2_test.dart:213-214`、`refresh_provider_stale_cleanup_test.dart:371-372`、`radio_controller_refresh_stale_test.dart:153-154`、`radio_controller_phase2_import_test.dart:145-146`、`lyrics_window_service_test.dart:179-180`、`audio_queue_state_provider_test.dart:139,141` | 中 |
| `Stopwatch` 逾時輪詢 | `audio_controller_mix_boundary_test.dart:350-364`（逾時直接 `fail()`）、`file_exists_cache_phase4_test.dart:7-14`（10ms 輪詢 / 2s 逾時） | 中 |
| 緊湊真實延遲製造時間差 | `search_history_repository_test.dart:57,59,71,83,117`（連續 5 處 `Future.delayed(2ms)`，用來讓 Isar 時間戳產生差異以驗證排序） | 中 |
| 時間容忍帶斷言 | `stream_resolution_service_test.dart:153,164,175-184`（1 秒寬容帶比對 `audioUrlExpiry`） | 低 |
| 全域靜態單例覆寫 | `radio_controller_refresh_stale_test.dart:18`、`radio_controller_phase2_import_test.dart:26`（都寫 `RadioRefreshService.instance`） | 低（`flutter test` 每檔獨立 isolate） |
| 真實檔案系統 | 約 20 檔用 `Directory.systemTemp.createTemp(...)`，均搭配 `tearDown` 清理 | 低（Windows 上檔案鎖定偶爾會讓刪除失敗） |

**【事實】正面結果（三項）**：
- 全 `test/` **0 處 `Random()`**（有無 seed 都沒有）。
- 除 `test/demo/` 外，**所有 `Dio()` 都掛了假 `httpClientAdapter`** —— 沒有其他真實網路請求。
- **0 處 mockito 的 `verify()` / `verifyInOrder()` / `verifyNever()`** —— 沒有依賴呼叫順序的 mock 驗證測試。

#### 清理後的目標規模

| 動作 | 減少 |
|---|---:|
| 移除 `test/demo/` 6 檔 | −2,017 行 |
| 移除 `test/widget_test.dart` 佔位 | −11 行 |
| 合併 `lyrics_window_layout_test.dart` | −10 行 |
| `test/performance/` 2 檔移出預設套件（不刪，改名） | −550 行（從套件計） |
| **目標** | **175 檔 / 43,769 行 / 1,241 測試**（測試數不變，因為刪掉的都沒有 test case） |

### 2.7 依賴健康度

完整表格見子代理報告；此處只留結論。

**【事實】7 個宣告但 `lib/`、`test/`、`android/`、`windows/` 全域零 import 的直接依賴**（我自己複驗過）：

| 套件 | 宣告版本 | 說明 |
|---|---|---|
| `riverpod_annotation` | ^2.6.1 | 且 `riverpod_generator` **不在** dev_dependencies → codegen 根本跑不起來；`@riverpod` 用量 0 |
| `logger` | ^2.5.0 | 專案用自寫的 `lib/core/logger.dart`。同名不同物，最容易誤導後續開發者 |
| `dynamic_color` | ^1.7.0 | 無 `DynamicColorBuilder` / `CorePalette` |
| `flutter_reorderable_list` | ^1.3.1 | UI 用的是 Flutter 內建 `SliverReorderableList`；該套件已 3 年 4 個月未更新 |
| `uuid` | ^4.5.1 | 無 `Uuid(` |
| `collection` | ^1.19.1 | 無 `firstWhereOrNull` 等 |
| `intl` | ^0.20.2 | 無 `DateFormat(` / `NumberFormat(`（可能只是為滿足 `flutter_localizations` 的版本解析，移除前需確認） |

（`isar_flutter_libs`、`media_kit_libs_windows_audio` 是原生綁定包，0 import 屬正常，不列入。）

**【事實】Isar 生態現況（子代理查證 pub.dev API + GitHub）**：

- `isar` 3.1.0+1 發布於 **2023-04-25**（3 年 4 個月前）。
- pub.dev 的 `isDiscontinued` / `isUnlisted` / `replacedBy` **三者皆為 null** —— 從 pub.dev 完全看不出上游已停擺。
- `isar/isar` repo 未 archive，但最後 commit **2025-06-14**，最後 release 停在 `4.0.0-dev.14`（2023-08-21），近期 issue（含 #1751 Android 16KB page size）無維護者回應。
- 討論串 `isar/isar#1689`「Isar is dead, long live Isar」（52 則留言，最後更新 2026-08-24）確認原作者已放棄且未交接。
- 社群 fork `isar_community` 3.3.2（2026-03-23 發布）**下載量約為原版 20 倍**（79,402 vs 3,804），已修 Android 16KB page size、GLIBC_2.36、Flutter 3.35 相容性。同 v3 binary format、API 相同。
- 無官方 v3→v4 migration 工具（`isar/isar#1595` 開兩年零回覆）。

**【事實】`lib/data/AGENTS.md:12-13` 的說法需要更新**：

> "v3 is upstream's recommended production version. The upstream `isar/isar` repository is **not** archived; its README states v4 is not production-ready."

字面上都對（repo 確實沒 archive，README 確實那樣寫），但這個框架把「上游還在」當成理由，而上游其實已經停擺 14 個月。文檔沒提 `isar_community` 這個生態實際採用的中繼方案 —— 而 issue #44 已經在講這件事了。

**【事實】其他值得注意的落後**：

| 套件 | 目前 | 最新 | 落後 | 影響檔數 |
|---|---|---|---|---:|
| `flutter_riverpod` | 2.6.1 | 3.4.2 | 1 major（3.0 移除 `StateNotifierProvider` 等） | 103 |
| `go_router` | 14.8.1 | 18.0.0 | 4 major | 12 |
| `file_picker` | 8.3.7 | 12.1.2 | 4 major | 2 |
| `slang_flutter` / `slang_build_runner` | 3.32.0 | 4.19.0 | 1 major | 2 |
| `flutter_secure_storage` | 9.2.4 | 11.0.0 | 2 major | 4 |
| `build_runner` | 2.4.13 | 2.16.0 | 多個 minor | dev-only |
| `audio_session` | 0.1.25 | 0.2.4 | caret 卡死 | 2 |
| `tray_manager` | 0.2.4 | 0.5.3 | 官方公告正遷往 `nativeapi-flutter` | 1 |

**【事實】Android 建置工具鏈三項都已被 Flutter 3.47.1 標記為即將淘汰**（本輪實跑
`flutter run -d emulator-5554` 時由 Flutter 工具自己印出，非我推測）：

| 項目 | 目前 | Flutter 要求 | 宣告位置 |
|---|---|---|---|
| Gradle | 8.14.0 | >= 9.1.0 | `android/gradle/wrapper/gradle-wrapper.properties:5` |
| Android Gradle Plugin | 8.11.1 | >= 9.0.1 | `android/settings.gradle.kts:22` |
| Kotlin (KGP) | 2.2.20 | >= 2.3.20 | `android/settings.gradle.kts:23` |

原文均為 "will soon be dropped. Please upgrade ... soon."。目前只是 warning、建置
成功（`Running Gradle task 'assembleDebug'... 13.8s` -> `Built app-debug.apk`），
但這是**有明確時限的**技術債：Flutter 一旦真的移除支援，Android build 會直接斷。
先前的依賴健康度盤點只看 `pubspec.yaml`，完全沒有涵蓋這一層。

**【事實】** `AGENTS.md:81` 的 `dart run slang` 目前可跑（我實測 `dart run slang stats` EXIT=0，三語系各 1230 條），但 `slang` 本身在 `pubspec.lock` 是 **transitive** 依賴（由 `slang_flutter` / `slang_build_runner` 帶入），pubspec 沒有直接宣告。任何依賴樹調整都可能讓這條指令失效。

### 2.8 程式碼一致性

一致性整體很好，以下只列量化結果與需要處理的部分。

**做得好的（高度一致）**：

| 面向 | 證據 |
|---|---|
| Logging | 單一門面 `AppLogger`（`lib/core/logger.dart:55`）+ `mixin Logging`（`:246`），752 次呼叫；生產碼 `print(` **0 次**；`AppLogger` 有敏感字串遮罩（`Authorization` / `Cookie` / `SAPISIDHASH` / `Bearer` / `MUSIC_U`） |
| i18n | 三語系（en / zh-TW / zh-CN）各 41 個 `*.i18n.json`、各 **1230 個 leaf key**；程式化 diff 雙向缺漏皆為 **0**（我自己複驗） |
| 硬編碼使用者字串 | `Text('...')` 掃描僅 19 筆命中，人工核實後全為品牌詞（`FMP` / `VIP` / `Mix` / `YouTube` / `P$n`）或開發者工具頁；`SnackBar` / `AlertDialog(title:)` 硬編碼 **0 筆** |
| 例外命名 | 19 個自訂例外全部 `XxxException`，零例外 |
| Riverpod 風格 | 單一風格（手寫 `StateNotifierProvider` 世代 API），無 codegen 與手寫並存；`ref.watch` 411 / `ref.read` 342 / `.select(` 72，在 build 外或 callback 內誤用 `ref.watch` 初篩 13 筆，逐一人工核實**全為合法模式** |
| lint ignore | `lib/` 全域只有 **2 處** `// ignore:` |
| 斷點常數 | `lib/ui/` 裸 `600` 只有 2 處且與斷點無關（對話框尺寸），裸 `1200` **0 處** |

**需要處理的**：

| 面向 | 量化 | 代表位置 |
|---|---|---|
| **空 catch** | **37 處 / 13 檔**，靜默吞例外 | `lib/ui/windows/lyrics_window.dart:384,390,396,419,444,455,469,484,497`（9 處）、`youtube_login_page.dart:50,53,56,207,227,290`（6 處）、`download_scanner.dart:192,208,229,347`、`update_service.dart:74,272,739`、`netease_source.dart:809,856` |
| **`unawaited(` 錯誤處理不一致** | 17 處，只約 4 處配 `.catchError` | `audio_provider.dart:515`、`library_invalidation_coordinator.dart:181-184` 有配；其餘 13 處靠被呼叫方自理 |
| **`analysis_options.yaml` 過寬** | 只有 `flutter_lints` + 2 條 const 規則 | 未啟 `unawaited_futures` / `cancel_subscriptions` / `close_sinks` → 上面兩項完全沒有機制兜底 |
| **`Duration` 字面量 vs 常數** | 字面量 99 處 vs 具名常數 48 處（約 2:1） | 常數類別（`AnimationDurations:40`、`ToastDurations:139`、`DebounceDurations:150`）都已存在，只是推廣不全 |
| **`debugPrint(` 繞過 AppLogger** | 3 處（另 3 處是 logger 內部實作） | `play_history_page.dart:264`、`youtube_stream_test_page.dart:826`、`create_playlist_dialog.dart:386` |
| **stack trace 變數命名** | 三種並存 | `stack`（主流）/ `stackTrace` / `st` |
| **對話框寬度未走 Breakpoints** | 3 處各自硬編 | `color_palette_button.dart:178`(320)、`lyrics_style_dialog.dart:167`(400)、`account_management_page.dart:269`(520) |

---

## 3. 問題清單 P0–P3

### P0 — 會讓 CI 紅燈或誤導 agent 產生錯誤修改

| # | 問題 | 證據 | 成本 | 風險 | 可逆 |
|---|---|---|---|---|---|
| **P0-1** | `test/performance/` 的 12 條 wall-clock 斷言在 CI 規格的機器上隨時會失敗。**4/4 負載回合必失敗**；乾淨 32 核機器上「500 searches」餘裕只有 1.48x | §1.3；`list_scrolling_benchmark_test.dart:361` 等 12 處 | S | 低 | 完全 |
| **P0-2** | `flutter test` 對 Bilibili 生產 API 發真實請求且前三個請求無 try/catch | §1.5；`test/demo/bilibili_info_test.dart:14,24,40`；三次實測回應 | S | 低 | 完全 |
| **P0-3** | `AGENTS.md:149` 的 `playlistProvider` 不存在，實際是 `playlistListProvider` | `rg` 零命中 vs `playlist_provider.dart:201` | S | 無 | 完全 |
| **P0-4** | 21 個 `*_phaseN_test.dart` + 3 個程式碼註釋引用已刪除的計劃文檔，現存文檔零解釋 | §2.5 | M | 低 | 完全 |

### P1 — 系統性正確性/可維護性風險

| # | 問題 | 證據 | 成本 | 風險 | 可逆 |
|---|---|---|---|---|---|
| **P1-1** | 6 個子樹 `AGENTS.md`（1,135 行）不享有 harness 保證的自動載入，全靠模型自願遵循路由表 | §2.1；官方文檔逐字 + 本 session 實證 | M | 中 | 完全 |
| **P1-2** | `services/` ↔ `providers/` 邊界已失效：6 檔 14 處反向依賴、29 個 provider 住 `services/`、`providers/` 有 8,636 行含 413 行 Isolate 掃描 | §2.4 | M | 中 | 高 |
| **P1-3** | 37 處空 catch 靜默吞例外，且 `analysis_options.yaml` 無 lint 兜底 | §2.8 | S–M | 中 | 完全 |
| **P1-4** | Isar 上游停擺 14 個月，pub.dev 無任何警示標記；35 個檔依賴它做持久化 | §2.7；issue #44 | 換 `isar_community`：**資料遷移為零（§1.7a 實測）**，但會被迫連帶升級 slang 3.32→4.19（§1.7b）→ 綜合 M；換 Drift：L | 高 | 中 |
| **P1-11** | 同一份「找 Isar 原生庫路徑」的 test helper 被**複製 40 次**（兩種變體），且全部硬編 `isar.dll`。任何 Isar 套件變動都要改 40 個檔 | §1.7c（`rg -l "isar_flutter_libs" test/` = 40） | S（抽成 1 個共用 helper） | 低 | 完全 |
| **P1-12** | slang 若升到 4.x，`main.dart:137` 的 `LocaleSettings.useDeviceLocale()` 會變成未 await 的 Future，`runApp()` 可能早於 locale 套用；而 `analysis_options.yaml` 沒開 `unawaited_futures`，`flutter analyze` 完全沉默 | §1.7d（實測 `No issues found!`） | S（改 `useDeviceLocaleSync()`） | 中 | 完全 |
| **P1-5** | `analysis_options.yaml:14` 排除 `test/**`，46k 行測試碼零靜態分析。**實測繞過後有 146 條**，其中 5 條是測試替身與正式介面漂移（1 條 `unrelated_type_equality_checks` 經實跑證明是誤報，見 §1.1b） | §1.1b | **S** —— 扣掉單一 demo 檔的 95 條 `avoid_print`，只剩約 50 條要清 | 低 | 完全 |
| **P1-6** | 11 條規則在 2–3 個 `AGENTS.md` 完整重述，違反根檔 `:66-69` 自己定的規矩 | §2.1 | M | 低 | 完全 |
| **P1-7** | CI 的兩份 workflow 完全沒有 `timeout-minutes`（沿用 360 分鐘上限），且沒有任何失敗重跑機制 | §1.3b | S | 低 | 完全 |
| **P1-8** | 46/184（25%）測試檔用 `readAsStringSync()` 對 `lib/` 原始碼做字串斷言 —— 重構改寫法就會紅，即使行為正確。這是目錄重構的最大改動面 | §2.6 | —（是成本因子，不是缺陷） | 中 | — |
| **P1-9** | `main.dart:91,93` 在 `LocaleSettings.useDeviceLocale()`（`:137`）之前 46 行讀 `t.` -> 通知頻道名稱/說明**永遠是英文**，與裝置語系無關。已在模擬器上以 per-app locale 切換確認 | §1.6a（實機 + slang 原始碼逐層追證） | **S**（把 `useDeviceLocale()` 上移到 `AudioService.init()` 之前） | 低 | 完全 |
| **P1-10** | Gradle 8.14.0 / AGP 8.11.1 / Kotlin 2.2.20 三項都被 Flutter 3.47.1 印出 "will soon be dropped" 警告；先前依賴盤點只看 `pubspec.yaml`，未涵蓋這層 | §2.7（`flutter run` 實跑輸出） | M | 中 | 高 |

### P2 — 準確性與文檔債

| # | 問題 | 證據 | 成本 | 風險 | 可逆 |
|---|---|---|---|---|---|
| **P2-1** | 12 條 AGENTS.md 斷言部分不符（指錯位置 / 誇大範圍 / 誇大強制力 / 指向空殼） | §2.1 表格 | M | 低 | 完全 |
| **P2-2** | `docs/agents/*` 宣稱 docs/ 是繁體，實測 7 份中 4 份（字數最多的 4 份）是簡體或混用 | §2.3 | S（改文檔）/ L（真統一） | 低 | 完全 |
| **P2-3** | `build-guide.md` ↔ `build-and-release.md` 逐字重複 100–110 行 | §2.3 | S | 低 | 完全 |
| **P2-4** | `docs/adr/` 是本機空目錄，clone 後不存在，但被兩份文檔當既有體系引用 | §2.2 | S | 無 | 完全 |
| **P2-5** | `docs/README.md:39` 點名不存在的 `/qa` skill | §2.2 | S | 無 | 完全 |
| **P2-6** | `refactoring-log.md` 內容停在 2026-03、編號錯亂、已有失效路徑 | §2.3 | S | 低 | 完全 |
| **P2-7** | 7 個宣告但零使用的依賴（`riverpod_annotation` 尤其誤導：無 generator、零 `@riverpod`） | §2.7 | S | 低 | 完全 |
| **P2-8** | `docs/build-and-release.md:293-295` 說「等本項目完成 Windows 插件補丁」，補丁已於 2026-08-22（`30dd55ed`）完成 | 子代理核對 | S | 無 | 完全 |
| **P2-9** | `AGENTS.md` Key Paths 漏列 9 個 `lib/services/` 子目錄，其中 2 個被其他 AGENTS.md 直接引用 | §2.1 | S | 低 | 完全 |
| **P2-10** | CI 從未在 Windows 或 Android 上跑過 `flutter test`（兩個 build job 只做 build），Windows 特有行為完全靠人工 on-device 驗證 | §1.3b | M（加 windows test job）| 低 | 完全 |
| **P2-11** | `test/demo/` 其餘 5 檔、`test/widget_test.dart` 佔位、`lyrics_window_layout_test.dart` 重複 —— 8 檔 2,038 行過時/重複資產 | §2.6 | S | 低 | 完全 |

### P3 — 打磨

| # | 問題 | 成本 |
|---|---|---|
| P3-1 | 7 個單檔 `services/` 子目錄，目錄名零資訊 | S（隨 P1-2 一起做） |
| P3-2 | `Duration` 字面量 99 vs 常數 48 | M |
| P3-3 | stack trace 變數三種命名並存 | S |
| P3-4 | 3 處 `debugPrint(` 繞過 `AppLogger` | S |
| P3-5 | 3 個對話框硬編寬度門檻未走 `Breakpoints` | S |
| P3-6 | **8 張截圖全是 Windows 桌面版、零 Android 畫面**，README 卻把 7 張排成 2 欄表格易讀成手機截圖；`home_desktop.png` 與 `home-page.png` 拍同一畫面且相差 3 個月（§1.6b）。**「過時」一項經實跑比對後不成立**（§1.6c） | S |
| P3-7 | `README.md` 沒寫最低 Android / Windows 版本需求 | S |
| P3-8 | `slang` 是 transitive 依賴但 `AGENTS.md:81` 把 `dart run slang` 當常備指令 | S |

---

## 4. 成熟做法對照

### 4.1 Agent 指令：Claude Code 官方機制

來源：https://code.claude.com/docs/en/memory（2026-08 現行版，逐字核對過）

| 官方做法 | FMP 現況 | 差距 |
|---|---|---|
| `CLAUDE.md` import `AGENTS.md` 是官方推薦的跨 agent 共用寫法，Windows 上明確建議用 import 而非 symlink | 完全符合，就是官方範例的最簡版 | 無 |
| 單檔目標 **< 200 行** | 根 185 ✅；`lib/ui/AGENTS.md` 305、`lib/services/AGENTS.md` 223、`lib/data/sources/AGENTS.md` 222 ❌ | 3 個子樹檔超標 |
| 大檔案的官方解法是 **`.claude/rules/` + `paths:` frontmatter**（"load only when Claude works with matching files"，harness 保證） | 沒有 `.claude/rules/`；用 `AGENTS.md` + 路由表（無保證） | **這是最大的機制差距** |
| 「規則衝突時 Claude 可能任意選一個」→ 官方明說要定期檢查移除重複與矛盾 | 11 條規則重複 2–3 次 | 直接對應 P1-6 |
| `InstructionsLoaded` hook 可 log 實際載入哪些指令檔 | 未用 | 可用來驗證 P1-1 的假設 |
| `/doctor` 會針對 checked-in CLAUDE.md 提出精簡建議（砍掉可從程式碼推導的目錄結構、依賴清單、架構總覽，保留 pitfalls / rationale / 與工具預設不同的慣例） | 未用 | 正好對應本報告發現的散文膨脹 |

### 4.2 目錄結構：Flutter 官方 + 三個大型專案 + 一個同類產品

#### Flutter 官方 architecture guide

https://docs.flutter.dev/app-architecture/case-study（逐字）：

> "There are two popular means of organizing code: 1. **By feature** ... 2. **By type** ..."
> "The architecture recommended in this guide lends itself to **a combination of the two**. Data layer objects (repositories and services) **aren't tied to a single feature**, while UI layer objects (views and view models) **are**."

`compass_app` 官方目錄樹（逐字引自 case-study 頁）：

```
lib/
  ui/
    core/
      ui/           <shared_widgets>
      themes/
    <feature_name>/
      view_models/
      widgets/
  domain/
    models/
  data/
    repositories/
    services/
    model/
  config/  utils/  routing/  main.dart
```

https://docs.flutter.dev/app-architecture/guide（逐字）：

> **Service**："Services are in the lowest layer... They wrap API endpoints and expose asynchronous response objects... They're only used to isolate data-loading, and they **hold no state**. Your app should have **one service class per data source**."
> **Repository**："Repository classes are the **source of truth** for your model data."

https://docs.flutter.dev/app-architecture/recommendations（逐字）：

> Use a domain layer — **Conditional**："A domain layer is only needed if your application has exceeding complex logic that crowds your ViewModels... **in most apps they add unnecessary overhead**."
> "you should put your shared widgets in a directory called **`ui/core/`**, rather than a directory called `/widgets`."

**【推論 — 關鍵】** **FMP 的 `lib/services/` 不是官方定義的 Service。** 官方的 Service = 包 API endpoint、無狀態、一個資料源一個 —— 那在 FMP 裡是 `lib/data/sources/`。FMP 的 `lib/services/`（84 檔 30,948 行）在官方架構裡沒有對應層。而 `lib/providers/` 實質是官方的 ViewModel 層，只是被抽出 `ui/` 之外。**命名衝突是所有後續混亂的起點。**

#### AppFlowy（flutter_bloc 9.x，60 萬行桌面應用）

https://github.com/AppFlowy-IO/AppFlowy/tree/main/frontend/appflowy_flutter/lib

頂層：`ai/ core/ date/ env/ features/ flutter/ mobile/ plugins/ shared/ startup/ user/ util/ workspace/`

- `features/`（新代碼落點）：每個 feature 固定三層 `features/<name>/{data, logic, presentation}`，例如 `features/share_tab/`
- `plugins/`（可插拔內容型態）：`document/ database/ ai_chat/ trash/ ...`，內部 `application/`（bloc）+ `presentation/`
- `workspace/`（舊主殼，layer-first 殘留）：只有 `application/` + `presentation/`

**做法要點**：AppFlowy 正在**從** layer-first 的 `workspace/{application,presentation}` **遷往** feature-first 的 `features/<name>/{data,logic,presentation}`。遷移方向與本報告的建議一致。

#### Immich mobile（hooks_riverpod 2.6，正在做大型目錄重構）

https://github.com/immich-app/immich/tree/main/mobile/lib

新舊並存：新 `data/ domain/ infrastructure/ presentation/ providers/`；舊 `pages/ services/ repositories/ widgets/ models/ ...`

- `domain/` + `infrastructure/` 由 **PR #16199**（2025-02-19，"refactor(mobile): split store into repo and service"）引入。
- `infrastructure/README.md` 現在寫著 repositories 正「one entity at a time」遷往 `lib/data/`。
- **`domain/README.md` 的鐵律（逐字）**："This layer should **never depend on anything from the presentation layer or from the infrastructure layer**."
- **Riverpod provider 是集中的**："Services are exposed through Riverpod providers in the **root `providers` directory**." —— 但 Immich 的 `providers/*.provider.dart` 是十幾到數十行的薄 DI wiring，邏輯全在 `domain/services/`。
- （順帶：Immich 已從 Isar 換成 Drift，`mobile/pubspec.yaml` 只剩 `drift: ^2.34.0`。）

**與 FMP 的直接對照**：Immich 的架構「集中 providers + 邏輯放 domain」正是 FMP 現在宣稱在做的事。**但 FMP 已經證明這條規則在本 codebase 守不住** —— `providers/` 8,636 行、含 413 行 Isolate 掃描、62 行零 Riverpod 的 debounce 類。Immich 靠明文 README 鐵律 + 大團隊 review 維持；FMP 是單人 + AI agent。

#### Very Good Ventures（`very_good create flutter_app`）

https://github.com/VeryGoodOpenSource/very_good_templates/tree/main/very_good_core

```
lib/
  app/{app.dart, view/}
  bootstrap.dart
  counter/                <- feature
    counter.dart          <- barrel
    cubit/counter_cubit.dart
    view/counter_page.dart
  l10n/arb/*.arb + l10n.dart
  main_{development,production,staging}.dart
```

**做法要點**：feature 目錄 = `cubit/`（狀態）+ `view/`（畫面）+ 同名 barrel；**`l10n/` 是與 feature 平行的頂層目錄，不隨 feature 拆**（對應 FMP 的 `i18n/` 應維持頂層）。Flutter 官方 recommendations 頁把它列為推薦資源。

#### 同類產品：Namida（音樂播放器，6.3k stars，2026-08-27 仍活躍）

https://github.com/namidaco/namida/tree/main/lib（367 個 `.dart`，與 FMP 311 個同級；同為 Android + Windows，同有 SMTC / 歌詞 / 佇列 / 下載 / 備份）

```
base/        13   跨頁面共用 mixin/抽象基底
class/       31   純資料型別
controller/ 133   全部業務邏輯與狀態，扁平單層
core/        12   constants/enums/extensions/themes/translations
packages/    17   自抽的可重用 widget
ui/          76   dialogs/ pages/ widgets/
youtube/     83   YouTube 這一源自成一個 feature：class/ controller/ functions/ pages/ widgets/
```

三點對 FMP 有用的差異：

1. **Namida 沒有 `services/` + `providers/` 雙層切分。** 邏輯與狀態合併在單一 `controller/`，一個子系統一個 `*_controller.dart`。FMP 把同一件事切兩處是 Namida 沒有的成本。
2. **Namida 把「一個資料源」升格為 feature 目錄**（`lib/youtube/` 83 檔自帶 `class/ controller/ pages/ widgets/`）。FMP 的三個源橫跨 `data/sources/`、`services/account/`、`services/lyrics/` 至少三處。
3. **Namida 的 `controller/` 已達 133 檔扁平單層**，開始出現 `settings.equalizer.dart` / `settings.player.dart` 這種用檔名點號模擬子目錄的徵兆 —— 這是單一巨型 layer 目錄的規模上限警訊。**FMP 不應把 `services/` 推到那裡**（目前 84 檔）。

### 4.3 效能測試：業界怎麼處理 wall-clock 斷言

**【事實】Flutter 官方 cookbook 的 benchmark 做法**（一手引用，來源
`https://docs.flutter.dev/cookbook/testing/integration/profiling`，對應 repo 路徑
`flutter/website/sites/docs/src/content/cookbook/testing/integration/profiling.md`）。

官方逐字說明為何一定要 profile mode：

> "The `--profile` option means to compile the app for the 'profile mode' rather
> than the 'debug mode', so that the benchmark result is closer to what will be
> experienced by end users."
>
> （原文的 'profile mode' / 'debug mode' 在來源頁面是雙引號，此處改單引號以免與外層
> 引號混淆。）

官方的執行方式**不在 `flutter test` 裡**，而是獨立的 driver：

```console
flutter drive \
  --driver=test_driver/perf_driver.dart \
  --target=integration_test/scrolling_test.dart \
  --profile
```

測量手段是 `binding.traceAction()` 包住待測操作、產出 timeline，再由
`TimelineSummary.summarize()` 匯出 JSON。官方記錄的指標**全是逐幀時間，不是單一操作
的總耗時**：

```json
{
  "average_frame_build_time_millis": 4.2592592592592595,
  "worst_frame_build_time_millis": 21.0,
  "missed_frame_build_budget_count": 2,
  "average_frame_rasterizer_time_millis": 5.518518518518518,
  "worst_frame_rasterizer_time_millis": 51.0,
  "missed_frame_rasterizer_budget_count": 10,
  "frame_count": 54
}
```

**【事實】Flutter 官方把「變異度」當成一等公民指標。** 官方部落格
`flutter/website/sites/www/content/blog/performance-testing-on-the-web/index.md`
的 benchmark 輸出裡，除了 `average` 之外還並列 `outlierAverage`、`outlierRatio`、
`noise`（例如 `"metric": "drawFrameDuration.noise", "value": 0.4512335390240227`）
—— 也就是說官方預期單次測量本來就會抖動，用**噪音比例**描述，而不是拿單次值去比一個
絕對門檻。

**【推論】三點對照下來，FMP `test/performance/` 的做法與官方實踐全部相反：**

| 面向 | Flutter 官方 | FMP `test/performance/` |
|---|---|---|
| 編譯模式 | profile mode（官方明言 debug 不代表使用者體驗） | **debug mode**（`flutter test` 唯一選項） |
| 執行載體 | `flutter drive` + 真實裝置 | **host Dart VM**，與其他 177 個測試檔搶同一台 runner |
| 指標 | 逐幀 build / rasterizer 時間 + 噪音比例 | **單次操作的 `Stopwatch` 絕對毫秒** |
| 判準 | 對照 timeline 摘要 | `expect(elapsed, lessThan(N))` 硬門檻 |

這正是 §1.3 實測到 4/4 必失敗的結構性原因：官方連 debug/profile 的差異都認為足以
使結果失真，FMP 卻在 debug 模式的共用 runner 上斷言絕對毫秒，且最緊的一條只有
1.48x 餘裕。

---

## 5. 建議方案

### 5.1 Agent 指令體系：目標結構與行數預算

#### 推薦：**維持 `AGENTS.md` 為單一事實來源，額外加一層薄的 `.claude/rules/` 路由**

```
CLAUDE.md                       1 行    @AGENTS.md                      （不動）
AGENTS.md                    ≤ 150 行   只留跨子系統的硬邊界與入口路由
.claude/rules/                          新增：6 個薄檔，各 5–10 行
  data.md                               paths: lib/data/**            → "read lib/data/AGENTS.md"
  sources.md                            paths: lib/data/sources/**    → "read lib/data/sources/AGENTS.md"
  providers.md                          paths: lib/providers/**       → ...
  services.md                           paths: lib/services/**        → ...
  audio.md                              paths: lib/services/audio/**  → ...
  ui.md                                 paths: lib/ui/**              → ...
lib/**/AGENTS.md             ≤ 200 行/檔  內容不變，仍是跨 agent 可讀的事實來源
```

**為何是這個方案而不是把內容搬進 `.claude/rules/`**：

- `AGENTS.md` 是跨工具標準（Codex / Cursor / Copilot 都讀），`.claude/rules/` 是 Claude Code 專屬。把 1,135 行搬進 `.claude/rules/` 等於放棄跨 agent 可攜性。
- 薄路由檔（每檔 5–10 行）只做一件事：把官方保證的 path-scoped 載入機制，接到現有的 `AGENTS.md` 上。內容零重複。
- 官方明說 path-scoped rule 「trigger when Claude reads files matching the pattern」—— 這正好把 P1-1 的「自願遵循」升級成「harness 觸發」。

**成本 S。風險低。完全可逆。**

#### 行數預算

| 檔案 | 現況 | 目標 | 怎麼縮 |
|---|---:|---:|---|
| `AGENTS.md` | 185 | **≤ 150** | 移除 11 條重複規則中在根檔的那份（改成單行指標）；Key Paths 表可從程式碼推導，官方 `/doctor` 明說這類內容該砍 |
| `lib/data/AGENTS.md` | 94 | 94 | 已達標 |
| `lib/providers/AGENTS.md` | 83 | 83 | 已達標 |
| `lib/services/audio/AGENTS.md` | 208 | **≤ 200** | 修 `audio_playback_types.dart` 描述；驗證章節改指根檔 |
| `lib/data/sources/AGENTS.md` | 222 | **≤ 200** | 134 行散文改條列；補完 12 個窄能力介面（改表格） |
| `lib/services/AGENTS.md` | 223 | **≤ 200** | 133 行散文改條列；Windows Sub-Windows 章節改成指向 `lib/ui/AGENTS.md` |
| `lib/ui/AGENTS.md` | 305 | **≤ 200** | 183 行散文改條列；Player Layout 章節（`:243-285`，43 行純散文）是最大宗 |
| `.claude/rules/*.md` ×6 | 0 | ~50 | 新增 |
| **合計** | 1,320 | **~1,130** | −14%，且每檔都在官方 200 行預算內 |

**文體原則（三條，可稽核）**：
1. **一條規則一行條列或一個表格列。** 散文只用來寫「為什麼」，不用來寫「是什麼」。
2. **每個具體斷言必須可被單一 `rg` 驗證。** 寫「常數在 `download_filenames.dart`」之前，先跑一次 `rg` 確認全部都在。
3. **禁止「is enforced by X」除非 X 真的在檢查那件事。** 這是本輪抓到的最危險錯誤類型 —— 它讓 agent 以為有安全網。

### 5.2 目標文檔地圖

| 文件 | 唯一職責 | 語言 | 維護觸發條件 | 處置 |
|---|---|---|---|---|
| `README.md` | 產品入口：下載、截圖、功能、隱私、免責、授權 | 繁體 | 使用者可見功能 / 截圖 / 下載入口 / 專案定位變更 | **保留**，補「系統需求」段 |
| `docs/README.md` | 文件索引與維護規則 | 繁體 | 新增/刪除/改職責的文件 | **保留**，修 `/qa`、修語言分工描述 |
| `AGENTS.md`（根） | agent 硬邊界 + 子樹路由 | 英文 | repo 級指令 / 架構地圖變更 | **保留**，縮到 ≤150 行 |
| `lib/**/AGENTS.md` ×6 | 各子樹的可驗證規則 | 英文 | 該子樹的行為 / 契約變更 | **保留**，各縮到 ≤200 行 |
| `.claude/rules/*.md` ×6 | 把 path-scoped 載入接到 AGENTS.md | 英文 | 子樹目錄結構變更 | **新增** |
| `CONTEXT.md` | 5 個領域術語的 ubiquitous language | 英文術語 + 說明 | 出現新的、會被多處誤稱的領域概念 | **保留**，為 2 個無識別字錨點的術語補「對應實作」欄 |
| `docs/agents/*.md` ×3 | engineering skills 的專案設定 | 英文 | 換 issue tracker / 標籤詞彙 / domain 佈局 | **保留**，修語言宣稱 |
| `docs/adr/` | 架構決策記錄 | 繁體 | 做出有替代方案被否決的架構決策 | **決策點**（見 §7） |
| `docs/development.md` | 貢獻者 onboarding：技術棧 + 架構總覽 | **統一為繁體** | 架構分層 / 技術棧變更 | **保留但精簡**：刪「常用命令」（改連結）、刪重複的 Isar collection 表（改連結） |
| `docs/build-guide.md` | **本機**建置環境與排錯（唯一權威） | **統一為繁體** | 工具鏈 / 前置條件 / 排錯手法變更 | **保留**，吸收兩份重複的逐字指令 |
| `docs/build-and-release.md` | **CI/發版**治理（唯一權威） | **統一為繁體** | workflow / secrets / 產物命名 / 更新資產變更 | **保留**，重複段改成連結 + 差異點；修 `:293-295` |
| `docs/troubleshooting.md` | 已查證的良性 runtime 噪音 | 繁體 | 出現新的「看起來像 bug 但不是」的現象 | **保留原樣**（品質最高） |
| `docs/debugging-with-vm-service.md` | VM Service 運行期檢查手冊 | **統一為繁體** | Dart/Flutter 大版本升級後重驗實測結論 | **保留原長度**，不精簡 |
| `docs/history/refactoring-log.md` | 唯讀歷史封存 | 保持現狀（不值得改） | **不再更新** | **封存**：banner 加「內容截至 2026-03，之後不再記錄」；修 `:944` 失效路徑；把條目 27/28 摘進對應 AGENTS.md |
| `docs/review/*.md` | 一次性審查報告 | 繁體 | — | **決策點**（見 §7）：前兩代都被刪，但程式碼還在引用 |

**新增一條維護規則**（寫進 `docs/README.md`）：

> 程式碼註釋、測試檔名、commit message **不得引用 `docs/review/` 下的文件**。審查報告是一次性產物，引用它等於製造必然的懸空引用。要在程式碼裡留鉤子，就把結論寫進對應的 `AGENTS.md` 並引用那裡。

### 5.3 目錄結構：`core/` + `data/` + `features/` + `ui/`

#### 推薦方案：取消 `services/` 與 `providers/` 兩個頂層目錄，合併為 `features/`

```
lib/
├── main.dart
├── core/                    # 無狀態、零 Riverpod、任何層皆可 import
│   ├── constants/  extensions/  utils/  services/
│   ├── media/               #   ← services/media/media_handoff.dart（純模組）
│   └── network/             #   ← services/network/ + core/utils/http_client_factory.dart
│
├── data/                    # 外部與持久化資料的唯一入口（type-first，官方明示不隨 feature 拆）
│   ├── models/  repositories/  sources/
│   └── database/            #   ← providers/database/database_provider.dart
│                            #     + services/database/data_integrity_service.dart
│
├── features/                # 一個使用者可見能力的全部業務邏輯與 Riverpod 狀態
│   ├── audio/  account/  download/  library/  lyrics/  search/
│   ├── explore/             #   ← services/cache/ + services/refresh/ + providers/search/{popular,refresh}
│   ├── radio/  backup/  update/  settings/  system/
│
├── ui/                      # 畫面。不含業務決策，只讀 features/*_providers.dart
│   ├── core/                #   ← 跨 feature 共用 widget + theme + layout（官方命名）
│   ├── home/ explore/ search/ library/ player/ queue/ lyrics/ radio/ history/ settings/ debug/
│   ├── windows/  router.dart  app_shell.dart
│
└── i18n/                    # 與 features/ 平行（比照 very_good_core 的 l10n/）
```

依賴方向：`ui/` → `features/` → `data/` → `core/`，單向。

#### 為什麼是這個 —— 一條可 grep 的機械規則

現行規則「`providers/` 只放 wiring、邏輯放 `services/`」是**主觀判斷，無法稽核，已經漂移失效**。替代規則：

> 在 `lib/features/` 底下，只有 `*_providers.dart` 允許 import `flutter_riverpod`。

稽核一行：

```bash
rg -l flutter_riverpod lib/features | rg -v '_providers\.dart$'   # 必須為空
```

這條規則同時修掉現存兩個病（29 個 provider 住 `services/`、8,636 行邏輯住 `providers/`），而且能寫進 CI 與 `AGENTS.md` 讓 agent 自檢。**單靠散文規則，FMP 已經失敗過一次。**

**副作用**：6 檔 14 處反向依賴中，`download_path_sync_service → download_scanner`、`auto_refresh_service → refresh_provider`、`radio_controller → account_provider`、`backup_service → database_provider` 合併後全部變成同目錄內或對 `data/` 的合法向下依賴。剩下 `audio → lyrics/download/library` 是**真實的跨功能耦合**，合併後至少誠實可見。

#### 成本 M，可逆性高

- 移動 124 檔（`services/` 84 + `providers/` 40）；需改 import 的檔案約 80 個 + `test/`。
- **零行為變更。** Dart 無動態 import，`flutter analyze` 是完整驗證。
- **前置機械步驟**：先把相對 import 統一為 `package:fmp/...`（現況混用：`audio_provider.dart:6` 是 `../../core/logger.dart`、`:34` 是 `package:fmp/i18n/strings.g.dart`）。統一後移動檔案不必重算 `../../` 深度，可獨立 commit、獨立驗證。
- 純 rename/move，無持久化格式、無對外 API、無 migration 變更，`git revert` 單一 commit 即可回退。

#### 替代方案

| 方案 | 成本 | 取捨 |
|---|---|---|
| **A. 最小手術：只把 `providers/` 併進 `services/`，維持 layer-first** | **S** | **優**：一個 PR 收工，消滅七對重複目錄與全部 6 處反向依賴，不動 `ui/`。**劣**：得到 124 檔的 `services/`（Namida 的 133 檔扁平 `controller/` 已在失控邊緣），且 `services` 這名字仍與官方定義衝突。**實質上是推薦方案的合法子集**，之後可無痛續做 |
| **B. 全面 feature-first（連 `data/` 一起拆）** | **L** | **不建議**。官方 case-study 明確反對；`BilibiliSource` 同時被 audio/download/search/library/radio 五處使用，拆了會製造假歸屬與循環依賴 |
| **C. Immich 路線：保留兩層，強制 `providers/` 只放 wiring** | S–M | **可行但脆弱**。Immich 靠明文鐵律 + 大團隊 review；FMP 現況就是這條規則沒守住的結果。除非同時加 CI 檢查（`providers/` 單檔行數上限、禁止定義非 provider 的 top-level class），否則會二次漂移。且保留「一個功能開兩個目錄」的日常成本 |
| **D. 不動** | 0 | 需接受：每加一個功能要同時建兩個目錄、反向依賴繼續累積、`ui/` 41 檔同時 import 兩層不會改善、7 個單檔目錄持續存在 |

### 5.4 測試：金字塔與 CI 時間預算

盤點數據見 §2.6。此處只給處置。

#### 立即處置（P0）

| 對象 | 處置 | 理由 |
|---|---|---|
| `test/performance/`（2 檔 550 行 12 條 wall-clock 斷言） | **移出預設套件**：改名為 `*_benchmark.dart`（不符 `*_test.dart`），或移到 `benchmark/` 目錄，需要時手動跑 | **4/4 負載回合必失敗**；乾淨機器餘裕只有 1.48x；斷言的是「這台機器多快」不是「這段程式碼對不對」 |
| `test/demo/bilibili_info_test.dart` | **改名為 `bilibili_info_demo.dart`**（與同目錄其他 5 個一致） | 它本來就是 demo 腳本，只是檔名讓 `flutter test` 誤收；改名一行解決，且與既有慣例一致 |

這兩項合計改 3 個檔名，就消除了 CI 上**唯二的結構性紅燈來源**。

#### 其次（P2 等級的清理）

| 對象 | 處置 |
|---|---|
| `test/demo/` 其餘 5 檔 | 刪除。用途已被正式實作 + mock 測試取代（`bilibili_live_client_test.dart`、`qqmusic_source_test.dart`、`netease_source_test.dart`）；`lyrics_matching_demo.dart` 內嵌的精簡邏輯已與 `lib/` 正式碼分岔 |
| `test/widget_test.dart`（11 行 `expect(true, isTrue)`） | 刪除。Flutter 樣板佔位，`test/ui/` 已有 47 個真的 widget 測試 |
| `test/services/lyrics/lyrics_window_layout_test.dart`（10 行） | 併入 `lyrics_window_style_test.dart` |
| `ci.yml` / `release.yml` 的 test step | 加 `timeout-minutes: 10` |

#### 目標金字塔

| 層 | 目前 | 目標 | 備註 |
|---|---|---|---|
| 純單元（models / utils / repositories / sources 解析） | 大宗 | 維持 | 快、穩、值得 |
| widget 測試（`test/ui/` 47 檔 6,969 行） | 適中 | 維持 | |
| 靜態規則測試（`test/ui/static_rules/` 2 檔 897 行 25 條） | — | **維持但正名** | 這是 lint，不是測試。它們很有價值（22 條 UI 一致性規則 + ListTile leading 規則），但應該在文檔裡誠實說明它們檢查什麼 —— 見 P2-1 的「誇大強制力」 |
| workflow 字串測試（`test/workflows/` 1 檔 31 行 3 條） | — | **維持** | 3 條都是對過去 CI bug 的迴歸防護（`commits<<EOF` heredoc 注入、changelog delimiter 換行、versionCode 公式）。極度實作耦合，但守的是真實踩過的坑 |
| benchmark | 混在套件裡 | **移出** | 見上 |
| 網路整合 | 混在套件裡（1 檔） | **移出** | 見上 |

#### CI 時間預算

**【事實】** 目前本機 1m38s–1m59s / 1241 測試。CI（`ubuntu-latest`，4 vCPU）會更慢但仍在可接受範圍。

**【建議】** 把預算定在 **`flutter test` ≤ 3 分鐘（CI 上）**，並在 `ci.yml` 的 test step 加 `timeout-minutes: 10`（目前兩個 workflow 的**任何 step 都沒有 timeout**，一個掛住的網路請求會吃滿 GitHub 的 6 小時 job 上限）。成本 S。

---

## 6. 重寫 vs 漸進重構

逐模組結論。

| 模組 | 建議 | 理由 |
|---|---|---|
| **Agent 指令體系**（`AGENTS.md` ×7） | **漸進重構** | 83% 的斷言正確，錯的 13 條都是點狀的（指錯位置、誇大範圍），不是結構性錯誤。內容本身是這個 repo 最有價值的資產之一 —— 它記錄了大量無法從程式碼推導的 rationale（buffer profile 數值、YouTube 縮圖 4:3 黑邊、AXTree 假 API）。重寫會丟掉這些。做法：逐檔修 13 條 + 去重 11 條 + 散文改條列 + 加 `.claude/rules/` 路由 |
| **`docs/`（人類文檔）** | **漸進重構 + 一份封存** | `README` / `docs/README` / `troubleshooting` / `debugging-with-vm-service` 品質好，不動。`development` / `build-guide` / `build-and-release` 三份的問題是重複與語言不一致，是編輯工作不是重寫。`refactoring-log.md` 封存 |
| **`lib/` 目錄結構** | **漸進重構（tracer bullet）** | 見 §5.3。**絕不重寫** —— 94k 行、1347 commits、大量隱性契約（下載檔名、Isar schema、auth header 邊界）。分階段：Phase 0 統一 import → Phase 1 只搬 `download`（13 檔，驗證 pattern 與 lint 規則）→ Phase 2–4 逐 feature 搬，每 1–2 個 feature 一個 commit → Phase 5 拆單檔目錄 + 更新 AGENTS.md。**每個 commit 結束 repo 都可跑可測** |
| **測試資產** | **漸進 + 3 個檔名改動** | 三個檔名改動（2 個 benchmark + 1 個 demo）就解決了 CI 上唯二的結構性紅燈。逐檔分類結果：**78.3% 是真正的行為測試、0 檔無法理解**，只有 8 檔（4.4%）過時或重複。1241 條在乾淨環境 3/3 全綠。這是一個健康的套件，不需要重寫 |
| **依賴** | **漸進，但 Isar 要單獨排期** | 7 個死依賴移除是 S。Isar 是唯一需要真正決策的（見 §7）。`riverpod` / `go_router` / `slang` 的 major 升級各自獨立排期，不要跟目錄重構混在一起 |

**總結：沒有任何一個模組建議重寫。** 這個 repo 的問題形狀是「邊界畫錯位置」與「文檔比程式碼腐爛得快」，兩者都是漸進重構能解的。

---

## 7. 需要你決策的點

先列出，不在本輪追問。

1. **`docs/adr/` 要不要真的用？**
   - (a) 開始寫 ADR：補一個 `docs/adr/0001-*.md`（現成題材：Isar 凍結決策、`services/`+`providers/` 分層、Windows 音訊後端選型）讓目錄進版控。
   - (b) 放棄 ADR：從 `AGENTS.md:35-36` 與 `docs/agents/domain.md` 移除引用，刪掉本機空目錄。
   - 現況（引用一個 clone 後不存在的目錄）是最差的一種。

2. **`docs/review/` 的定位。** 前兩代（2026-04 八份、2026-07 八份）都在一個月內被刪，但 `*_phaseN_test.dart` 與 3 個程式碼註釋還在引用它們。三選一：
   - (a) 審查報告不進 repo（寫到 scratchpad / gist），程式碼永遠不引用。
   - (b) 進 repo 且**永久保留**在 `docs/review/`，程式碼可以引用。
   - (c) 進 repo 但明文禁止程式碼引用，刪除時一併清理引用。

3. **繁簡：統一還是誠實描述？**
   - (a) 統一為繁體：4 份文檔（`development` / `build-guide` / `debugging-with-vm-service` / `build-and-release`）共約 6,000 CJK 字，成本 M。`lib/` 註釋 64k CJK 字不動（或另議）。
   - (b) 只改文檔對自己的描述：`docs/agents/*` 與 `docs/README.md:37` 誠實寫「2026-07 之後新寫的用繁體，既有簡體文檔不回頭改」，成本 S。
   - 注意 `slang.yaml` 的 `base_locale: zh-CN` 是另一個層次的問題（app i18n 基準），不建議在文檔議題裡一起動。

4. **Isar：什麼時候動、動到哪？**（issue #44 已在追）
   - **前提已實測，不再是未知數**：既有 `.isar` 檔用 `isar_community` 3.3.2 開啟後
     11 個 collection、1,523 筆記錄逐項一致，檔案大小不變，**資料遷移成本為零**（§1.7a）。
   - (a) 現在換 `isar_community`。**但它會強制把 slang 3.32 升到 4.19**（§1.7b 的
     `build ^4` 依賴鏈，無法繞過），而 slang 4 會引入兩個 `flutter analyze` 看不見的
     問題（§1.7d）。若選這條，建議**拆成兩個獨立變更**：先升 slang 並穩定，再換 Isar。
   - (b) 等到 Android 16KB page size 真的擋住上架再說。
   - (c) 直接排 Drift 遷移（成本 L）。
   - 無論選哪個，`lib/data/AGENTS.md:12-22` 的凍結說明都需要更新 —— 它目前把「上游還在」當理由，而上游已停擺 14 個月。
   - 另外 §1.7c 的 40 份重複 test helper（P1-11）**與這個決策無關，應該先做掉** ——
     它現在是任何 Isar 變動的固定稅。

5. **目錄重構：做到哪一步？**（§5.3 的 A / B / C / D）
   - 我推薦：先做 Phase 0（統一 `package:fmp/` import）+ Phase 1（`download` 合併成 `features/download/`）+ 把那條可 grep 的 Riverpod 規則寫進 `AGENTS.md`。成本 S、完全可逆，能在真實 feature 上驗證整個方案，再決定要不要推完剩下六個。

6. **`analysis_options.yaml` 要不要收緊？**
   - 開 `unawaited_futures` + `cancel_subscriptions` + 移除 `exclude: test/**`：成本 M（需先清理未知數量的既有違規才能過 CI），但這是 P1-3 唯一的機制解。
   - 現況「靠紀律不靠機制」已經產生 37 處空 catch。

7. **7 個死依賴要不要移除？** 技術上是 S，但依 `AGENTS.md` 的規則，改 pubspec 算對外介面變更，需要你點頭。`intl` 需要先確認是否為 `flutter_localizations` 的版本解析所需。

---

## 8. Quick wins

按「改動最小 / 收益最大」排序。全部未動手。

| # | 動作 | 位置 | 成本 |
|---|---|---|---|
| 1 | `test/demo/bilibili_info_test.dart` → `bilibili_info_demo.dart` | 檔名 | 1 分鐘。**移除 CI 對 Bilibili 生產 API 的依賴** |
| 2 | `test/performance/*_test.dart` → `*_benchmark.dart` | 2 個檔名 | 1 分鐘。**移除 CI 上唯一可重現的 flaky 來源** |
| 3 | `AGENTS.md:149` `playlistProvider` → `playlistListProvider` | 1 行 | 1 分鐘 |
| 4 | `ci.yml` / `release.yml` 的 `Verify generated files are committed` → 改名 + 收窄成 `git diff --exit-code -- pubspec.yaml pubspec.lock` | `ci.yml:49-50`、`release.yml:198-199` | 5 分鐘（issue #38 的建議方案 1） |
| 5 | `docs/README.md:39` 移除 `/qa` | 1 個詞 | 1 分鐘 |
| 6 | `lib/services/AGENTS.md:221` `_FmpImageCacheManager` 路徑改為 `network_image_cache_service.dart`，參數名改為 `maxWidth`/`maxHeight` | 2 行 | 2 分鐘 |
| 7 | `lib/services/audio/AGENTS.md:80-82` 修正 `audio_playback_types.dart` 描述（6 行、只有 `enum PlayMode`） | 1 行 | 2 分鐘 |
| 8 | `lib/data/sources/AGENTS.md:122-125` 5 個介面 → 12 個（改表格） | ~10 行 | 10 分鐘 |
| 9 | `lib/ui/AGENTS.md:44-46` 刪掉「this is enforced by `ui_consistency_static_rule_test.dart`」或改成正確的描述 | 1 句 | 2 分鐘 |
| 10 | `lib/services/AGENTS.md:17-21` 註明只有 3 個檔名是常數，其餘硬編（`download_filenames.dart:5-6` 的原註釋已說明是刻意取捨） | 2 行 | 5 分鐘 |
| 11 | `docs/history/refactoring-log.md:944` `lib/ui/widgets/track_thumbnail.dart` → `lib/ui/widgets/images/track_thumbnail.dart` | 1 行 | 1 分鐘 |
| 12 | `docs/build-and-release.md:293-295` 更新 Windows runner 措辭（補丁已於 `30dd55ed` 完成） | 1 段 | 5 分鐘 |
| 13 | `ci.yml` 的 test step 加 `timeout-minutes: 10` | 1 行 | 1 分鐘 |
| 14 | `ci.yml:44` / `release.yml:141,193,239` 的 `flutter pub run build_runner` → `dart run build_runner`（與 `AGENTS.md:80` 一致） | 4 行 | 2 分鐘 |
| 15 | `lib/main.dart:107-109` 的 `MediaKit.ensureInitialized()` 包 try/catch（issue #37 的第二層防護，獨立於主修法） | 3 行 | 5 分鐘 |
| 16 | 3 個 `debugPrint(` 改用 `AppLogger` | `play_history_page.dart:264`、`youtube_stream_test_page.dart:826`、`create_playlist_dialog.dart:386` | 5 分鐘 |
| 17 | `docs/history/refactoring-log.md` banner 加「內容截至 2026-03，之後的重構不再記錄於此」 | 1 行 | 1 分鐘 |
| 18 | 刪 `test/widget_test.dart`（11 行 `expect(true, isTrue)` 樣板佔位） | 1 檔 | 1 分鐘 |
| 19 | 併 `test/services/lyrics/lyrics_window_layout_test.dart`（10 行）進 `lyrics_window_style_test.dart` | 2 檔 | 5 分鐘 |
| 20 | `release.yml` 的 test step（`:205`）也加 `--coverage` 或明確說明為何不加 | 1 行 | 2 分鐘 |
| 21 | ~~查 `radio_controller_phase2_import_test.dart:195` 那條 `unrelated_type_equality_checks`~~ —— **已查，是誤報，無需處理**（§1.1b）。若要消掉 lint 雜訊，可在該行加 `// ignore:` 並註明「泛型未綁定造成的誤報」 | 1 行 | 2 分鐘 |
| 22 | 清 `playback_request_session_test.dart:888,910` 與 `temporary_play_handler_test.dart:351,361,371` 的 5 個死 `@override`（測試替身已與正式介面漂移） | 2 檔 | 15 分鐘 |
| 23 | `test/demo/bilibili_live_api_lookup_demo.dart` 補 `// ignore_for_file: avoid_print`（與同目錄其他 5 檔一致）—— 或直接隨 P2-11 刪掉整個 demo 目錄，這 95 條就消失 | 1 行 | 1 分鐘 |
| 24 | `lib/services/storage_permission_service.dart` 是 `lib/services/` 根目錄唯一的散裝 `.dart`。`lib/providers/AGENTS.md:7-8` 與 `lib/ui/AGENTS.md:7-8` 都禁止這種放法，`lib/services/AGENTS.md` 沒有對應規則 —— 補規則或把它移進 `platform/` | 1 檔 | 5 分鐘 |
| 25 | `lib/main.dart:137` 的 `LocaleSettings.useDeviceLocale()` 上移到 `:88` 的 `AudioService.init()` 之前（兩者無先後依賴）。這就是 **P1-9** 的完整修法 | 移動 1 行 | 5 分鐘 |
| 26 | `lib/i18n/*/nav.i18n.json` 的 `"explore"` key 三個語系都有，但 `responsive_scaffold.dart` 的 6 個導航項沒用到 —— 刪 key 或說明保留原因 | 3 檔各 1 行 | 5 分鐘 |
| 27 | README `:40` 與 `:45` 的 `home_desktop.png`／`home-page.png` 是同一個畫面（桌面首頁），刪掉舊的那張（`home_desktop.png`，2026-02-13） | 1 檔 + 1 行 | 5 分鐘 |
| 28 | README 截圖區加一句說明「以下為 Windows 桌面版畫面」，避免 2 欄表格被誤讀成手機截圖（§1.6b） | 1 行 | 2 分鐘 |

> **原本列在此處的「通知頻道語系」額外發現已升級為 P1-9**，並在 §1.6a 完成實機驗證。
> 一併更正當時的推論：實際洩漏的**不是** base locale zh-CN，而是 **`en`** —— 因為
> slang 在 locale 未定時會走「只比對 countryCode」的分支，而 `en` 是 FMP 三個 locale
> 中唯一沒宣告 `countryCode` 的，`null == null` 成立便被選中，根本走不到 `?? baseLocale`。
> 另外「頻道名只在首次啟動寫入」的說法也不必要：Android 的
> `createNotificationChannel()` 本來就會更新既有頻道的名稱與描述，所以此 bug 每次啟動
> 都在重新寫入英文名，不是只影響首次安裝。

---

## 9. 三個 issue 的裁決

### #37 — runApp() 之前的任何例外都會變成靜默失敗

**裁決：✅ 保留（描述準確，建議的修法正確）** — 併入重構時一起做，或當獨立小修。

**【事實】逐條核對**：

| issue 的說法 | 核對結果 |
|---|---|
| 所有初始化在 `runZonedGuarded` 的 async body 裡，`runApp()` 在最後 | ✅ `main.dart:63` 開始，`:139` `runApp()`，`:146-148` zone handler 只記一行 log |
| `lib/main.dart:107` 的 `MediaKit.ensureInitialized()` 沒有 try/catch | ✅ `:107-109`，無 try/catch（`if` 在 107、呼叫在 108，行號差 1，不影響） |
| `_preloadThemeSettings()`、`AudioService.init()`、`_initializeWindowManager()` 都在這個區間內 | ⚠️ **部分不準**。三者確實都在區間內，但 `_preloadThemeSettings()`（`:189-201`）**自己有 try/catch 吞掉一切**（`:198 catch (_)`），不可能 throw。`AudioService.init()`（`:87`）與 `_initializeWindowManager()`（`:159`）/ `_initializeSmtc()`（`:152`）則確實裸奔 |
| 沒有 `runApp()` 就沒有第一帧、沒有視窗 | **未驗證** —— 這是 Flutter Windows embedder 的行為推論，我沒有實際跑一個會 throw 的 build 來確認 |

**補充（issue 未提，但同一區塊）**：`main.dart:50` 設了 `FlutterError.onError`，但沒有設 `PlatformDispatcher.instance.onError`；且 `:58` 的 `if (kDebugMode)` 讓 release 模式下框架層錯誤完全靜默。這與 issue 描述的是同一類問題，修的時候可以一起考慮。

**建議修法**：issue 的兩層方案（zone handler 知道 `runApp()` 跑過沒 + 個別初始化加 try/catch 降級）是對的。第二層可以先做（Quick win #15）。

### #38 — CI 的「Verify generated files are committed」名不副實

**裁決：✅ 保留（描述完全準確），建議照 issue 的方案 1 修** — 可直接做（Quick win #4）。

**【事實】逐條核對，全中**：

| issue 的說法 | 核對結果 |
|---|---|
| `ci.yml:49-50` 有這一步 | ✅ 行號完全一致 |
| `release.yml:198-199` 有這一步 | ✅ 行號完全一致 |
| `.gitignore:29` 是 `*.g.dart` | ✅ 行號完全一致 |
| `git ls-files \| grep -cE '\.g\.dart$'` → 0 | ✅ 實測 0 |
| `lib/i18n/*.g.dart` 被 ignore | ✅ `git status --porcelain --ignored=matching lib/i18n` 列出 `!! lib/i18n/en/strings.g.dart`、`!! lib/i18n/strings.g.dart` |
| 這一步只抓得到 `pubspec.lock` 被改動 | ✅ 推論正確 |

**補充**：`release.yml` 有 3 個 job 各自跑生成（`:141`、`:193`、`:239`），但只有 `:198-199` 那個 job 有這個檢查步驟 —— 進一步說明它不是一個真正的閘門。另外三處都用 `flutter pub run build_runner`，而 `AGENTS.md:80` 寫的是 `dart run build_runner`，順手一起統一（Quick win #14）。

### #43 — audio_controller_phase1_test 在完整測試套件負載下偶發失敗

**裁決：⚠️ 保留，但根因推測需要修正；建議把 issue 改寫成「測試生命週期洩漏」** — 併入重構。

**【事實】我做了什麼**：
- 乾淨環境跑完整套件 3 次 → **3/3 全綠**，1241 測試零失敗。
- 24 核 CPU 飽和（其中 2 次另外並行 `flutter analyze`）跑 4 次 → **4/4 失敗，但每次失敗的都是同樣 3 條 `test/performance/`，#43 那一條一次都沒紅**。
- 翻 CI 歷史，找到 **2026-07-27 `run 30280237603`** 一次真實的 CI 失敗。

**【事實】那次 CI 失敗的是同一個檔、同一個 group 的鄰居測試**：

```
❌ test/services/audio/audio_controller_phase1_test.dart:
   AudioController phase 1 regressions
     superseded playback-starting callback does not stop the newer request
```

issue #43 說的是 `superseded source error without next track does not stop newer request`（`:1237`）。兩條是同一個 group 裡的兄弟。

**【事實】CI log 給出了 issue 沒有的根因**：

```
Error: IsarError: Isar instance has already been closed
  #3 QueueRepository.save.<anonymous closure> (queue_repository.dart:30:39)
  #7 QueuePersistenceManager.persistQueue (queue_persistence_manager.dart:89:5)
  #8 QueueManager._persistQueue (queue_manager.dart:828:5)
  #9 QueueManager.playSingle (queue_manager.dart:402:5)
  #10 AudioController.playSingle (audio_provider.dart:704:26)
Bad state: Condition was not met after 50 event pumps  (_pumpUntil, :1775)
Bad state: Tried to use AudioController after `dispose` was called.
```

**【推論 — 這是對 issue 的實質修正】**

issue #43 的推測是：

> 「該測試用 `pumpEventQueue(times: N)` 等待非同步狀態收斂……圈數是寫死的……修法方向是把固定圈數換成等到目標狀態的條件式 helper」

但 CI 實際失敗的那條測試**已經在用條件式 helper**（`_pumpUntil`，`:1767-1776`），而且它仍然失敗了 —— 因為 `_pumpUntil` 自己也有 `maxPumps = 50` 的上限（`:1769`）。條件式等待並不能解決這個問題。

真正的失敗鏈是：

1. `AudioController.playSingle` → `QueueManager.playSingle`（`queue_manager.dart:402`）**`await _persistQueue()`**；
2. `_persistQueue`（`:826-833`）→ `QueuePersistenceManager.persistQueue`（`:89`）→ `QueueRepository.save`（`queue_repository.dart:30`）**開 Isar write transaction**；
3. 這時 Isar 已經被關掉（前一個測試的 tearDown，或本測試的 tearDown 提前跑）→ `IsarError: Isar instance has already been closed`；
4. `playSingle` 因此 throw，狀態永遠不會收斂 → `_pumpUntil` 50 圈後放棄；
5. 收尾時再撞上 `Tried to use AudioController after dispose was called`。

**這是測試 fixture 的生命週期洩漏（Isar / controller 在 in-flight async 完成前就被關閉），不是 pump 圈數不夠。** 加大圈數或換成條件式等待都治不了它 —— 條件永遠不會成立。

**建議的修法方向**（與 issue 目前寫的不同）：
- tearDown 前先 await 或取消所有 in-flight 的 persistence future；或
- 讓 `QueuePersistenceManager` / `QueueRepository` 在 Isar 已關閉時安全 no-op（`Isar.isOpen` 檢查）；或
- 讓 `AudioController.dispose()` 阻擋後續的 queue 寫入。

**順帶的生產環境疑慮（未驗證，值得單開 issue）**：`queue_manager.dart:402` 的 `await _persistQueue()` 在生產環境同樣可能撞上 app 關閉時的 Isar close。`lib/services/audio/AGENTS.md:148-150` 已經有一條規則：「Fire-and-forget backend cleanup futures must catch and log errors. ... async `FmpAudioService.dispose()` failures must not become unhandled async errors.」—— queue persistence 走的是同一類風險，但目前沒有對應防護。

**同時建議**：#43 的標題與內文都聚焦在單一測試名。實際上：
- 有**兩條**測試（至少）會這樣失敗；
- 本輪負載重現到的、更嚴重也更可重現的 flaky 是 `test/performance/`（2/2 必失敗），而目前**沒有任何 issue 在追它**。建議另開一個。

---

## 附錄 A：方法與可信度

**子代理分工**：6 個（2× opus 做 AGENTS.md 規則抽驗、1× opus 做架構對照研究、1× sonnet 做測試盤點、1× sonnet 做依賴健康度、1× sonnet 做文檔驗證、1× sonnet 做程式碼一致性掃描、1× claude-code-guide 查官方記憶檔語意）。

**我親自複驗的子代理結論（15 條，全部吻合）**：

| # | 複驗項 | 結果 |
|---|---|---|
| 1 | `playlistProvider` 不存在 | ✅ `rg` 零命中；實際 `playlistListProvider` |
| 2 | `_FmpImageCacheManager` 在 `network_image_cache_service.dart:431` | ✅ |
| 3 | `download_filenames.dart` 只有 3 個常數 | ✅ `:11,14,17` |
| 4 | `slang` 是 transitive 依賴 | ✅ `pubspec.lock` |
| 5 | `source_capabilities.dart` 有 12 個介面 | ✅ 逐行列出 |
| 6 | `audio_playback_types.dart` 只有 6 行 | ✅ |
| 7 | i18n 三語系各 1230 key、雙向缺漏 0 | ✅ 自寫腳本複算 |
| 8 | 37 處空 catch / 13 檔 | ✅ |
| 9 | `.select(` 72 處、`ref.watch` 411 / `ref.read` 342 | ✅（子代理報 70/409/341，計數法差異） |
| 10 | `services/` → `providers/` 反向依賴 6 檔 14 處 | ✅ |
| 11 | `lib/services/` 有 29 個 provider 宣告（audio_provider 佔 15） | ✅ |
| 12 | `download_event_handler.dart` 62 行、零 riverpod import | ✅ |
| 13 | 各層行數（core 3044 / data 12121 / services 30948 / providers 8636 / ui 39349） | ✅ 完全一致 |
| 14 | 測試案例數 `test(` 1140 + `testWidgets(` 101 | ✅ |
| 15 | `test/widget_test.dart` 是 `expect(true, isTrue)` 佔位 | ✅ |

**我駁回的子代理結論（1 條）**：測試盤點代理主張 commit `a4dcc315` 同時加入 phase2 與 phase4 測試、因此 phaseN 不是全域階段編號。核對 `git show --stat` 後，該 commit 只新增兩個測試檔，**都是 phase2**。反證不成立（見 §2.5）。

**我自己直接查證、未經子代理的**：官方 Claude Code memory 文檔逐字（WebFetch）、`flutter analyze` / `flutter test` 全部 7 次執行、4 回合壓力測試與失敗解析、CI 歷史與失敗 log 挖掘（`gh run view --log-failed`）、簡繁字元統計腳本、git 歷史考古（`docs/review/` 三代、四份 phase 計劃文檔、截圖時間軸）、`test/demo/bilibili_info_test.dart` 的網路請求證據萃取。

## 附錄 B：本輪未完成的部分

| 項目 | 為何未完成 | 建議何時做 |
|---|---|---|
| ~~**截圖是否過時**（P3-6）~~ | ✅ **已補**，見 §1.6b / §1.6c：實跑 `flutter run -d windows` 比對首頁後，**「過時」不成立**（版面結構與截圖完全一致）。改為證實了另外兩件事：8 張全是桌面截圖、零 Android；`home_desktop.png` 與 `home-page.png` 重複。剩餘 6 張未逐頁比對 | — |
| ~~**`main.dart` 通知頻道語系**~~ | ✅ **已補**，見 §1.6a：模擬器上以 per-app locale 切至 zh-CN 確認 —— UI 變簡中但頻道名仍是 `FMP Audio Playback`。根因追到 `slang-3.32.0/lib/api/singleton.dart:82-97`。已升為 **P1-9**，修法見 Quick win #25 | — |
| ~~`dart analyze test`~~ | ✅ **已補**，見 §1.1b：146 條（0 error / 14 warning / 132 info）。其中 5 條測試替身漂移成立；1 條 `unrelated_type_equality_checks` 我原判為缺陷，實跑後**推翻並更正** | — |
| ~~**`isar_community` 的既有 `.isar` 檔相容性**~~ | ✅ **已補**，見 §1.7：獨立 worktree + 生產資料庫複本 A/B 實測。11 collection / 1,523 筆逐項一致、檔案大小不變、`flutter analyze` 全綠。同時量出遷移會強制升級 slang 4 的連鎖成本 | — |
| ~~**Flutter 官方 benchmark 做法的一手引用**（§4.3）~~ | ✅ **已補**，見 §4.3：已取得 `docs.flutter.dev/cookbook/testing/integration/profiling` 的逐字引用（profile mode 的理由）與官方 timeline 指標清單，另補上官方部落格把 `noise`／`outlierRatio` 當一等公民指標的證據。該節已從「建議方向」改為【事實】+【推論】 | — |

**原本卡住的最後一項已在你放行後完成**：`isar_community` 的既有 `.isar` 檔相容性 ——
見 §1.7。在丟棄式 `git worktree` 內完成，主工作樹零改動；生產資料庫只用複本，原始檔
未被開啟。結論：**資料遷移成本為零**，但遷移會強制連帶升級 slang 4，且帶進兩個
`flutter analyze` 看不見的問題。

另有兩項是**範圍已知的縮減**，不是遺漏：
- §1.6c 只逐項比對了首頁，其餘 6 張截圖未逐頁比對（理由見該節）。
- §2.5 的類別命名審查指出 `Service`／`Handler`／`Manager`／`Controller`／`Coordinator`
  五種後綴並存且無文檔定義，但**刻意不提改名方案** —— 命名分工應該和 §5.3 的目錄重構
  同一輪決定，單獨改名只會製造一次無謂的大範圍 diff。
