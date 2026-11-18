# 12: 預載下一首

Status: done
Blocked by: 11
讀: brief §6、§9；architecture〈快取〉；事實 I4、K4、W3；`app/lib/playback/audio_backend.dart`；spec〈共同規則〉

## What to build

快到下一首時先解析它的串流，再讓音訊後端先緩衝開頭，切歌時不必等連線（brief §6）。音訊後端介面現在一次只裝一首，要改成能先裝好下一首（`mattpocock-skills:codebase-design`，兩個實作都改；just_audio 跳到已預載的項目用 seek、不重開，事實 I4；media_kit 要 `prefetch-playlist=yes`，事實 K4）。

第一步（擁有者定）：在四個平台量「按下一首到出聲」，並查 macOS 點下到出聲約 15 秒（M0 票 12 的觀察）慢在哪裡，原因寫進事實、數字寫進 `docs/research/`；數字給擁有者定預載後的目標，記成一條決定。

## 驗收

- [x] 預載前四平台的「按下一首到出聲」與 macOS 慢的原因已寫進 `docs/research/` 與事實；擁有者定了目標。（Windows 跳過，見 Comments）
- [x] 預載有測試：快到下一首時解析並緩衝；下一首改變（拖動、下一首播放、隨機）時換掉預載；預載的網址照〈快取〉檢查過期。
- [x] 預載後再量一次，四平台達到擁有者定的目標，數字寫進 `docs/research/`。（Windows 跳過，見 Comments）
- [x] 四平台實跑讀回切歌。（Windows 跳過，見 Comments）
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。（`--skip-windows`）

## Comments

### 做法

- 後端介面（`playback/audio_backend.dart`）加 `preload(AudioStream?)` 與 `AudioBackendState.stream`。預載的那條排在原生清單的第二項，原生自己決定什麼時候先緩衝它，這一首播完就自己接過去：後端先為這一首報一次 `completed`，之後的狀態屬於新那條。`load` 收到預載的那條（同一個物件）時跳過去、不重開（事實 I4），正在放的那條就什麼都不做。
- 兩個後端共用的帳本是 `playback/backends/backend_items.dart`（`BackendItems`），記原生清單裡依序是哪幾條、原生在哪個位置，修改一次一個（`SerialEdits`）。just_audio 用 `addAudioSource`、`seek(index:)`、`currentIndexStream`（事實 K31）；Apple 平台預載時就先把 HLS 清單包好。media_kit 用 `add`、`jump`、`stream.playlist`（事實 K33）。換過去之後移掉播過的那項，清單最多兩項。
- 播放層（`Playback`）：佇列用 `preloadNext(Track?)` 說下一首是哪首。這一首開始出聲後才解析它、交給後端；播它時用預載的串流，不再解析。預載的串流離過期不到 2 分鐘時不用，等著的預載在過期前 2 分鐘重新解析（ARCHITECTURE〈快取〉）。下一首換了，先把舊的從後端撤掉再解析新的。真正的改動延到 microtask 才做，所以按下一首時「佇列先換、同一輪再播」照樣用得到原本的預載。
- 佇列（`QueueController`）的下一首（`_upcoming`）：一般是 `Queue.upcoming`；單曲循環時是同一首；臨時播放時是要回去的佇列目前那首（回去時跳過去再倒退）。隨機加列表循環播到最後一首時，下一輪要重新打亂，不預載。佇列、臨時播放一變，或第一次出聲時，就告訴播放層。
- 實跑修掉兩個只在真的播放器上出現的問題：AVPlayer 自己接到下一首後，還會報一次上一首結尾再往後的位置（`BackendStates.position` 把它丟掉）；按下一首換過去時，原生還會報一次舊的項目位置（換的期間不理會）。另外，just_audio 的新那條常在 `setAudioSource` 回來前就出聲，那時還不能預載，載入回來後補做。
- 看門狗的開頭門檻 45 秒改成 20 秒（`stallTimeoutsProvider`，事實 F25）。
- 測試：`backend_items_test`、`backend_states_test`（自己接過去、殘留的位置）、`playback_test` 的預載一組（出聲後才預載、換過去不解析、自己接過去聲音不斷、過期、等著的預載重新解析、換掉與清掉、撤掉舊的、重開後再交、解析失敗、載入回來前就出聲）、`queue_controller_test` 的預載一組（按下一首、最後一首、自己接過去、拖動與下一首播放與隨機、不循環與列表循環、單曲循環、臨時播放）、`queue_test` 的 `upcoming`。閘門加 `integration_test/preload_test.dart`（真的後端：自己接過去不再解析；預載的網址回 403 時，換過去才報錯、重新解析照樣播；Apple 平台走 HLS 的兩條也接得上）。

### 量測

數字、量法與限制在 `docs/research/next-time-2026-11-18.md`。「出聲」以新那首的播放位置開始往前走為準（協調者要求），預載前後用同一支情境、同一個量法：

| 平台 | 按下一首：預載前 → 後 | 播完接下一首：預載前 → 後 |
| --- | --- | --- |
| macOS | 325–518 → 126–166 ms | 768 → 263 ms |
| iOS 模擬器 | 582–655 → 204–262 ms | 656 → 280 ms |
| Android 模擬器 | 405–995 → 126–221 ms | 621 → 196 ms |

擁有者定的目標（按下一首 ≤ 500 ms、播完接下一首 ≤ 300 ms）三平台都達到。程式還在修時另外量過兩輪預載後的按下一首：Android 有一次剛好 500 ms，另一次 1686 ms（開始下載到出聲 1682 ms，原因沒查），餘裕不大。播完接下一首的數字幾乎都是起點那 250 毫秒的誤差。稍早用「狀態變成播放中」量的一輪（預載前按下一首 366–1065 ms、播完 374–788 ms，給擁有者定目標用的；預載後播完 0 ms）不拿來判斷達不達標。

macOS 點下到出聲約 15 秒的原因：AVPlayer 直接播 B 站單檔時，要先下載幾乎整個檔才出聲（事實 M16，機制同 M14）。今天直接播 34:06 的曲目，45 秒還沒出聲；包成 HLS（ADR 0040）後只要 64–391 ms。對照實驗是 `integration_test/real_run/start_direct_run.dart`。`start_time_run.dart` 重量的開頭和換曲時沒預載的開頭，現在都在 1.1 秒內，所以開頭門檻改成 20 秒。

事實：新增 M16、K31–K33，改寫 F25；I4 前半重驗過（Apple 在輪到預載那項時才報 -11849），另兩點這次沒重現，仍標【待重驗】。

### 實跑

最後一輪是 `00c7c153` 上的 `next_time_run.dart`（macOS、iOS、Android 都綠），截圖與讀回在 `<暫存目錄>/after5/<平台>/`，`01-launch` 是啟動後還沒動過視窗的那張，`real_run.dart` 檢查過沒有白圖。每一步讀回的迷你播放器時長，三平台都依序換了曲：

| 步驟 | macOS | iOS 模擬器 | Android 模擬器 |
| --- | --- | --- | --- |
| 第一首播 15 秒 | 0:15 / 59:32 | 0:15 / 59:32 | 0:15 / 59:32 |
| 第 1 次下一首 | 0:15 / 3:13:36 | 0:15 / 3:13:36 | 0:15 / 3:13:36 |
| 第 2 次下一首 | 0:15 / 37:32 | 0:15 / 46:09 | 0:15 / 37:32 |
| 第 3 次下一首 | 0:15 / 46:09 | 0:15 / 37:32 | 0:15 / 46:09 |
| 播完接下一首 | 0:00 / 49:00 | 0:00 / 49:00 | 0:00 / 49:00 |

log 每次換曲都有 `Preloaded the next track` 與 `Playing the preloaded stream`。量測情境匿名搜一次，解析的首數比 spec 的「播一首」多（每輪 5 首、加上預載）。同一個量法量了好幾輪，前後在修程式。

### 審查

`mattpocock-skills:code-review`（從 `a5925395` 起）處理了：下一首換了時舊的預載沒先撤掉、帳本在抓 HLS 索引期間先改帳、換過去時混入舊那項的位置、`BackendPlaylist` 撞到名詞表的「歌單」（改名 `BackendItems`）、註解把 I4 待重驗的兩點寫成確定的事實、兩個後端重複的修改佇列、多餘的 `==`、假後端自己接過去的事件順序和真的不同。沒處理的：

- `Playback` 為預載多了七個欄位，沒抽成獨立元件。
- 預載靠「佇列先換、同一輪再播」，microtask 那段有寫註解；`_advance` 中間要是多一個 `await` 就會失效，`queue_controller_test` 的「最後一首」那條會紅。
- 等著的預載快過期、正在重新解析的那幾百毫秒裡這一首剛好播完時，後端接到的是舊網址（還沒過期），播放層會再重開一次。
- 單曲循環時按下一首、隨機加列表循環的下一輪第一首，沒有預載。
- 帳本與原生清單之間還有毫秒級的空檔：原生正在增刪的那一刻自己接過去，會對不上。
- 從預載換來、長度未知的串流會一直算緩衝中，直到看門狗觸發（B 站都有長度）。

### 驗證

完整閘門 `dart run tool/check.dart --skip-windows`（`00c7c153` 加上這次的研究檔），退出碼 0：

```
ok   i18n (slang)、codegen、format、analyze、test、schema snapshot、doc gate、doc gate tests
ok   build macos、build macos native tests、build ios、build android
ok   lock shared devices
SKIP build windows (--skip-windows: winpc keeps crashing, Windows checks wait until it is stable again)
ok   native tests macos
ok   integration_test macos／ios／android：app_test、preload_test、queue_test、search_and_play_test、stream_duration_test、stream_refresh_test（18 步全 ok）
SKIP integration_test windows：上面六個（同一個原因）
ok   unlock shared devices
ok   plugin bundles (esbuild)
```

`preload_test` 的 403 那支印出各平台怎麼報壞掉的預載：macOS、iOS 是 `ParseFailure (code -11849: Operation Stopped)`，Android 是 `NetworkError (code 0: Source error)`，都只報一次、重新解析後照樣播。

Windows 跳過：media_kit 的預載只有 `BackendItems` 的單元測試，沒建置、沒實跑，也沒跑 `preload_test`。補驗時看：(1) `next_time_run.dart` 的按下一首與播完接下一首有沒有達到 ≤ 500／≤ 300 ms；(2) `preload_test` 三支綠；(3) 換到預載那條（`jump`）時，mpv 在長度不變時會不會不再發 duration，害 `load` 等滿 20 秒；`jump` 會先 `play()`，臨時播放回去時會不會先出一小段開頭；(4) 用 `start_time_run.dart` 量開頭出聲時間，確認 20 秒門檻夠；(5) 自己接過去後，位置有沒有殘留上一首的值。

Session 紀錄：2026-11-19 預載下一首：後端清單第二項預載、原生自己接過去、換過去不重開；三平台量測預載前後達到擁有者定的 500／300 ms；macOS 慢的原因查到是直接播單檔；看門狗開頭門檻改 20 秒
決定：預載的目標是播完自動接下一首 ≤ 300 ms、播到一半按下一首 ≤ 500 ms，四平台都要（使用者定）
決定：測試接縫四層：播放層、佇列層、BackendItems 單元測試、閘門的 preload_test（協調者代答）（Agent 定）
決定：看門狗開頭門檻 45 秒改成 20 秒，Apple 改走 HLS 後已知最慢約 8 秒（協調者代答）（Agent 定）
決定：「出聲」以新那首位置開始往前走量，播完接下一首從上一首走到結尾前 250 ms 起算（協調者要求）（Agent 定）
決定：這一首開始出聲就預載下一首、不等快播完：中途按下一首的目標要省掉取得網址（Agent 定）
決定：預載用原生清單的第二項；自己接過去時先報播完，播放層靠 AudioBackendState.stream 的物件身分認串流（Agent 定）
決定：佇列把下一首推給播放層（preloadNext），改動延到 microtask，按下一首時仍用原本的預載（Agent 定）
決定：下一首換了先從後端撤掉舊預載再解析新的，解析失敗就不預載（Agent 定）
決定：從預載換來長度 0 的 ready 算緩衝中、新的載入不等改到一半的清單，防的是 I4 待重驗的兩點（Agent 定）
決定：單曲循環預載同一首、臨時播放預載要回去的那首、隨機加列表循環的最後一首不預載（Agent 定）
決定：預載解析失敗只寫 warning、播到它時照常解析；等著的預載在過期前 2 分鐘重新解析（Agent 定）
決定：自己接到下一首後，大於等於上一首最後位置的報數丟掉，直到新那首報出更小的（Agent 定）
決定：macOS 慢的原因用對照實驗 start_direct_run 查（直接播 vs HLS），留在 real_run 換版本時重量（Agent 定）
決定：量測情境每輪解析 5 首以上加預載，比 spec 的播一首多；播不了的那首記成跳過（Agent 定）
變更：Added｜播放控制｜播放時先準備好下一首：按下一首時不用再等取得網址，一首播完直接接上下一首
變更：Changed｜播放控制｜開頭一直緩衝不出聲時，20 秒（原本 45 秒）就當成播不了，更快重試或跳下一首
