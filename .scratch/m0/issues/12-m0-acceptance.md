# 12: M0 驗收與封存

**What to build:** 把 spec〈驗收〉逐條對到證據，跑完里程碑的 code-review 與乾淨 checkout 上的完整閘門，請擁有者在四個平台各試一次，最後封存 M0：session 紀錄與偏差搬到 `docs/archive/M0.md`，交棒給下一個里程碑。

讀：spec〈驗收〉〈共同規則〉；`docs/progress.md` 開頭的封存規則；plan §4、§5.3；票 01–11、02b、05b 的 `## Comments`

**Blocked by:** 01–11、02b、05b 全部

**Status:** done

做法：

1. **里程碑 code-review**：`/code-review ca551939`（M0 開工的 commit）。Spec 軸讀 spec 與票 01–11、05b，Standards 軸讀 `AGENTS.md`。小問題當場修。
2. **逐條對照**：spec〈驗收〉每一條對到一條測試、一次閘門輸出或一次實跑紀錄，做成表記在 Comments；缺的補上。
3. **乾淨 checkout**：`git worktree add --detach` 到暫存目錄，從零安裝後跑 `dart run tool/check.dart` 完整版。
4. **Comments 歸屬**：票 01–11、05b 的 Comments 與這一票 code-review 沒處理的發現，逐條分成「修掉」「延後」「不做」。延後的寫進 plan 對應里程碑那一節（還沒開工的是 plan §5.x）；不做的寫理由。
5. **擁有者試用**：需要擁有者在場，開工時先約時間。擁有者在四個平台各搜一次、播一首。
6. **舊版 CI**：push main 之後確認 `ci.yml` 綠燈（push 照 `AGENTS.md` 流程）。
7. **封存**（同一個 commit）：M0 的 session 紀錄與偏差整段搬到 `docs/archive/M0.md`，逐列比對不遺失。里程碑表 M0 的備註換成封存檔的連結，加上 M1 列；plan 開頭的狀態行更新。spec 與票留在原處。progress.md 加一列 `M1 準備` 的紀錄，下一步寫 `/to-tickets docs/plan.md 拆 M1 的票`（D 已在 2026-11-11 定稿）。

- [x] 里程碑 code-review 跑完，小問題已修。
- [x] spec〈驗收〉每一條在 Comments 有對應的證據；缺的已補。
- [x] 乾淨 checkout 上 `check.dart` 完整版綠燈，貼輸出最後幾行。（`94294d95` 全綠；最終 commit `7bc0e1a5` 連跑 4 次都只紅在 `winpc` 的環境當掉，擁有者 2026-11-12 同意照實記錄後關票，見 Comments）
- [x] 票 01–11、05b 與本票沒處理的發現逐條歸屬；延後的已寫進 plan。
- [x] 擁有者在四個平台試用過，結果記在 Comments。（擁有者 2026-11-12 委託 agent 代測，不是擁有者親試，見 Comments）
- [x] main 上的 `ci.yml` 綠燈，貼 run 連結。（main `94294d95`：https://github.com/1morr/FMP/actions/runs/43160831525 ；合併、push 由協調者做，之後由協調者再確認）
- [x] `docs/archive/M0.md` 有 M0 全部的 session 紀錄與偏差，progress.md 只留進行中的里程碑；里程碑表與 plan 已更新。

## Comments

### 里程碑 code-review（`ca551939` 起，Standards 與 Spec 兩軸）

範圍：`app/`（排除產生檔、平台目錄、`dist/`、fixture）、`.githooks/`、根目錄設定；`scripts/experiments/` 只核對結論有沒有寫回文件。

已修（commit `33a6a3a5`、`6beb093b`）：

- Standards：`i18n_keys_test.dart` 是靜態規則卻沒有雙向變異 → 抽出 `i18nKeys`、`keyMismatches`，補「少或多一個 key 會紅」「改譯文、排版、順序不紅」；另外拿真的 `en.i18n.json` 刪一個 key，確認會紅、還原後綠。
- Standards：`plugin_error_codes_test.dart` 的「turns red」只斷言 `isNot` 一個隨手寫的集合，沒有證明比對會紅 → 抽出 `codeMismatches`，三個方向（多、少、相同）都斷言。
- Standards：`tool/winpc/*.sh` 的註解是英文，違反「註釋用繁中」（票 02b 當時以「同目錄一致」保留）→ 三支 `.sh` 改繁中；`.ps1` 必須是純 ASCII，維持英文。
- Standards：`check.dart` 的 doc 漏了 codegen 與 schema 快照兩步 → 補上。
- Standards（判斷題）：bilibili 插件的 API header 在 `search` 與 `apiGet` 各寫一份 → 抽成 `browserHeaders(referer, origin)`，`dist/plugin.js` 重建；多餘的空行刪掉。
- Standards（判斷題）：`'${track.source}/${track.id}'` 在 `playback.dart` 拼三次 → `Track.logId`，`_describe` 刪掉（log 格式不變，`playback_test.dart` 既有的 `for songs/ok from …` 斷言守著）。
- Spec：「音訊後端」「作者」不在名詞表 → 擁有者確認後補進 `GLOSSARY.md`；`Track.author` 的註解改指名詞表。
- Spec：ADR 0038 結尾還寫「建好之前沒有閘門」→ 擁有者確認後改成指出三個閘門步驟。
- Spec：plan §1.2 把網路放在 `core/`，實作在 `plugins/src/` → 擁有者確認後照實作改，〈偏差與決定〉記一行（已封存在 `docs/archive/M0.md`）。
- Spec：票 05b 第 4 條、票 10 的 F4 那條、票 11 的「fixture 重播」那條打了勾但和現況不完全一致 → 三條各加一句註記（見下一節的理由），不改勾選。

沒修，歸屬在〈發現的歸屬〉：`placeholder_page.dart` 兩個錯誤 switch 與借用 `placeholder.search.*` 字串、三處 `two()` 補零、`plugin_assets_test.dart` 沒用 `pluginDirectories`、`host_network.dart`／`plugin_host.dart` 的 log 前綴、`Track.source` 裸字串、`resolveStream` 不檢查網域。

### spec〈驗收〉逐條對照

| spec〈驗收〉 | 證據 |
| --- | --- |
| 四個平台各自搜尋並播放出一首 B 站曲目（佔位畫面） | 票 11〈驗證〉四平台實跑；本票〈擁有者委託代測〉四平台再做一次，都讀回「播放中」且位置前進 |
| `check.dart` 完整版綠燈，含主要流程的 `integration_test` 四平台通過 | 下面〈乾淨 checkout〉兩次：`integration_test <平台>: integration_test/search_and_play_test.dart` 四平台都是 `ok` |
| 依賴規則測試、插件契約測試、打包產物檢查都在閘門裡，ADR 0038〈如何確認〉三條都有對應 | `test/architecture/dependency_rules_test.dart`、`test/plugins/plugin_contract_test.dart` 在 `test` 步驟（`tool/src/gate.dart` 的 `command('test', 'flutter', ['test'])`）；打包產物是 `plugin bundles (esbuild)`；ADR 0038 結尾已改成寫明這三處 |
| 五項實驗的結論已寫進 brief，plan §6 P2 已移到 §1.4、§2，P5 已刪除 | 票 03（K7、K11）、04（A4、W8、M8、K8、K17）、05（M9、M10、K18）、05b（K10、K21–K24）的事實都在 brief §18，決定寫進 brief §6、§11、§17；plan〈待決〉現在只剩 P1、P3，`grep -n 'P2\|P5' docs/plan.md` 沒有結果 |
| 舊版的 `ci.yml` 在 main 上綠燈 | main `94294d95` 的 run 43160831525 success：https://github.com/1morr/FMP/actions/runs/43160831525 （協調者提供；本票合併、push 後由協調者再確認一次） |
| 擁有者在四個平台各親手試一次 | **沒有達成，改為代測**：擁有者 2026-11-12 不在電腦前，委託 agent 代測，見〈擁有者委託代測〉。這條不算擁有者親試 |

### 乾淨 checkout

`git worktree add --detach <暫存目錄>/clean-m0 94294d95`（開工時的 HEAD），在 `app/` 裡 `flutter pub get && dart run tool/check.dart`，退出碼 0：

```text
ok   i18n (slang)
ok   codegen (build_runner)
ok   format
ok   analyze
ok   test
ok   schema snapshot (drift)
ok   doc gate
ok   build macos
ok   build ios
ok   build android
ok   lock shared devices
ok   build windows
ok   integration_test macos: integration_test/app_test.dart
ok   integration_test macos: integration_test/search_and_play_test.dart
ok   integration_test ios: integration_test/app_test.dart
ok   integration_test ios: integration_test/search_and_play_test.dart
ok   integration_test android: integration_test/app_test.dart
ok   integration_test android: integration_test/search_and_play_test.dart
ok   integration_test windows: integration_test/app_test.dart
ok   integration_test windows: integration_test/search_and_play_test.dart
ok   unlock shared devices
ok   plugin bundles (esbuild)
EXIT 0
```

code-review 的修正改到 `app/`，所以在修正後的 commit 另開乾淨 checkout 重跑。

第二次（`6beb093b`）`FAIL build windows` 與兩個 `FAIL integration_test windows`，查出兩個閘門的 bug，都已修：

- `sync.sh` 在 `winpc` 沒有 `C:\fmp-wt` 時失敗：代測完照 plan §2 的清理刪掉整個工作樹，下一次同步的 `Remove-Item -Recurse -Force C:\fmp-wt\app -EA SilentlyContinue` 對不存在的路徑仍讓 PowerShell 以 1 結束，`set -e` 讓 `sync.sh` 不印任何東西就中止。repro：`ssh winpc '…; Remove-Item … -EA SilentlyContinue'` 在 `app` 不在時 exit 1、在時 exit 0。改成先 `Test-Path`；修後兩種情況都 exit 0（`efc9fe4f`）。之前沒遇到是因為以前的 session 從沒照 plan 清掉過工作樹。沒有自動測試：要連 `winpc` 才測得到，下面第三次閘門就是在刪掉 `C:\fmp-wt` 之後跑的。
- 閘門讀 `winpc` 的 log 失敗時只印 `FormatException: Unexpected extension byte`：`ProcessShell.capture` 的 stderr 用 UTF-8 嚴格解碼，`winpc` 回的是 cp950 的錯誤訊息，解碼例外蓋掉了帶指令與退出碼的 `ProcessException`。stderr 改成和 stdout 一樣寬鬆解碼；`test/tool/steps_test.dart` 補一條 cp950 stderr 的測試，修前紅（`FormatException`）、修後綠（`7bc0e1a5`）。

第三次起在 `7bc0e1a5`，見下一節。

### 乾淨 checkout（最終 commit `7bc0e1a5`）

每次都是新的 `git worktree add --detach`，`flutter pub get && dart run tool/check.dart`。macOS、iOS、Android 與 quick 各步四次全是 `ok`；Windows 每次都紅，原因都是 plan §2〈`winpc` 的 Dart 偶發當掉〉那類原生工具存取違規：

| 次 | Windows 的結果 | 原因（`app/build/winpc/*.log`） |
| --- | --- | --- |
| 3 | `ok build windows`（這次是在刪掉 `C:\fmp-wt` 後跑，`sync.sh` 的修正生效）；`FAIL integration_test windows: app_test.dart`；`ok … search_and_play_test.dart` | `flutter test -d windows` 建置時 `Build process failed`，沒有 `-v` 看不到細節，事件記錄沒有當掉紀錄 |
| 4 | `FAIL build windows`；兩個 Windows integration_test `ok` | `linking with link.exe failed: exit code: 0xc0000005`（連結 fjs） |
| 5 | `FAIL build windows`；兩個 Windows integration_test `ok` | `error MSB6006: "CL.exe" … -1073741819`（`0xC0000005`） |
| 6 | `FAIL build windows` 與兩個 Windows integration_test | build_runner 的 Dart VM `===== CRASH =====`、`ExceptionCode=-1073741819`，`exit codegen=78`，沒產生 `database.g.dart`，後面跟著編譯失敗 |

第 4 次的完整輸出（第 5 次相同）：

```text
ok   i18n (slang)
ok   codegen (build_runner)
ok   format
ok   analyze
ok   test
ok   schema snapshot (drift)
ok   doc gate
ok   build macos
ok   build ios
ok   build android
ok   lock shared devices
FAIL build windows
ok   integration_test macos: integration_test/app_test.dart
ok   integration_test macos: integration_test/search_and_play_test.dart
ok   integration_test ios: integration_test/app_test.dart
ok   integration_test ios: integration_test/search_and_play_test.dart
ok   integration_test android: integration_test/app_test.dart
ok   integration_test android: integration_test/search_and_play_test.dart
ok   integration_test windows: integration_test/app_test.dart
ok   integration_test windows: integration_test/search_and_play_test.dart
ok   unlock shared devices
ok   plugin bundles (esbuild)
EXIT 1
```

Windows 的每一步在這四次裡都至少通過一次（第 3 次 `build windows`；第 4、5 次兩個 integration_test，它們各自重建一次 Windows App）。擁有者 2026-11-12 看過這些結果，同意照實記錄後關票（〈偏差與決定〉記一行）。協調者轉達 `winpc` 今天又藍屏兩次；檢查 `winpc` 硬體（Windows 記憶體診斷要重開機、擁有者在場）記成 M1 開工前的待辦（progress.md 與 plan §5.3）。

### 發現的歸屬

「延後」的已寫進 plan §5.3、§5.4 的〈M0 留下的〉（擁有者 2026-11-12 確認清單）。

| 出處 | 發現 | 歸屬 |
| --- | --- | --- |
| 01 | 依賴規則抓不到的繞法：識別碼先存常數、`startsWith`、查表 | 不做：仍靠 code review；`lib/` 現在沒有這些寫法，硬掃會誤判一般字串 |
| 01 | `defaultTargetPlatform` 要不要算「判斷平台」 | 延後 M1（照稿切版前定，plan §5.3） |
| 01 | 要不要改用 `material_ui` | 延後 M1（照稿切版前定，plan §5.3） |
| 01 | `_handwrittenDartFiles` 與 `readLibSources` 走目錄的邏輯相似、`_milestoneTable` 的 null 兩用、播放器套件出界的規則名 | 不做：分屬 tool 與測試、各只有一個呼叫端 |
| 02 | quick 失敗仍照跑四平台；平台用字串；`C:\fmp-wt` 寫在多處；`_Winpc._task` 的成組參數 | 不做：理由見票 02（`.ps1` 必須是獨立的純 ASCII 腳本，四個平台只有一個模組用） |
| 02b | Ctrl-C 時指令收到兩次 SIGINT；pid 重用；`lock_guard.sh` 註解維持英文 | 前兩條不做（無害、已不適用）；第三條本票改成繁中（修掉） |
| 03 | 預編譯庫沒核對版本；flutter_js 的門檻不一致；沒量 await 後的迴圈 | 不做：不影響選擇，README 已註明 |
| 04 | `run.sh` 讓 macOS 也能 release | 不做：一行，換版本重量時可能用到 |
| 04 | 給 M2 登入票的設定清單、CocoaPods（K17） | 延後 M2（plan §5.4） |
| 05 | #1139 的狀態寫三處 | 不做：各自的上下文需要 |
| 05 | 沒測 `flutter_media_session`、channel 版的遠端封面、release | 不做：選了 audio_service；改用 channel 時才需要（plan §7 已有退路） |
| 05b | 實驗程式的 Repeated Switches、尾碼規則分散、`Shot` 重複 | 不做：實驗程式可丟棄，不進 `app/` |
| 05b | `DESIGN.md` standard 玻璃模糊 16／18 | 延後 M1（plan §5.3） |
| 05b | 驗收第 4 條手機幀時間量不到 | 不做（已在 plan §7：里程碑量效能時用實機或 GPU 加速的模擬器量）；票 05b 那條加註記 |
| 06 | 遮不到的音源專屬名稱（`SESSDATA=` 單獨出現等） | 延後 M2（plan §5.4） |
| 06 | 網易雲的串流簽名在路徑裡 | 延後 M1（plan §5.3） |
| 06 | uncaught error 沒接進 log | 延後 M1（plan §5.3） |
| 06 | 寧可多遮的副作用、`Log` 的注入方式、Android 舊檔 | 不做：多遮是刻意的取捨；`Log` 的注入票 08 已用 `logProvider` 定了；舊檔輪替時自然刪掉 |
| 07 | v1 時 migration 測試 0 條、資料完整性測試沒有骨架 | 不做：第一次升 schema（M3）時 drift_dev 會產生，plan §3 已寫流程 |
| 07 | 資料庫名稱與路徑分三處、`jni` FFI 插件、integration_test 用真實 dev 資料檔 | 不做：只有一個資料庫；`jni` 閘門已建過；首次建立由單元測試涵蓋 |
| 08 | 逾時的競態、建引擎失敗的 future 被快取 | 延後 M1（plan §5.3；寫得出會紅的測試再修） |
| 08 | 宿主網路在 `plugins/src/` | 修掉：plan §1.2 照實作改（擁有者確認） |
| 08 | 「有 `manifest.json` 就是插件」寫在 JS、閘門、App 三處 | 不做：三個執行環境共用不了 |
| 08 | 插件 id 用裸 `String` | 延後 M1（plan §5.3，佇列與持久化前定） |
| 08 | `Track.author` 不在名詞表 | 修掉：補「作者」（擁有者確認） |
| 09 | 重播不比對 header 與 body | 不做：由 `bilibili_plugin_test.dart` 的單元測試守 |
| 09 | WBI 參數讓重播對不上 | 延後 M1（plan §5.3，第一個用到 WBI 的插件能力時） |
| 09 | `realHttpClient()` 沒有限制只在 `live` 測試用 | 不做：只有 `liveRecording()` 一個呼叫端，`live` 測試是手動跑 |
| 09 | `pluginDirectories` 又一份、`Log.open` 的 setUp 重複、plan §3 寫進格式 | 不做：`plugin_assets_test.dart` 要在 `dist/` 缺檔時回報缺什麼，`pluginDirectories` 會直接讀檔失敗；其餘沿用既有寫法 |
| 10 | 佔位頁兩個錯誤 switch、借用 `placeholder.search.*` 字串 | 不做：佔位頁 M1 整頁換掉（本票 code-review 也指出，同理） |
| 10 | 宿主沒有 `pluginFor` | 修掉：票 11 已搬進宿主 |
| 10 | F4 那條勾選和現況（多了瀏覽器 UA） | 修掉：票 10 加註記；F4 已在票 11 依 F22 改寫，仍不帶憑證 |
| 11 | 「音訊後端」不在名詞表 | 修掉：補詞（擁有者確認） |
| 11 | `AudioBackendError.==` 用 `toString()`；`track`＋`stream` 成組傳 | 不做：只用來判斷狀態有沒有變；量小 |
| 11 | `classifyMpvLog`、mpv 設定、`audio_session`、403 重解析與降音質 | 延後 M1（plan §5.3；重解析與看門狗本來就在 §5.3 的「串流過期重解析、失敗處理」） |
| 11 | octet-stream 在 Apple 平台 | 延後 M1（plan §5.3） |
| 11 | 「fixture 重播」那條實際用 `FakeHttp` | 不做：fixture 檔在主機的 `plugins/<id>/fixtures/`，沒打包進 App，iOS、Android 上的 integration_test 讀不到；串流網址也必須改指本機假 CDN，不能用錄下的網址。插件請求的 fixture 重播由主機上的契約測試做。票 11 那條加註記 |
| 12 | `resolveStream` 不比對 manifest 網域、header 照單全收 | 延後 M1（媒體網域）、M2（擋憑證 header），擁有者確認 |
| 12 | 三處 `two()` 補零、log 前綴重複 9 次 | 不做：兩處在 M1 換掉的佔位頁；log 前綴是一行字串，抽 helper 換不到什麼 |
| 12 | `plugin_assets_test.dart` 沒用 `pluginDirectories` | 不做：同票 09 |
| 12 | `Track.source` 裸字串（`TrackRef`） | 延後 M1（同票 08） |
| 12 | 刪掉依賴規則或契約測試的檔案，閘門不會紅 | 不做：兩個測試在 `test/` 的固定位置，刪檔會出現在 diff 與 code review |

### 擁有者委託代測（2026-11-12）

擁有者不在電腦前，委託 agent 在四個平台照同樣步驟各做一次：搜一次、點一首、暫停、繼續（匿名）。**這不是擁有者親試**；agent 聽不到聲音，「在播」以畫面的播放狀態、位置前進與 App 的 log 為證。App 是 `6beb093b` 的 debug 建置；碰裝置時這個 worktree 在背景持共用裝置鎖，做完放掉，`winpc` 的 `C:\fmp-wt` 已清掉。截圖只留在本機暫存目錄。

**聲音沒有經過人耳確認**：代測只看畫面的播放狀態、位置與 log。擁有者回來後要在四個平台各親耳聽一次（記成 M1 開工前的待辦，progress.md 與 plan §5.3）。

| 平台 | 搜尋 | 播放（畫面讀回） | 暫停 → 繼續 |
| --- | --- | --- | --- |
| macOS | `lofi`，列出 B 站結果 | 點第一首「今年的第一场雪…Snow vibe Lofi music」（BedroomSonicClub，45:20）：先「載入中…」約 15 秒，之後「播放中 0:24 / 45:19」 | 暫停後 0:38，4 秒後仍 0:38；繼續 5 秒後「播放中 0:43」 |
| iOS 模擬器（iPhone Duo） | 模擬器鍵盤是注音，`lofi` 被打成 `ㄠ ㄟ ㄑ ㄛ` 送出（log 的 keyword 看得到），搜尋成功但結果無關。為了不多打一次匿名搜尋，直接用這批結果 | 點第一首「【Hi-Res无损】DOUDOU《嗵嗵》歌词纯享版…」：「播放中 0:18 / 4:23」 | 暫停後 0:25，5 秒後仍 0:25；繼續 5 秒後「播放中 0:30」 |
| Android 模擬器（`Medium_Phone_API_37.0`） | 鍵盤是速成，第一次打字停在組字區、沒有送出（log 沒有請求）；切到英文鍵盤後搜 `lofi`，試完切回速成 | 點第一首（同 macOS）：「Playing 0:22 / 45:19」 | 暫停後 0:32，5 秒後仍 0:32；繼續後「Playing 0:40」 |
| Windows（`winpc`） | `shot.ps1 -Type lofi` | `-Click "200,262;48,244;400,40;48,244" -ClickWait 15`：第 1 張「播放中 0:14 / 45:19」 | 第 2 張暫停 0:14，第 3 張（再過 15 秒）仍 0:14；第 4 張繼續「播放中 0:29」；`foreground_is_fmp_*` 全是 True，`exited_after_close=True`，`app-stderr.txt` 只有 Impeller 那一行 |

log 摘錄（四平台相同的形狀，以 Windows 為例）：

```text
2026-11-12T06:08:36Z DEBUG plugin bilibili: GET https://api.bilibili.com/x/web-interface/search/type?search_type=video&page=1&keyword=lofi -> 200 in 429ms
2026-11-12T06:08:45Z DEBUG plugin bilibili: GET https://api.bilibili.com/x/player/pagelist?bvid=BV1bbx163EcX -> 200 in 82ms
2026-11-12T06:08:45Z DEBUG plugin bilibili: GET https://api.bilibili.com/x/player/playurl?bvid=BV1bbx163EcX&cid=43204215688&fnval=16 -> 200 in 72ms
```

四平台都沒有 `Playback failed` 或 `Playback stalled`。

觀察（沒有處理）：

- macOS 從點下到出現「播放中」約 15 秒（解析只花 150 ms，其餘是 AVPlayer 載入 45 分鐘的 m4a）。沒到「緩衝超過 15 秒」的警告門檻，log 沒有 `stalled`。M1 的預載與看門狗會碰到這段。
- macOS 用 `osascript -e 'quit app "FMP Dev"'` 結束時回 `-128`（使用者取消），但 App 隨後確實結束（`pgrep` 確認）。推測是票 11 讓 App 結束前先釋放後端、延後結束，Apple Event 因此收到取消；沒有查證。
- 模擬器的輸入法怪癖寫進 plan §2〈其他已知怪癖〉。
