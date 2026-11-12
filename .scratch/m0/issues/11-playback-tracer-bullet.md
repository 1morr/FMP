# 11: 播放出聲

**What to build:** 在佔位搜尋頁點一首 B 站曲目，四個平台都播放出聲，並能暫停、繼續。宿主有自己的音訊後端介面，Android、iOS、macOS 用 just_audio 實作，Windows 用 media_kit 實作；串流的 header 照插件回傳的帶上。主要流程（搜尋到播放）有一條 `integration_test`，四平台都在完整閘門裡跑。這張票做完就是 M0 的 tracer bullet。

讀：brief §6、事實 K1、K3、K4、M5、W3、W4、W5、I4；plan §1.2、§1.3、§1.4、§2、§3；票 10 的 Comments；spec〈共同規則〉、〈驗收〉

**Blocked by:** 10

**Status:** ready-for-agent

- [ ] 音訊後端介面用 `mattpocock-skills:codebase-design` 設計，只涵蓋 M0 要的載入、播放、暫停、狀態與錯誤；兩個實作在 `playback/backends/`（plan §1.3 的例外，擁有者 2026-11-11 決定），平台判斷只在 `platform/`。
- [ ] 帶 header 播放：Apple 平台照事實 M5 重驗 B 站 CDN 回的 Content-Type 與 header 做法；Windows 照事實 K4。重驗結果更新 brief §18。
- [ ] 播放錯誤轉成錯誤分類並寫 log；長度為零或一直 buffering 的情況至少有記錄（事實 W4），完整的看門狗留給 M1，記到票的 Comments。
- [ ] 單元測試用 fake 後端測播放流程；零聯網。
- [ ] `integration_test`：搜尋、點一首、進入播放狀態，用 fixture 重播與不連網的音訊來源，四平台在 `check.dart` 完整版通過。
- [ ] 四平台實跑：搜一次、播一首，確認出聲並能暫停、繼續（macOS、Windows 本機聽；模擬器以播放狀態與進度前進為證），讀回畫面。
- [ ] 依賴版本寫進 plan §1.4。
- [ ] Windows 上的原生崩潰要分清來源再處理：建置階段 `frontend_server` 當掉（MSB8066，plan §2 記的 `winpc` 不穩）可以重跑；App 執行中的崩潰（崩的是 App 自己的行程，例如事實 W5 的 media_kit 同時 dispose）一律當產品 bug 查，不能重跑放過。判斷依據（log、crash dump 的模組名）記在票的 Comments。
- [ ] `dart run tool/check.dart` 完整版綠燈。

## Comments

### 做法

- 音訊後端介面（`playback/audio_backend.dart`，用 `mattpocock-skills:codebase-design` 設計）：`state`、`states`、`load(AudioStream)`、`play()`、`pause()`、`dispose()`。狀態照 just_audio 的 `ProcessingState` 加上 `failed`，錯誤是 `AudioBackendError(錯誤分類, detail)`。兩個實作加上測試的 fake，接縫是真的。
  - 分工：原生錯誤怎麼轉成錯誤分類只有實作知道，所以由實作轉；寫 log 由呼叫端做。
  - 約定：`load` 開不了時先把狀態改成 failed 再丟錯；被下一次 `load` 取代時直接回來，不丟錯。
- 兩個實作在 `playback/backends/`，依平台挑在 `platform/audio_backend.dart`。`main` 把 `audioBackendProvider` override 成它，同 `logProvider` 的做法；`playback/` 不 import `platform/`。共用的狀態保管在 `backends/backend_states.dart`：合併事件、沒變不發、失敗後黏住直到下一次載入。
- 播放（`playback/playback.dart` 的 `Playback`）：用 `host.pluginFor(source)` 找插件解析串流，交給後端載入並播放，再把後端狀態轉成 `PlaybackState`（解析中、載入中、緩衝中、播放中、已暫停、播完、失敗）。
  - 票 10 Comments 說「播放也要找插件時搬進宿主」，`pluginFor` 已搬進 `PluginHost`。
  - 連點時只播最後一首。
  - 後端在第一次播放時才建：佔位頁一開就 watch 播放狀態，原本會在啟動時就開原生播放器。
- header：
  - just_audio 設 `useProxyForRequestHeaders: false`，由原生播放器帶 header（事實 K25）。預設的 Dart proxy 會繞過宿主網路層，也會被測試的零聯網防線擋。
  - media_kit 用 `Media.httpHeaders`（事實 K4）。
  - 四平台都由 integration_test 的假 CDN 證明 header 帶到了。
- 錯誤分類：
  - just_audio：ExoPlayer 的 source、remote 錯誤，以及 `NSURLErrorDomain`（-1000 到 -3999），算網路。renderer 與 AVFoundation 的 -11828、-11821 算不支援。其他算解析失敗。
  - mpv：照 media_kit 轉發的那幾類，再加上 `ao`。
  - CDN 回 403：Android 被壓成 `code 0: Source error`（事實 K3），Apple 是 `-1102`，兩邊都落在網路。真正的原因要看 logcat 或系統 log。
  - 對照表在 `test/playback/backend_errors_test.dart`。
- 失敗的 log 一行寫明錯誤分類、原生代碼與訊息、曲目，以及 CDN 主機（不記簽名網址），例如 `Playback failed: NetworkError (code -1102: …) for bilibili/BV… from upos-…`。
- 看門狗只做記錄（事實 I4、W4）：
  - 長度回報為 0 時寫一筆 warning。
  - 載入或緩衝超過 15 秒（`stallWarningAfterProvider`）寫一筆 `Playback stalled`。iOS 實跑真的記到一次（見下）。
  - 完整的看門狗（重試、降音質、跳下一首，brief §6）留給 M1。
  - media_kit 載入等到長度出現、mpv 報錯或 20 秒逾時；逾時時長度還是 0，就當成一直在緩衝。
- 佔位頁：點一首就播。面板顯示狀態、進度、暫停或播放鈕，以及串流的音質、到期時間與遮蔽過的網址。播放失敗時也顯示這些，方便看是哪個 CDN。新字串補齊三語。
- integration_test：`plugin_search_test.dart` 改名並擴充成 `search_and_play_test.dart`，做搜尋、點一首、播放、進度前進、暫停、繼續。
  - 沿用舊檔會讓原生播放器真的去連 `cdn.example.com`：原生播放器不經 `HttpOverrides`。
  - 串流網址改指向 `test/support/local_audio_server.dart`：127.0.0.1 上的假 CDN，回產生出來的無聲 WAV（閘門跑時不出聲），支援 Range（AVPlayer 需要）。少了 Referer 或瀏覽器 User-Agent 就回 403，像真的 B 站。
  - `gate_test.dart` 的步驟清單跟著改名。
  - 本機 http 的放行情況：macOS 與 iOS 模擬器不加 ATS 例外就播得了 `http://127.0.0.1`（事實 M11）。Android API 37 模擬器不加 network security config 也播得了（事實 K27），所以沒有改 manifest。
- 依賴：just_audio 0.10.6、media_kit 1.2.6、media_kit_libs_windows_audio 1.0.9，帶進 audio_session 0.2.4，已寫進 plan §1.4。plan §2 各平台的套件與 §3 的主要流程測試已補。
- `tool/winpc/shot.ps1` 的 `-Click` 可以給好幾個座標（`x,y;x,y`），每下之後另存一張截圖，plan §2 已補。用來在 Windows 上看暫停與繼續。

### M5 重驗與偶發的 403（事實 F22、M11）

- 重驗 M5（`scripts/experiments/bilibili-cdn-headers/probe.sh`，匿名）：
  - B 站 CDN（`upos-hz-mirrorakam.akamaized.net`）回 `Content-Type: video/mp4`，Range 回 206，不是 M5 擔心的 `application/octet-stream`。
  - AVPlayer 在 macOS 與 iOS 模擬器都播得出來。
  - M5 其餘幾條（WebM/Opus、FLV、`http://` 網域的 ATS、octet-stream 打不開）M0 用不到，沒重驗，標記留著。驗過的部分寫成新的 M11。
- 偶發的 403：第一次四平台實跑時，iOS 模擬器第一首失敗（AVPlayer `-1102`），Android 模擬器第一首也失敗（logcat：`InvalidResponseCodeException: Response code: 403`）。macOS 與 iOS 重試都正常。
  - 查的過程：`hosts.sh` 對 `BV14gQeBNEix` 的主網址與 `backupUrl` 各試四種 header。ExoPlayer 與 AppleCoreMedia 的 User-Agent 都回 403，瀏覽器的回 206；`bilivideo.com` 那台不帶 Referer 也是 403。
  - 其他影片的網址不擋，所以看起來是偶發的。舊版的媒體請求一律帶瀏覽器 UA（`legacy:lib/data/sources/source_http_policy.dart:8-10,82-84`），事實 F4 原本寫「只需要 Referer」是錯的，已改。
  - 修法：先讓 integration_test 的假 CDN 拒絕非瀏覽器的 UA，macOS 紅了（AVPlayer 用自己的 UA）。再讓 bilibili 插件的媒體 header 加上瀏覽器 UA（`MEDIA_HEADERS`），四平台轉綠。
  - 三個播放器都會用 header 裡的 User-Agent（事實 K25、K4）。
  - 回歸：最終實跑時，Android 點的就是先前 403 的 `BV14gQeBNEix`，這次正常播放。
- iOS 那首（`BV1DXYCzrENa`）修正前重試時，約 25 秒才開始播，log 記到 `Playback stalled: buffering for over 15000 ms`。修正後同一首 5 秒內就在播。原因沒查清楚，記成事實 I9。
- 這次的實驗共打了：probe 兩次（各一組 pagelist 加 playurl）、hosts 一次，CDN 共 10 個 1 KB 的 Range 請求，都是匿名。

### Windows 原生崩潰的判斷

- 這張票在 `winpc` 沒遇到 App 執行中的崩潰，也沒遇到建置階段的 `frontend_server` 崩潰（MSB8066）。
- 判斷依據：
  - 四次手動跑 integration_test，每次 `test.log` 都有 `exit test=0` 與 `=== done`。
  - 建置的 `build.log` 每個階段的退出碼都是 0。
  - 實跑時 App 的 log 沒有 error，`shot.ps1` 關 App 前行程都還在（`exited=False`）。
- 只有一個播放器，`dispose` 只在 provider 釋放與 integration_test 收尾時各做一次（事實 W5）。

### 四平台實跑（最終程式碼，合併 main 之後）

都是匿名，每個平台搜一次、播一首，持共用裝置鎖；截圖留在暫存目錄。我聽不到聲音，所以出聲的證據是播放狀態、進度前進，以及暫停時進度停住。macOS 另有系統的音訊輸出紀錄：`pmset -g assertions` 在播放開始時出現 `coreaudiod` 的 `audio-out`。擁有者親手聽在票 12。

- macOS：搜 `lemon`，點「【4K顶级画质】米津玄师《Lemon》…」（mp4a.40.2 · 190 kbps）。播放中 0:06 → 按暫停，3 秒內停在 0:06 → 按播放，0:10。
- iOS 模擬器：鍵盤是注音（同票 08、10），選「熬過運用」後搜尋。點「《熬过风雪又一年》…」（217 kbps），5 秒內播放中。0:12 → 暫停，停在 0:12 → 繼續，0:17。
- Android 模擬器：速成輸入法選「被一例」後搜尋。點第一首（`BV14gQeBNEix`，107 kbps）：播放中 → 暫停，停在 0:25 → 繼續，0:29。模擬器的音訊比實際快約 1.7 倍（plan §2）。
- Windows（`winpc`）：`shot.ps1 -Type lemon -Click "200,262;48,244;400,40;48,244"`，`foreground_is_fmp_*` 全是 True。點「在百万豪装录音棚…【Hi-res】」（193 kbps），播放中 0:05 → 暫停，6 秒後仍停在 0:05 → 繼續，0:11。

### code-review（b9cac98b 起）

已處理（`96563b04`）：
- Standards 與 Spec 兩軸都提到 media_kit 連續載入時，舊的那次要等 20 秒逾時，之後還會蓋掉新那首的狀態。改成每次載入取代上一次（以 false 完成），逾時與報錯都檢查是不是自己那次。
- just_audio 的 `_loading` 布林值有競態，改成世代計數加上未完成的載入數。
- mpv 在 `open` 期間報錯會成為沒人處理的錯誤：等待在 `open` 之前就先接上。`play()` 的 Future 也接住。
- 後端的 `play()` 丟錯時，`Playback` 沒接。
- 載入失敗後 stall 計時器沒取消。
- 載入中會顯示上一首的位置。
- 被取代的載入原本丟一個假的 `ParseFailure`，改照介面約定直接回來。
- 真的後端先發 failed 再丟錯，載入失敗會記兩次 log。fake 原本發的是 idle，所以測試沒抓到。fake 改照真的後端發 failed，測試斷言只記一次。
- `BackendStates` 補了單元測試。
- 引用的事實 K25、F22 等已寫進 brief。

未處理：
- 「音訊後端」不在 `GLOSSARY.md`（brief §6 與 plan 都這樣叫）。補詞要擁有者確認，留給票 12 一起問。
- `AudioBackendError.==` 用錯誤分類的 `toString()` 比較，因為 `AppError` 沒有定義相等。只用來判斷狀態有沒有變，可以接受。
- 佔位頁的兩個 `_errorText` 各自 switch 錯誤分類。佔位頁到 M1 整頁換掉，沒有收斂。
- `track` 加 `stream` 在 `_fail` 與 log 之間一起傳（Data Clumps）。量小，沒抽型別。
- `classifyMpvLog` 把所有 `cplayer` 的 error 都當成失敗。mpv 若有不致命的 `cplayer` error，畫面會顯示失敗但聲音還在播。這和 media_kit 自己的轉發一致，等 M1 遇到再收窄。
- CDN 若回 `application/octet-stream`，Apple 平台能不能播，沒有測試涵蓋（M5 剩下的部分）。B 站實測回 `video/mp4`。YouTube 在 M1 要重驗。

### 留給 M1

- media_kit 的 `vid=no`、`prefetch-playlist=yes` 等 mpv 設定（事實 K4）沒設：M0 只播一首純音訊。
- just_audio 沒設定 `audio_session`：背景播放、中斷處理在 M1。
- 403 時重新解析、換 `backupUrl`、降一級音質重試（brief §6）都在 M1。
