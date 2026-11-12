# 實驗：玻璃三級的四平台可行性（M0 票 05b）

設計稿的玻璃分三級（`docs/design/DESIGN.md` §1.4）：**折射**（凸面邊緣的位移、色散，加模糊與飽和）、**standard**（模糊加飽和、高光、陰影，無折射）、**minimal**（無 backdrop 的實心填色，給系統「降低透明度」用）。這個實驗回答：每個候選做法在四個平台做得到哪一級、浮在 1000 首以上的列表上捲動時掉不掉幀、四個平台讀不讀得到「降低透明度」。

實驗程式可丟棄，但留在這裡：換 Flutter 或套件版本時照〈怎麼跑〉重量。

**決定**（擁有者 2026-11-12，看過 `results/` 的四平台對照圖後選定）：玻璃元件用 `liquid_glass_easy`（折射級 lens、standard 用 lite glass、minimal 自己畫實心）；捲動中不降級，但元件要能在執行期切換級數；iOS、macOS、Windows 跟系統的「降低透明度」退到 minimal，Android 不提供。寫在 brief §11、事實 K10、K19–K22，plan §1.4、§7，`docs/design/DESIGN.md` §1.4。

## 結果（2026-11-12）

環境：Flutter 3.47.5（Dart 3.13.4），macOS 27.0.1（160 Hz 內建螢幕），iOS 27.1 模擬器（iPhone Duo），Android 模擬器 API 37（`Medium_Phone_API_37.0`），Windows 11（`winpc`，Build 26200，160 Hz）。四個平台的 `ImageFilter.isShaderFilterSupported` 都是 true，也就是都跑 Impeller（Android 模擬器的 logcat：`Using the Impeller rendering backend (OpenGLES)`）。

### 每個候選做得到哪一級

以讀回的截圖為準（`results/<平台>-sheet.jpg`，每格是一個候選的迷你播放器、導覽膠囊、搜尋圓鈕，浮在黑色直條紋的彩色列表上；折射看的是條紋在玻璃邊緣有沒有被彎曲、放大）。

| 候選 | 版本 | iOS | Android | macOS | Windows |
| --- | --- | --- | --- | --- | --- |
| `liquid_glass_widgets` premium（`lgw-premium`） | 1.17.2 | 折射 | 折射 | 折射 | ❌ 見下 |
| `liquid_glass_widgets` standard／minimal（`lgw-standard`、`lgw-minimal`） | 1.17.2 | 模糊加飽和 | 模糊加飽和 | 模糊加飽和 | ❌ 見下 |
| `liquid_glass_easy` lens（`lge-lens`） | 5.2.0 | 折射 | 折射 | 折射 | 折射 |
| `liquid_glass_easy` lite（`lge-lite`） | 5.2.0 | 模糊加飽和 | 模糊加飽和 | 模糊加飽和 | 模糊加飽和 |
| 自己做：`BackdropFilter` + `ImageFilter.shader`（`own-refract`） | 核心 Flutter | 折射 | 折射 | 折射 | 折射 |
| 自己做：`BackdropFilter` 模糊加飽和矩陣（`own-blur`） | 核心 Flutter | 模糊加飽和 | 模糊加飽和 | 模糊加飽和 | 模糊加飽和 |
| 實心退路（`solid`） | 核心 Flutter | 實心 | 實心 | 實心 | 實心 |

- **`liquid_glass_widgets` 在 Windows 不能用**：照 README 呼叫 `LiquidGlassWidgets.initialize()`、`LiquidGlassWidgets.wrap()` 並用 `LiquidGlassScope` + `GlassBackgroundSource` 包列表時，整個視窗是白的，連列表都沒畫出來（`results/windows-sheet.jpg`；profile 與 debug 都一樣，FrameTiming 照常回報，所以 `windows.json` 的幀時間不算數）。用 `--plain` 拿掉這三樣之後 App 正常（`windows-plain-sheet.jpg`），但這時 `lgw-premium` 什麼都不畫、`lgw-standard` 只剩半透明填色。沒有再細分是三樣中的哪一樣造成白屏。
- **自己做的折射**：`probe/shaders/refract.frag` 照 `DESIGN.md` §1.1 算邊緣寬（min(短邊 × 0.42, 22)）與位移量（min(56, 短邊 × 0.6) 的一半，對應 SVG `feDisplacementMap` 的 scale），紅、綠、藍位移 1.06／1.00／0.94 倍；外面先套 5 的模糊、後套飽和 1.9。玻璃的矩形用全域實體像素傳給 shader：在 macOS 用 `REFRACT_DEBUG=true` 畫 SDF 確認，BackdropFilter 的輸入就是整個畫面的座標。
- **Impeller GLES 不要翻 Y 軸**：`ImageFilter.shader` 的 dartdoc 寫 OpenGL(ES) 後端要自己翻 Y，照做之後 Android 模擬器（Impeller GLES）取樣到畫面上方的列，顏色整個錯；拿掉翻轉才對（Flutter 3.47.0 的 release notes 有「[Impeller] Remove the texture coordinate system Y-flip workaround」）。iOS、macOS（Metal）不受影響。
- `liquid_glass_widgets` 的 standard 在 iOS、macOS 看不出折射（只有模糊），和它文件說的「輕量 shader、取背景貼圖」一致；套件預設的模糊與飽和比設計稿弱，probe 改成照 `DESIGN.md`（折射級模糊 5、其他 16、飽和 1.8、填色 .42）。
- 沒測的：`liquid_glass_renderer`（pub 上只有 pre-release，完整玻璃另外要 Flutter GPU，平台沒有 Windows）、`oc_liquid_glass`（只支援 Impeller 的三個行動與 Apple 平台），`cupertino_ui` 的 Liquid Glass 還沒發佈（brief 事實 K10）。

### 捲動時的幀時間

情境：1500 列的 `ListView`（每列 64 高，彩色底、黑色直條、粗體字），上面浮著 5 個玻璃（頂列 2 個、底部 dock 3 個），以 2000 px/s 等速捲 8 秒，記錄 FrameTiming（先捲 1 秒暖機不記）。每個候選只跑一次，不是 brief §15 的「5 次取中位數」：這裡要比的是候選之間的差，不是驗收。`python3 summarize.py results/<平台>.json` 印出下表。

**macOS**（profile，160 Hz，預算 6.2 ms）

| 候選 | 幀數／應有 | build p50／p99 | raster p50／p90／p99／max | > 16.7 ms | > 預算 |
| --- | --- | --- | --- | --- | --- |
| lgw-premium | 1268／1280 | 0.4／1.4 | 2.5／3.1／3.6／4.5 | 0 | 0 |
| lgw-standard | 1273／1280 | 0.3／1.2 | 2.0／3.3／3.8／4.4 | 0 | 0 |
| lgw-minimal | 1275／1280 | 0.3／1.2 | 2.8／3.6／4.1／4.8 | 0 | 0 |
| lge-lens | 1271／1280 | 0.3／1.3 | 1.6／3.0／3.5／4.5 | 0 | 1 |
| lge-lite | 1275／1280 | 0.3／1.2 | 2.7／3.3／3.7／4.3 | 0 | 0 |
| own-refract | 1275／1280 | 0.1／0.8 | 1.4／2.4／2.7／3.2 | 0 | 0 |
| own-blur | 1272／1280 | 0.3／1.3 | 2.1／2.8／4.0／4.5 | 0 | 0 |
| solid | 1269／1280 | 0.3／1.3 | 1.2／1.7／2.0／2.2 | 0 | 0 |

**Windows**（profile，`--plain`，160 Hz，預算 6.2 ms；`lgw-*` 在這個模式下畫得不對，見上）

| 候選 | 幀數／應有 | build p50／p99 | raster p50／p90／p99／max | > 16.7 ms | > 預算 |
| --- | --- | --- | --- | --- | --- |
| lgw-premium | 1269／1280 | 0.3／1.0 | 6.3／6.9／7.5／8.2 | 0 | 686 |
| lgw-standard | 1284／1280 | 0.3／1.0 | 6.2／6.9／7.5／8.7 | 0 | 607 |
| lgw-minimal | 1029／1280 | 0.3／1.0 | 7.8／8.8／9.6／21.4 | 1 | 1029 |
| lge-lens | 1243／1280 | 0.3／0.9 | 6.4／7.1／7.7／15.2 | 0 | 786 |
| lge-lite | 999／1280 | 0.3／0.9 | 7.9／8.6／9.3／10.2 | 0 | 999 |
| own-refract | 1350／1280 | 0.3／0.9 | 5.9／6.5／7.1／8.2 | 0 | 291 |
| own-blur | 1364／1280 | 0.2／0.9 | 5.8／6.6／7.1／7.6 | 0 | 318 |
| solid | 1680／1280 | 0.2／1.2 | 4.4／5.6／8.7／11.5 | 0 | 110 |

**iOS 模擬器**（debug：Flutter 不能在模擬器建 profile；畫面由 Mac 的 GPU 畫，數字不代表 iPhone）：8 個候選都是 0 幀超過 16.7 ms，raster p99 1.9–6.5 ms（`results/ios.json`）。

**Android 模擬器**（profile）：GPU 是 SwiftShader（CPU 軟體模擬，`dumpsys SurfaceFlinger`：`ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device …))`），而且只有 1 核。連 `solid` 的 raster 中位數都是 24 ms，玻璃候選 115–340 ms（`results/android.json`）。**只能證明畫得出來，不能拿來判斷效能。**

觀察：

- 以 brief §15 的標準（捲動中沒有超過 16.7 ms 的幀）：macOS 全部候選都是 0；Windows 除了 `lgw-minimal` 有 1 幀（21.4 ms），其他都是 0，包括折射級浮在捲動中的列表上方。
- 以 160 Hz 的預算（6.2 ms）：macOS 全過；Windows 只有 `solid` 接近全過，`own-refract` 與 `own-blur` 約 22–23% 的幀超過，其他候選超過得更多。`own-refract` 和 `own-blur` 幾乎一樣，所以在 Windows 上多付的成本是 backdrop 本身（每個玻璃一次背景讀取），不是折射 shader。
- 套件的「lite／minimal」在 Windows 比折射版還慢（`lge-lite`、`lgw-minimal` 每幀都超過 6.2 ms）：推測是它們的模糊比較大（16 對 5），沒有做同半徑的對照。所以退到 standard 時模糊半徑不能比折射級大，否則比折射級還慢。
- Windows 的「幀數」比「應有」（8 秒 × 160 Hz）多（`solid` 1680）：FrameTiming 每畫一幀記一筆，Windows 上的出幀數和 `display.refreshRate` 不一致，所以「> 預算」一欄在 Windows 只能參考；以 16.7 ms 為標準的結論不受影響。
- 模糊值：`own-blur` 照 `DESIGN.md` §1.4 用 18，套件的 standard／lite 用 §1.1 一般玻璃的 16，折射級的預模糊都是 5。
- 手機的實際效能這個環境量不到：iOS 只有模擬器（debug），Android 模擬器沒有 GPU 加速。舊版基準（`docs/audit/perf-baseline.md`）的 Android 數字是在 `winpc` 的模擬器（主機 GPU 模擬）上量的，和這台 Mac 的模擬器不能比。要量手機，用實機或有 GPU 加速的模擬器（例如 `winpc` 上的 Android 模擬器）跑 `python3 run.py android`。

### 「降低透明度」讀不讀得到

Flutter 3.47.5 讀不到：`dart:ui` 的 `AccessibilityFeatures` 沒有這個欄位（追蹤中：flutter/flutter#190318）。`liquid_glass_widgets` 與 `cupertino_ui` 的分支拿 `highContrast`（增加對比）代替，下表顯示兩者是不同的設定。probe 用 platform channel `fmpx/a11y` 自己讀（原生端在 `probe/macos/Runner/MainFlutterWindow.swift`、`probe/ios/Runner/AppDelegate.swift`、`probe/windows/runner/flutter_window.cpp`、`probe/android/.../MainActivity.kt`）。

| 平台 | 原生 API | 設定關 | 設定開 | Flutter `highContrast`（開時） |
| --- | --- | --- | --- | --- |
| macOS | `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` | false | true | false |
| iOS | `UIAccessibility.isReduceTransparencyEnabled` | false | true | false |
| Windows | 登錄 `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` 的 `EnableTransparency`（0 = 關掉「透明效果」） | false | true | false |
| Android | 沒有標準 API（AOSP 沒有這個設定；Samsung One UI 有「減少透明度與模糊」，key 未查到） | null | — | — |

切換方式：macOS 在「系統設定 › 輔助使用 › 顯示器 › 減少透明度」（`defaults write com.apple.universalaccess` 被系統擋，寫不進去）；iOS 模擬器在「設定 › 輔助使用 › 顯示與文字大小 › 減少透明度」（`simctl ui` 沒有這個選項）；Windows 直接改登錄值（等同「設定 › 個人化 › 色彩 › 透明效果」）。結果在 `results/<平台>-a11y-off.json`、`-a11y-on.json`。每次測完都已切回原本的值。Windows 另有 `UISettings.AdvancedEffectsEnabled`（WinRT，附變更事件），實驗沒有用它。設定變更的通知（iOS `reduceTransparencyStatusDidChangeNotification`、macOS `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`）沒有實測，probe 只在啟動時讀一次。

## 檔案

| 路徑 | 內容 |
| --- | --- |
| `probe/` | Flutter App（`com.personal.fmpx.glassProbe`／`com.personal.fmpx.glass_probe`）：`lib/variants.dart` 是 8 個候選，`lib/main.dart` 依序顯示每個候選（場景）、捲動量幀，`shaders/refract.frag` 是自己做的折射 |
| `run.py` | macOS、iOS 模擬器、Android 模擬器：建置、持共用裝置鎖啟動、依 probe 宣告的場景截圖、收結果、產生對照圖 |
| `run-windows.sh`、`windows/probe.ps1` | Windows：同步到 `winpc` 的 `C:\fmpx\glass`，以排程工作在桌面工作階段建置、截圖（`PrintWindow` 與螢幕複製各一張），取回結果 |
| `summarize.py` | 把結果印成上面的表 |
| `results/<平台>.json` | 環境（平台、renderer、更新率、DPR、無障礙旗標）與每個候選的幀時間 |
| `results/<平台>-sheet.jpg` | 每個候選的 dock 截圖（裁切、統一成 2 倍），完整截圖不進 repo |
| `results/windows.json`、`windows-sheet.jpg` | Windows 預設模式（含 `liquid_glass_widgets` 初始化）：白屏的證據 |
| `results/windows-plain.json`、`windows-plain-sheet.jpg` | Windows `--plain`：上面表格的來源 |
| `results/<平台>-a11y*.json` | 「降低透明度」的讀取結果 |

## 怎麼跑

```bash
cd scripts/experiments/glass
python3 run.py macos                       # 全部候選；results/macos.json、macos-sheet.jpg
python3 run.py android
IOS_SHOT_ARGS=--display=1 python3 run.py ios   # iPhone Duo（雙螢幕）截圖要 --display=1
./run-windows.sh                           # 含 liquid_glass_widgets 初始化（目前會白屏）
APP_ARGS=--plain ./run-windows.sh          # 不初始化 liquid_glass_widgets：results/windows-plain.json
VARIANTS=own-refract,solid python3 run.py macos   # 部分候選：<平台>-partial.json
MODE=a11y python3 run.py macos             # 只讀無障礙旗標：<平台>-a11y.json（切設定前後各跑一次，自己改名成 -off／-on）
MODE=a11y ./run-windows.sh                 # Windows 同上（debug 建置）：windows-a11y.json
python3 summarize.py results/macos.json
```

需要：

- Flutter 3.47.5、Xcode；Python 3 加 Pillow（產生對照圖）。iOS 模擬器與 Android 模擬器先開好。
- **共用裝置鎖**（plan §2、§4）：`run.py` 的裝置階段經 `app/tool/device_lock.dart` 持鎖；`run-windows.sh` 開頭 source `app/tool/winpc/lock_guard.sh`。macOS、iOS、Android 的建置在鎖外；Windows 在 `winpc` 上建置，整段持鎖。
- macOS 截圖用 `orca computer get-app-state`（執行的終端機要有「螢幕錄製」權限）。
- `winpc` 的桌面有人登入；截圖會短暫把 probe 視窗拉到最上層。
- 結果檔名照模式自動加尾碼：`-partial`（設了 `VARIANTS`）、`-a11y`（`MODE=a11y`）、`-plain`（Windows 的 `APP_ARGS`）。
- 每個結果檔的 `env.a11y` 都記了當時讀到的「降低透明度」，所以 a11y 不一定要用 `MODE=a11y` 跑：`windows-a11y-on.json` 是關掉透明效果後跑 `VARIANTS=solid APP_ARGS=--plain ./run-windows.sh`（profile，只跑實心）的結果。Windows 切換：持鎖時 `ssh winpc 'Set-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name EnableTransparency -Value 0'`，跑完改回 `-Value 1`（先讀原值）。
- 清掉 `winpc` 上的實驗目錄：`(cd app && dart run tool/device_lock.dart -- ssh winpc 'Remove-Item -Recurse -Force C:\fmpx\glass')`。
- 場景與捲動的時間可用 `SCENE_HOLD_MS`、`SCROLL_MS` 調（dart-define，預設 4000、8000）。
