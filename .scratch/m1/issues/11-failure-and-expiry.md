# 11: 失敗處理、串流過期重新解析與看門狗

Status: done
Blocked by: 06、07
讀: brief §6、§13；architecture〈快取〉；事實 F5、I4、K4、K25、K26、W3、W4；M0 票 06、11 的 Comments；spec〈共同規則〉

## What to build

播放失敗時照 roadmap 定的順序處理：重新解析一次（含 CDN 回 403）→ 跳下一首 → 連續 3 首失敗就停止並用 Toast 提示（先降一級音質在 M2）。串流照 ARCHITECTURE〈快取〉在過期前重新解析：要用網址前（載入、暫停後繼續、seek）離過期不到 2 分鐘就先重新解析。看門狗：一直緩衝超過門檻就當成失敗走同一條路（M0 只記錄警告）。

M0 留下的一起做：
- media_kit 的 mpv 設定：`vid=no`、`prefetch-playlist=yes` 等（事實 K4）；`classifyMpvLog` 只把致命的 `cplayer` 錯誤當失敗。
- just_audio 接 `audio_session`。
- 未捕捉的錯誤（`FlutterError.onError`、`PlatformDispatcher.onError`）寫進 log。

## 驗收

- [x] 失敗處理有測試：重新解析一次、403 重新解析、跳下一首、連續 3 首停止並提示、成功一首後計數歸零。
- [x] 過期前重新解析有測試（假的時鐘）：離過期不到 2 分鐘時先解析；沒給有效期時不預先解析。
- [x] 看門狗有測試：緩衝超過門檻走失敗處理。
- [x] `classifyMpvLog` 只把致命錯誤當失敗，有測試；mpv 設定與 `audio_session` 已接上。
- [x] 未捕捉的錯誤寫進 log，有測試。
- [x] 四平台實跑：用壞掉的串流（假 CDN 回 403）觸發一次重新解析，讀回 log 與畫面。（Windows 依擁有者 2026-11-18 的決定跳過，macOS、iOS、Android 收，見 Comments 的「Windows 跳過」）
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。（`--skip-windows`，同上）

## Comments

### 做法

- 重新解析在 `Playback`（`playback/playback.dart`）：拿到串流之後的失敗（後端開不了、播放中出錯、看門狗）重新解析一次、從失敗的位置接著，原本在播才接著播；重新解析中不報失敗。插件解析本身失敗直接報。這一次 `play` 只有一次額度，重新解析後順利播了 30 秒額度還回來。過期前重新解析：暫停後繼續與 seek 時離 `expiresAt` 不到 2 分鐘就先解析（`playbackClockProvider` 可換假時鐘）；載入一律用剛解析的串流，預載（票 12）要自己在載入前檢查。
- 看門狗在同一處：要出聲卻沒聲音，還沒出過聲超過 45 秒、出過聲後緩衝超過 15 秒就當成串流壞掉（`stallTimeoutsProvider`，事實 F25）。暫停中的緩衝不管。開頭最壞要等 45 秒逾時、重新解析後再等一輪（近 90 秒）：這段時間迷你播放器與播放膠囊照解析中、載入中顯示，上一首、下一首照佇列可按，使用者隨時能自己跳；第一次逾時寫 `WARNING Playback stalled: starting for over 45000 ms` 與 `INFO Resolving the stream again`，不另跳提示。
- 給票 12（預載與切歌延遲）：預載把出聲時間壓下來之後，用 `start_time_run.dart` 四平台重量，回頭調低開頭門檻（`stallTimeoutsProvider.starting`，事實 F25 與 `docs/research/start-time-2026-11-18.md` 一起改）。
- 跳下一首在 `QueueController`：最後的失敗由它決定跳下一首、臨時曲目回佇列、連續 3 首停下或停在這首（沒有下一首、需驗證），結果放 `playbackFailureProvider`，提示層聽它出 Toast，不自己猜。開始播就歸零；使用者自己按下一首、上一首、點佇列、臨時播放也歸零。
- 提示：原因句沿用，跳過接「已跳下一首。」、臨時曲目接「已回到佇列。」、停下時前面加「連續 3 首都無法播放，已停止。」與「看佇列」；停在這首時照舊（可重試的有「重試」）。
- mpv：建 player 時設 `vid=no`、`prefetch-playlist=yes`（事實 K4），設完寫 log。`classifyMpvLog` 的 `cplayer` 只認三種讓這首播不下去的訊息與 fatal 級（事實 W13，讀 mpv 0.36 原始碼）。
- `audio_session` 改直接依賴，啟動時設成 `music()`（`platform/audio_session.dart`；Windows 沒有實作，不設），事實 K30。
- 未捕捉的錯誤：`app/uncaught_errors.dart` 接 `FlutterError.onError`（照舊交給原本的處理）與 `PlatformDispatcher.onError`（標成已處理），`main` 開好 log 後呼叫。
- 測試：`playback_test`（重新解析、403、暫停中出錯、額度還回來、過期、看門狗兩個門檻與正常的慢開頭）、`queue_controller_test`（跳過、403 跳過、連續 3 首、歸零、手動歸零、沒有下一首、需驗證、臨時曲目）、`playback_toast_test` 與 `now_playing_test`（三種提示、看佇列開佇列頁）、`backend_errors_test`、`uncaught_errors_test`；閘門加 `integration_test/stream_refresh_test.dart`（本機假 CDN 對第一次解析到的網址回 403），macOS 單跑過。

### 量測（看門狗門檻）

`integration_test/real_run/start_time_run.dart`，數字與量法在 `docs/research/start-time-2026-11-18.md`：四平台長片（3:11:49）開始載入到出聲 229–841 ms、34:06 那首 196–267 ms，出聲後 20 秒內緩衝最久 5 ms。先前觀察過 iOS 直接播長片 15–38 秒、macOS 45 分鐘檔約 15 秒，所以開頭門檻取 45 秒、中途 15 秒（舊版 bufferStarvation）。

### 實跑（重新解析）

`integration_test/real_run/refresh_run.dart`：匿名搜「lofi」、臨時播放第一首，第一次載入換成本機假 CDN（一律 403）的網址（`runFmp(wrapAudioBackend:)`），之後打真的 B 站。`13fdda45` 上 macOS、iOS、Android 綠，截圖與讀回在 `<暫存目錄>/refresh2/<平台>/`，`01-launch` 是啟動後沒動過視窗那張：

| 平台 | log | 畫面（`03-playing`） |
| --- | --- | --- |
| macOS | `Playback failed: ParseFailure (code -11849: Operation Stopped) for bilibili/BV1G9sZ6UEQw from upos-hz-mirrorakam.akamaized.net` → `Resolving the stream again` | 播放中 0:05 / 59:32，沒有提示 |
| iOS 模擬器 | 同上（`-11849`） | 播放中 0:05 / 59:32，沒有提示 |
| Android 模擬器 | `NetworkError (code 0: Source error)` → `Resolving the stream again` | Playing 0:05 / 59:32，沒有提示 |
| Windows | 沒跑成，見〈winpc〉 | |

每次啟動都有 `Audio session configured for music`。log 記的 CDN 主機是插件給的那條（網址是在後端裡換掉的）。

### winpc

- 第一次 Windows 量測紅在建置的 `MSB8066`（`flutter_assemble`）。fjs 的 Rust 產物只在 `C:\fmp-wt\app\build\…\cargokit_build`，每次同步都整個刪掉，pub cache 裡沒有 `target`，等於每次都是乾淨的 Rust 建置；持鎖重跑一次就過，量到上面的 Windows 數字。
- 2026-11-18 17:47 藍屏：BugCheck `0x00000050`（PAGE_FAULT_IN_NONPAGED_AREA，和 15:59 那次同一種），minidump `C:\WINDOWS\Minidump\111826-19703-01.dmp`，系統記的上一次意外關機在 17:19。當時 Mac 端剛跑完，Windows 的 refresh、persist、restore 都紅。
- 照協調者的規則持鎖重跑一次：三段都在建置前就斷，排程工作 `fmpbuild` 一啟動就回「就緒」、沒有 build.log。`query session` 的 console 沒有使用者、`LogonUI` 在跑：重開後停在登入畫面，排程工作跑不起來，要擁有者登入。沒有再重試。

### 驗證

完整閘門（`dart run tool/check.dart`，`13fdda45`）：

```
ok   i18n (slang) … ok   doc gate tests（quick 全部 ok）
ok   build macos / build macos native tests / build ios / build android
ok   lock shared devices
FAIL build windows
ok   native tests macos
ok   integration_test macos／ios／android：app_test、queue_test、search_and_play_test、stream_duration_test、stream_refresh_test（15 步全 ok）
FAIL integration_test windows：上面五個都紅
ok   unlock shared devices
ok   plugin bundles (esbuild)
```

Windows 六步都是同一個原因：排程工作 `fmpbuild` 一啟動就「就緒」、沒有 `C:\fmp-wt\build.log`（winpc 藍屏重開後停在登入畫面，見〈winpc〉），不是程式的問題，也沒建置到程式。

Session 紀錄：2026-11-18 失敗處理（重新解析一次、跳下一首、連續 3 首停）、過期前重新解析、看門狗兩門檻（四平台量測定 45／15 秒）、mpv 設定、audio_session、未捕捉錯誤寫 log；mac、iOS、Android 實跑重新解析，Windows 因 winpc 藍屏後停在登入畫面沒跑成
決定：測試接縫五層：playback、佇列、提示 widget、classifyMpvLog 與未捕捉錯誤單元測試、閘門的 403 integration_test（協調者代答）（Agent 定）
決定：只有拿到串流後的失敗重新解析一次；插件解析失敗直接跳下一首；需驗證停在那首不跳（協調者代答）（Agent 定）
決定：提示沿用原因句，跳過接「已跳下一首。」、臨時曲目接「已回到佇列。」、停下時前加「連續 3 首…已停止。」與「看佇列」（協調者代答）（Agent 定）
決定：看門狗開頭 45 秒、中途 15 秒，照四平台實測與先前觀察取最慢再留餘裕，量測是協調者要的（事實 F25）（Agent 定）
決定：開頭門檻保留 45 秒、不為縮短而誤跳慢開頭；等待中照載入狀態顯示、可按下一首，第一次逾時只寫 log；預載後由票 12 重量調低（協調者代答）（Agent 定）
決定：重新解析的額度每次播放一次，重新解析後順利播 30 秒還回來，長片後段再壞還救得回來（Agent 定）
決定：暫停中出錯或看門狗觸發時，重新解析後照原本要不要播，不自己開始播（Agent 定）
決定：「成功一首」是進到播放中；停下或停在這首後、使用者自己點歌時，連續失敗也從頭算（Agent 定）
決定：臨時曲目播不了也算進連續失敗，第 3 首時停下、不回佇列（Agent 定）
決定：佇列的處理結果經 `playbackFailureProvider` 給提示層，提示不自己猜佇列做了什麼（Agent 定）
決定：mpv 只設 `vid=no`、`prefetch-playlist=yes`（事實 K4），舊版其他的緩衝與重連設定沒有事實，不搬（Agent 定）
決定：`cplayer` 只認讀 mpv 0.36 原始碼確認會中斷播放的三種訊息與 fatal 級，寫成事實 W13（Agent 定）
決定：`audio_session` 改直接依賴、啟動時設成音樂，Windows 不設；ARCHITECTURE〈主要依賴〉已列 0.2.4，不改（Agent 定）
決定：框架回報的未捕捉錯誤照舊交給原本的處理，非同步的標成已處理，都寫 error（Agent 定）
決定：`main` 拆出 `runFmp({wrapAudioBackend})` 給實跑驅動換後端，refresh_run 只讓第一次載入拿到假 CDN 的網址（Agent 定）
決定：解析中、載入中顯示開始的位置，重新解析時進度不跳回 0（Agent 定）
決定：量測情境播兩首、refresh_run 解析兩次，比 spec 的播一首多（Agent 定）
決定：Apple 把本機假 CDN 的 403 報成 -11849（歸成解析失敗），閘門測試只要求失敗一次、重新解析一次，不斷言分類（Agent 定）
變更：Added｜播放控制｜一首播不了時先重新取得串流再試一次（例如網址過期、CDN 拒絕），還是不行就跳下一首並提示「已跳下一首」；連續 3 首都播不了就停下，提示有「看佇列」
變更：Added｜播放控制｜串流快過期時，暫停後繼續與拖動進度會先重新取得網址，不會接著播就失敗
變更：Added｜播放控制｜一直緩衝不出聲（開頭超過 45 秒、播放中超過 15 秒）時當成播不了，照上面的方式處理
變更：Changed｜臨時播放｜臨時播放的曲目播不了時也先重試一次，還是不行才回到佇列，提示寫「已回到佇列」
變更：Changed｜播放控制｜重新取得串流時進度停在原處，不跳回 0:00
變更：Fixed｜播放控制｜Windows 上播放器不影響聲音的錯誤（例如不能拖動進度）不再被當成播放失敗
等使用者：winpc 17:47 藍屏（今天第四次）後停在登入畫面，Windows 的三段實跑（refresh、票 10 的 persist／restore）與閘門的 Windows 步驟都跑不起來。請擁有者登入 winpc；登入後下一個 session 持鎖重跑這三段與完整閘門。不處理的話「四平台實跑」「補驗票 10」「全部檢查綠燈」三條勾不了，票不能 done
決定：暫時跳過所有 Windows，照三平台收，補驗在票 20（使用者定）
決定：閘門加 `--skip-windows`：Windows 的步驟列成 SKIP 並註明原因、不算失敗，跳過寫在步驟上（`CheckStep.skipped`），其他步驟照跑（Agent 定）
Windows 跳過：以下只在 Windows 生效或只差 Windows 沒實跑，單元測試照常跑過，補驗時各看：① mpv 設定 `vid=no`、`prefetch-playlist=yes`（`media_kit_backend.dart` 經 `NativePlayer.setProperty`）：log 有 `mpv options set: …`、沒有設定失敗的 warning，播放照常出聲；② `classifyMpvLog` 在真 mpv 0.36 上的分類（事實 W13）：播放中拖動進度等不致命的 `cplayer` 訊息不出現 `Playback failed`、不跳歌，假 CDN 回 403 時 log 有一次 `Playback failed: <分類>` 並記下實際分類；③ 重新解析的實跑（`dart run tool/real_run.dart -d windows integration_test/real_run/refresh_run.dart`）：第一次載入被拒、log 有 `Resolving the stream again: bilibili/…`、接著出聲、沒有無法播放的提示，看啟動後不動視窗的截圖；④ `audio_session` 在 Windows 不設：log 沒有 `Audio session configured for music`、也沒有因它而起的 `Uncaught error`；⑤ 未捕捉錯誤寫 log 在 Windows 的 release／debug 建置照常：啟動到播放的 log 沒有 `Uncaught` 開頭的錯誤；⑥ 票 10 的 `persist_run` 接 `restore_run`（同一個持鎖的 `bash -c`）：重開後停在原曲原位置，按播放從同一位置接著播，看截圖；⑦ 完整閘門的 Windows 六步（`build windows` 與 app、queue、search_and_play、stream_duration、stream_refresh 五個 integration_test）不帶 `--skip-windows` 全綠
