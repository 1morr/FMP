# 效能基準（重寫前）

> 現況描述，未經確認，不代表目標。

量測日期：2026-09-26，分支 `docs/audit`（HEAD `6d78fe23`）。這份文件是重寫後的比較基準：每個數字都附量測命令與原始輸出摘錄，重寫後用同一組命令重量即可對照。

## 量測環境

| 項目 | 值 |
|------|----|
| 主機 | Intel Core i9-13900HX（24C/32T）、31.8 GB RAM、NVIDIA RTX 4080 Laptop GPU |
| 主機 OS | Windows 11 專業工作站版 build 26200；主螢幕 2560×1440、縮放 150%（FMP 視窗 DPI 144） |
| Flutter | 3.47.1 stable（framework `6655482ec0`、engine `11d79658c4`）、Dart 3.13.1 |
| Build mode | **profile**（Android `app-profile.apk` 47.5 MB；Windows `build\windows\x64\runner\Profile\fmp.exe`） |
| Android emulator | AVD `Medium_Phone`：API 37（`android-37.2-beta3` google_apis_playstore ps16k x86_64）、4 vCPU、2048 MB RAM、1080×2400 @ 420 dpi、`hw.gpu.mode=auto`（GPU 由主機模擬） |
| Android App 資料 | emulator 內既有測試資料：2 個歌單（154 首 + 1 首）、15 筆播放歷史、佇列空 |
| Windows App 資料 | **使用者真實資料**：profile build 走 `getApplicationDocumentsDirectory()` = `C:\Users\<user>\Documents\FMP\`（`lib/data/database/database_provider.dart:49-52`），1 個 1195 首的歌單、佇列 1195 首、有目前曲目 |
| 網路 | 兩平台首頁都會自動載入三個音源的排行榜（Bilibili / YouTube / 網易雲）與封面；Windows 右側 Detail Panel 另載入目前曲目的資訊與評論。這些請求無法避免，數字包含它們 |

注意事項：

- emulator 的 CPU、GPU 都是虛擬的，**Android 數字只能跟同一台主機、同一個 AVD 比**，不代表實機。
- 兩個平台的資料量不同（Windows 有 1195 首佇列與目前曲目、Android 佇列空），所以兩平台之間的數字不能直接比較。
- 同一時段另有其他 agent 在同一個 checkout 跑 `build_runner` / `flutter test`（codegen 開始時曾出現 `Waiting for already-running build_runner.`），主機不是完全閒置。

## 摘要

| 指標 | Android（Medium_Phone） | Windows |
|------|------------------------|---------|
| 冷啟動到首幀 `timeToFirstFrameMicros`（`--trace-startup`，3 次中位數） | **1239 ms** | **1731 ms** |
| 首幀完成光柵化 `timeToFirstFrameRasterizedMicros`（中位數） | 1292 ms | 1752 ms |
| `am start -W` TotalTime（3 次中位數） | 1482 ms | — |
| 首頁穩定後記憶體（3 次中位數） | PSS **183,367 KB**（≈179 MB）／RSS 310,752 KB | Working Set **299.9 MB**／Private **440.6 MB** |
| 長列表捲動，UI thread 每幀 `Animator::BeginFrame` 中位數／p99 | 1.00 ms／4.18 ms（歌單 154 首） | 0.45 ms／5.45 ms（佇列 1195 首） |
| 長列表捲動，raster 每幀 `GPURasterizer::Draw` 中位數／p99 | 4.27 ms／21.62 ms | 1.96 ms／2.72 ms |
| 捲動中超過 16.7 ms 的 raster 幀 | 43／302（第 1 輪）、17／306（第 2 輪） | 0／312、0／316 |

## 1. 啟動時間

### 方法 A：`flutter run --profile --trace-startup`（兩平台）

量的是 engine 進入點到 Dart 首幀（`timeToFirstFrameMicros`）與首幀光柵化完成（`timeToFirstFrameRasterizedMicros`）。每次跑完 App 會自行結束，`build/start_up_info.json` 被覆寫，所以每次跑完立刻複製一份。Android 每次之間先 `adb shell am force-stop com.personal.fmp`；Windows 每次之間程序已結束。

```bash
# Android
adb shell am force-stop com.personal.fmp
flutter run --profile --trace-startup -d emulator-5554
cp build/start_up_info.json <scratch>/android_startup<i>.json
# Windows
flutter run --profile --trace-startup -d windows
cp build/start_up_info.json <scratch>/win_startup<i>.json
```

原始輸出（µs）：

| 次 | 平台 | timeToFrameworkInit | timeToFirstFrame | timeToFirstFrameRasterized | timeAfterFrameworkInit |
|----|------|--------------------:|-----------------:|---------------------------:|-----------------------:|
| 1 | Android | 380,399 | 1,245,787 | 1,354,611 | 865,388 |
| 2 | Android | 371,942 | 1,238,945 | 1,292,482 | 867,003 |
| 3 | Android | 252,215 | 875,541 | 936,132 | 623,326 |
| 1 | Windows | 1,286,636 | 2,322,241 | 2,346,683 | 1,035,605 |
| 2 | Windows | 1,350,721 | 1,730,724 | 1,751,879 | 380,003 |
| 3 | Windows | 1,332,404 | 1,676,262 | 1,717,516 | 343,858 |

終端摘錄：`Time to first frame: 1245ms.` / `1238ms.` / `875ms.`（Android）；`Time to first frame: 2322ms.` / `1730ms.` / `1676ms.`（Windows）。

觀察：

- Windows 第 1 次是剛建完 profile build 後的第一次啟動，`timeAfterFrameworkInit` 比後兩次多約 0.65 s。**推測**是檔案系統與 DLL 冷快取；後兩次較能代表常態。
- Windows 的 `timeToFrameworkInit` 穩定在 1.29–1.35 s，佔首幀時間的 77–80%；Android 只有 0.25–0.38 s。`WidgetsFlutterBinding.ensureInitialized()` 在 `main()` 很前面就呼叫（`lib/main.dart:129`），所以這段時間主要花在 Dart 之前。**推測**是 Windows runner 的原生 plugin 註冊（webview、media_kit、SMTC 等）與 engine 啟動，本次沒有拆解。
- Android 第 3 次明顯較快（875 ms），三次差距大。emulator 的變異性高，重寫後比較時建議量 5 次以上。

### 方法 B：`adb shell am start -W`（僅 Android）

量的是 Activity 冷啟動到第一個視窗繪製（`TotalTime`）。Flutter 的 Activity 視窗可能在 Dart 首幀之前就算「已繪製」，所以它跟方法 A 不是同一個終點。

```bash
adb shell am force-stop com.personal.fmp; adb shell sleep 3
adb shell am start -W -n com.personal.fmp/.MainActivity
```

| 次 | LaunchState | TotalTime | WaitTime |
|----|-------------|----------:|---------:|
| 1 | COLD | 1482 | 1489 |
| 2 | COLD | 1331 | 1334 |
| 3 | COLD | 1677 | 1680 |
| 4（量記憶體時順帶） | COLD | 1458 | — |
| 5（量記憶體時順帶） | COLD | 1415 | — |

前 3 次中位數 1482 ms；5 次中位數 1458 ms。

## 2. 記憶體

### Android：`dumpsys meminfo`

冷啟動後停在首頁，等 20–28 秒（排行榜與封面載入完）才取樣。

```bash
adb shell am force-stop com.personal.fmp; adb shell am start -W -n com.personal.fmp/.MainActivity
adb shell sleep 28
adb shell dumpsys meminfo com.personal.fmp
```

| 取樣 | TOTAL PSS (KB) | TOTAL RSS (KB) |
|------|---------------:|---------------:|
| 1（啟動後約 20 s） | 183,367 | 310,752 |
| 2（啟動後約 28 s） | 185,178 | 312,024 |
| 3（啟動後約 28 s） | 180,843 | 307,716 |

取樣 2 的 App Summary 摘錄：

```
           Java Heap:    10936                          36076
         Native Heap:    41556                          45984
                Code:    53028                         158028
               Stack:     1248                           1256
            Graphics:        0                              0
       Private Other:    62372
              System:    16038
           TOTAL PSS:   185178            TOTAL RSS:   312024      TOTAL SWAP (KB):        0
```

`Graphics: 0` 是 emulator 的 GPU 由主機模擬所致，實機會有數十 MB，不能拿來當實機的圖形記憶體基準。

### Windows：`Get-Process`

Working Set 是實體記憶體駐留量，Private 是 commit 的私有位元組（含未駐留部分）。

```powershell
Get-Process fmp | Select-Object Id, WorkingSet64, PrivateMemorySize64, PeakWorkingSet64
```

| 取樣 | Working Set | Private | 備註 |
|------|------------:|--------:|------|
| 1 | 281.0 MB | 416.5 MB | 啟動後約 1 分鐘；Peak WS 297.2 MB |
| 2 | 299.9 MB | 440.6 MB | 首幀後 30 s |
| 3 | 307.1 MB | 446.6 MB | 首幀後 30 s |

中位數：Working Set 299.9 MB，Private 440.6 MB。Windows 載入了 1195 首的佇列與 Detail Panel 的封面、評論，這些都算在裡面。

## 3. 長列表捲動

### 3.1 `test/performance/` 下的兩支 benchmark

兩支都**不叫 `*_test.dart`**，檔頭註解說明它們量的是絕對時間，只在閒置機器上手動跑（`test/performance/startup_benchmark.dart:6-15`）。它們跑在 `flutter test` 的主機 VM 上（debug JIT、無真正的 GPU），**量不到 App 的實際 UI**：

- `list_scrolling_benchmark.dart`：用產生的 `Track` 建 **Material 內建的 `ListTile`** 或手寫的仿列（`:150` 起），不是 FMP 的 `TrackTile`；只 import `track.dart`。
- `startup_benchmark.dart`：量 `Track` 建構、字串處理、`Directory.exists` 等微操作，不涉及 App 啟動流程。名稱中的「startup」與內容不一致。
- 兩支都沒有網路存取，可離線跑。

```bash
flutter test test/performance/list_scrolling_benchmark.dart test/performance/startup_benchmark.dart -r expanded
# 00:03 +13: All tests passed!
```

輸出摘錄：

```
Created 1000 Track models in 4ms
Extracted display names 50000 times in 6ms
Performed 300000 date operations in 37ms
Performed 2000000 string operations in 433ms
Initial render of 100 items: 506ms
Initial render of 500 items: 76ms
10 scroll operations with 1000 items: 392ms   (Average: 39.2ms per scroll)
Complex list item render (100 items): 213ms
Checked 10000 directory existence in 1482ms
Performed 200000 path operations in 122ms
100 widget rebuilds: 1155ms                   (Average: 11.55ms per rebuild)
Filtered and sorted 10000 tracks in 14ms
500 searches on 5000 tracks: 602ms
```

「100 items 506 ms、500 items 76 ms」這種倒掛說明第一個 `testWidgets` 吃到了 JIT 暖機，這些數字對重寫的參考價值低。

### 3.2 App 內實測：VM Service timeline

`adb shell dumpsys gfxinfo com.personal.fmp` 對 Flutter 無效：捲動後 `Total frames rendered: 0`。Flutter 畫在 `SurfaceView` 上，不經過 HWUI 的統計。所以改用 VM Service 錄 timeline：`flutter run --profile` 起 App，對 `setVMTimelineFlags`（`["Dart","Embedder","GC"]`）→ `clearVMTimeline` → 操作 → `getVMTimeline`，再統計每幀的 `Animator::BeginFrame`（UI thread：build + layout + paint）與 `GPURasterizer::Draw`（raster thread）耗時。統計腳本放在 scratchpad（`timeline.py`），邏輯是對同名事件配對 `B`/`E` 或讀 `X` 的 `dur`。

**Android**：歌單詳情頁（154 首），每輪 8 次向下、8 次向上 `adb shell input swipe 540 2000 540 500 150`，間隔 0.8 s。

```
== pass 1
Animator::BeginFrame: n=303 median=1.00ms p90=1.92ms p99=4.18ms max=6.32ms >16.7ms=0
GPURasterizer::Draw:  n=302 median=4.27ms p90=17.16ms p99=21.62ms max=25.76ms >16.7ms=43
== pass 2
Animator::BeginFrame: n=308 median=0.81ms p90=1.66ms p99=4.01ms max=5.39ms >16.7ms=0
GPURasterizer::Draw:  n=306 median=3.67ms p90=12.68ms p99=20.99ms max=35.56ms >16.7ms=17
```

**Windows**：佇列頁（1195 首），1904×1191 視窗，滑鼠滾輪向下 40 格、再向上 40 格（每格 `WHEEL_DELTA`×3，間隔 60 ms）。

```
== pass 1
Animator::BeginFrame: n=313 median=0.45ms p90=1.06ms p99=5.45ms max=8.03ms >16.7ms=0
GPURasterizer::Draw:  n=312 median=1.96ms p90=2.26ms p99=2.72ms max=10.00ms >16.7ms=0
== pass 2
Animator::BeginFrame: n=315 median=0.41ms p90=1.07ms p99=5.01ms max=10.41ms >16.7ms=0
GPURasterizer::Draw:  n=316 median=1.89ms p90=2.11ms p99=2.37ms max=2.58ms >16.7ms=0
```

觀察：

- 兩平台的 UI thread 都遠低於 16.7 ms 預算，捲動卡頓（若有）不在 Dart 端。
- Android 的 raster 尾端（p90 12–17 ms、最高 35 ms）落在 emulator 的軟體／轉譯 GPU 上，**推測**不代表實機；但 timeline 裡 `Canvas::saveLayer` 在約 303 幀內出現 2040 次（約每幀 6.7 次），同一頁在 Windows 沒有進入前 25 名。saveLayer 在實機上同樣昂貴，來源（`Opacity`、帶抗鋸齒的 clip、`ShaderMask` 之類）本次沒有追查，值得在重寫時用實機 DevTools 確認。
- Windows timeline 每幀有約 4 個 `Semantics.*` 事件（313 幀 1252 次）：Windows 上無障礙樹一直處於啟用狀態，每幀都在更新語意節點。

## 4. 沒做到的項目

| 項目 | 原因 |
|------|------|
| 實機（非 emulator）Android 數字 | 本機沒有接實機 |
| Android 的 `Graphics` 記憶體、raster 時間的實機意義 | emulator 的 GPU 由主機模擬，`Graphics: 0` |
| `gfxinfo` 幀統計 | Flutter 走 `SurfaceView`，`Total frames rendered: 0`，改用 VM Service timeline |
| DevTools 圖形介面的 frame chart | 用 VM Service HTTP 端點取同一份 timeline 取代，沒有開 DevTools 網頁 |
| 播放中的 CPU／記憶體 | 任務要求不主動播放；Android 佇列空 |
| Windows 乾淨資料的基準 | profile build 讀使用者真實的 `Documents\FMP`，沒有獨立資料目錄的開關（見 `docs/audit/ui.md` § 6.0） |
