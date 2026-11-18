# 13: 背景播放與系統媒體控制

Status: done
Blocked by: 07、09
讀: brief §6；事實 I2、I5、K18、M10、R4；architecture〈主要依賴〉〈風險與回寫點〉；`scripts/experiments/macos-now-playing/`；spec〈共同規則〉

## What to build

App 在背景時繼續播放（Android 前景服務與通知、iOS 背景音訊模式、桌面最小化），系統媒體控制接上：Android、iOS、macOS 用 audio_service，Windows 用 runner 裡自己接的 SMTC（2026-11-19 擁有者同意，原本是 smtc_windows；Dart 端只有 `platform/` 碰 `fmp/media` 頻道）。Now Playing 顯示曲名、作者、封面、長度與位置；系統的播放、暫停、上一首、下一首、拖動進度控制 App。App 要出過聲才會成為 Now Playing App（事實 M10），重啟後先在 App 按播放。

iOS 的中斷與 Now Playing 模擬器驗不到的部分記在 Comments（事實 I2、I5），留給使用者試。audio_service 在 macOS 壞了就照〈風險與回寫點〉改用自己的 platform channel。

## 驗收

- [x] 四平台：App 在背景時繼續播放，讀回 log 或畫面。（Windows 跳過，見 Comments）
- [x] Now Playing 的資訊與系統的播放、暫停、上一首、下一首、拖動進度有作用（macOS 控制中心、Windows 媒體浮層、Android 通知用模擬器讀回；iOS 模擬器做得到的部分）。（Windows 跳過、iOS 只驗得到背景播放，見 Comments）
- [x] 換曲、暫停、seek 時 Now Playing 的資訊跟著更新，有測試（fake 的媒體控制）。
- [x] audio_service 的版本與 Windows 的做法寫進 ARCHITECTURE〈主要依賴〉；需要的平台設定（manifest、Info.plist、entitlements）寫進 `docs/development.md`〈平台〉。
- [x] 模擬器驗不到的項目列在 Comments。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。（`--skip-windows`）

## Comments

決定：Windows 媒體控制不用 smtc_windows（事實 W7），改在 runner 用 C++ 接 SMTC；brief §6、ARCHITECTURE〈主要依賴〉、spec 照擁有者選的做法改，改動在合併前經協調者轉給擁有者本人看過、同意保留（使用者同意）
決定：測試接縫四層：綁定層（provider 加 fake 媒體控制）、audio_service 的 handler 對應、Windows 頻道的 Dart 端（mock messenger）、三平台實跑（Agent 定）
決定：Now Playing 在換曲、狀態、長度、上下首能不能按改變，與暫停中改位置、拖進度時馬上送；照常播放時最多 5 秒重送位置（SMTC 不自己推進，事實 W6）（Agent 定）
決定：系統的播放、暫停照 App 的播放鈕：播完或失敗的那首按播放從頭再播，解析、載入中按暫停不動；上下首照佇列，臨時播放時回佇列（Agent 定）
決定：沒有上一首或下一首時系統媒體控制不放那顆鈕，長度不知道時不能拖進度（Agent 定）
決定：Android 滑掉暫停中的通知（audio_service 的 stop）只算暫停，佇列與位置留著（Agent 定）
決定：Now Playing 的封面用 App 的封面快取下載插件給的那張（B 站是 160 方形縮圖），不另取大圖（Agent 定）
決定：Android 通知頻道的名字是「播放控制」（en：Playback controls），字串在 `app.mediaNotificationChannel`（Agent 定）
決定：`androidStopForegroundOnPause` 維持預設的 true，同舊版（協調者代答）（Agent 定）
決定：Windows 的 C++ 放在 CMake 選項 `FMP_WINDOWS_SMTC` 後面、預設 OFF；Dart 啟動時問 `available`，沒人接就寫 warning、不啟用（協調者代答）（Agent 定）
決定：選項打開時 runner 以 C++20 編譯、連 `windowsapp.lib`（C++/WinRT 在 VS 2026 的 C++17 下編不過，audio_service_win #6）（Agent 定）
決定：實跑的系統動作經宿主的 `/system` 與 `tool/real_run_system.sh`（`RealRun.system`），和截圖同一套等回覆的做法（Agent 定）
決定：Android 播放中 uiautomator 讀不到畫面，實跑先用媒體鍵暫停再讀通知，點按用讀到的位置；關動畫也沒用，不改模擬器設定（Agent 定）
決定：實跑情境 `media_run.dart` 解析兩首（要有上下首），比 spec 的播一首多一首；這個 session 三平台各跑了 2–5 次（Agent 定）
決定：Android 實體的播放鍵、暫停鍵照上一版（fb75a020 的 `MediaKeyFix.java`）在原生端改寫成直接播放、暫停，單鍵的播放／暫停照常切換（協調者代答）（Agent 定）
決定：A6 的失效條件寫成實跑情境的兩步（暫停中按暫停、播放中按播放，修前紅、修後綠），Dart 端補 `MediaKeyFix` 何時裝的 mock 頻道測試與 audio_service 釘版測試；原生改寫本身沒有單元測試（Agent 定）
決定：iOS 模擬器的控制中心與鎖屏讀不到（`orca emulator button lock` 沒作用），iOS 只驗背景播放（Agent 定）
實跑讀回（2026-11-19 最終 commit；截圖與讀回在 `<暫存目錄>`，不進 repo）：macOS 縮到 Dock（`hidden`）10 秒，位置 1.7→11.7 秒仍在播；「正在播放」面板讀回曲名、作者、封面、`00:14`，面板的暫停、播放、下一首、上一首、拖到 60 秒與媒體鍵都讀回狀態改變。Android 按 Home（`paused`）位置 1.0→11.0 秒；通知讀回曲名、作者、封面、`Play`、`11 seconds of 59 minutes, 33 seconds`、`Next track`，第一首沒有上一首、最後一首沒有下一首；通知的播放、暫停、下一首、上一首、進度條（拖到 39:18）與媒體鍵 pause、next、play-pause 都讀回狀態改變；暫停中再按 pause 維持暫停、播放中按 play 照常播（位置 11.3→14.5 秒）。iOS 切到「設定」（`paused`）位置 1.4→11.2 秒仍在播。
模擬器驗不到（留給擁有者試）：① iOS 控制中心與鎖屏的 Now Playing（曲名、作者、封面、進度）與它的播放、暫停、上下首、拖進度；audio_service 在 iOS 不設 `playbackState`（事實 I5），看鎖屏的播放鈕跟不跟著狀態變。② iOS 的中斷：來電、Siri、別的 App 開始播放時暫停，結束後該續播的有沒有續播，duck 後音量有沒有變大（事實 I2 待重驗；現在交給 just_audio 的 `handleInterruptions`，事實 K30）。③ 真手機的 Android：暫停幾分鐘（或鎖屏放著）後，從通知或鎖屏按播放能接著播（`androidStopForegroundOnPause: true`、Android 12+ 的前景服務限制，事實 A7 待重驗）；不行再回頭改。④ 真耳機與車機（藍牙）：已暫停時按「暫停」不會開始播、播放中按「播放」不會暫停或重來，單鍵的播放／暫停照常切換；模擬器只用 `cmd media_session dispatch` 驗過（事實 A6）。release 版（R8）也要試一次，keep 規則漏了的話會退回切換。⑤ Android 來電中斷後的續播（事實 A7）。⑥ 拔耳機時暫停（事實 K30）。
Windows 跳過：SMTC 的 C++（`windows/runner/media_controls.cpp`）沒在 Windows 上編譯過，所以 CMake 選項 `FMP_WINDOWS_SMTC` 預設 OFF、主程式不編它，Dart 端問不到 `available` 就不啟用；C++ 沒有測試，只有 Dart 端的頻道單元測試。補驗步驟：(1) 選項關著照常建置、跑完整閘門的 Windows 步驟，log 有 `Windows media controls are not built in`、播放照常；(2) 把 `app/windows/runner/CMakeLists.txt` 的 `option(FMP_WINDOWS_SMTC … OFF)` 暫時改 ON，同步後 `build.ps1` 編譯過（C++20、`windowsapp.lib`）；(3) 播一首：媒體浮層顯示曲名、作者、封面（https 的 webp 縮圖，事實 W6 待重驗的「封面要 https」一起看），時間軸的長度與位置對，播放中會不會自己往前（W6 待重驗；不會就最多落後 5 秒）；(4) 浮層與鍵盤媒體鍵的播放、暫停、上一首、下一首、拖進度有作用，第一首時上一首停用；(5) 縮到工作列後繼續播；(6) 關 App 不崩潰（事實 W11 那類收尾問題）；(7) 都過了才把預設改成 ON、重跑完整閘門，否則記下失敗、留著 OFF。實跑的系統動作（`RealRun.system`）Windows 還沒接，`media_run.dart` 在 Windows 會失敗。
code-review 未處理：① 播放中往前拖不到 2 秒不算拖進度，Now Playing 最多 5 秒後才更新（audio_service 那邊系統自己推算，看不出來）。② `platform/media_controls.dart` 與 `playback/media_controls.dart` 同名、`main.dart` 兩個都 import，留著。③ `WindowsMediaControls.dispose()` 只有測試在用（清掉靜態頻道的 handler），留著。④ audio_service 與 Windows 各有一個 `PlaybackStatus` 的對應 switch，各平台的對應本來就不同，留著。
Session 紀錄：2026-11-19 背景播放與系統媒體控制：媒體控制介面與綁定、audio_service（Android、iOS、macOS，含 Android 媒體鍵修正）與 Windows 自己接的 SMTC（選項預設關）；三平台實跑背景播放，Android 通知與 macOS 面板驅動播放控制；完整閘門 --skip-windows 綠
變更：Added｜背景播放｜App 在背景時繼續播放：手機切到別的 App 或鎖屏、桌面縮到 Dock；Android 播放時顯示媒體通知
變更：Added｜系統媒體控制｜Android 通知與鎖屏、iOS 控制中心與鎖屏、macOS 選單列的「正在播放」顯示曲名、作者、封面與進度，可以播放、暫停、上下首、拖進度；耳機與鍵盤的媒體鍵也有作用，Android 耳機或車上的「暫停」在已暫停時不會開始播放（Windows 還沒有）
之後改 brief／ARCHITECTURE 先用 AskUserQuestion 給擁有者看草稿，確認後才寫入；這次的三處改動是寫入後才補給擁有者看。
