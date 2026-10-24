# 測試插件 `fmp-test`

ADR 0015 §決定 6 的測試插件：合成資料、不連網。執行環境的測試、實機驗證與量測
都用它；它與旁邊的音檔以 dev flavor 的 asset 打包（`pubspec.yaml` 的
`flutter.assets`），prod 不含。

- `test_plugin.js`：安裝檔（標頭 manifest ＋ ES module），能力 `search`、
  `resolveStream`、`live`、`mix`、`multiPart`、`trackDetail`、`importPlaylist`、`charts`、`libraryRead`、`login`。搜尋任何關鍵字都回三首（每頁兩首）；關鍵字剛好是 `fail` 時以
  `RateLimited` 失敗，實機不連網也能看到錯誤提示。關鍵字剛好是 `missing` 時，第一頁
  第二首（`missing-440`）的串流指向不存在的 `missing.wav`：兩首依序加進佇列再按
  播放，第二首的前瞻開不起來，第一首照常播完、第二首重新解析後走恢復。
  播放恢復的實機驗證另有三個關鍵字（都只在剛好是它時）：
  - `preview`：每一首都只回試聽片段（`previewOnly: true`）。「跳過試聽片段」開著時
    跳過並提示，關著時照播、播放列標「試聽」。
  - `flaky`：每一首的解析輪流以 `NetworkError` 失敗與成功，第一次失敗（插件的
    isolate 活著就一直算下去，同一首要再看失敗就等網址快取的 5 分鐘過去或重開 App）。
    網路狀態是 `online` 時是「重試中」一秒後播起來；不是 `online` 時（Android
    模擬器開飛航模式）停在「等待網路連線」，網路回來後從原位置自動續播。
  - `unavailable`：第一頁第一首以 `Unavailable`（版權）失敗。兩首一起加進佇列
    播放，第一首跳過並提示原因。

  假的登入（`login.methods` 是 `qr` 與 `cookie`，不連網），給帳號頁的實機驗證：
  - 「設定 > 帳號」的「FMP Test Plugin」按「QR 登入」：QR 碼的內容固定是
    `fmp-test://login`（掃了也沒用）。第一次輪詢（2 秒後）是 `waiting`，第二次
    （4 秒後）就 `done`，交出憑證 `fmp_test_session=fake-session-0000`。
  - 按「貼上 cookie」：貼 `fmp_test_session=` 加任何值（例如
    `fmp_test_session=fake-session-0000`；`cookies.txt` 格式的一行也可以）就能登入。
  - `loginVerify` 只看有沒有值不空的 `fmp_test_session`，有就回帳號「FMP Test User」
    （沒有頭像）；沒有就以 `CredentialInvalid` 失敗（貼錯的 cookie 看得到失敗訊息）。
  - 沒有 `webView`：網頁登入要真的網站，只在真實模式驗。
  - 登入之後開關「以登入身分瀏覽與播放」、登出都走真的流程（`CredentialStore`、
    `source_settings`）。這個插件不發請求，所以看不出請求帶不帶憑證：那部分由
    `test/plugins/accounts/account_service_test.dart` 以會發請求的插件守。
  失效與刷新（`login.refresh` 是 `onStartup`，不連網，給帳號頁與失效提示的實機驗證）。
  這個插件不發請求，看不到 `credentialsAttached`，所以以「已登入」當作這次帶了憑證，
  狀態存在 plugin storage 的 `expiry`：
  - 登入後搜尋 `expired`：第一次以 `CredentialInvalid` 失敗，宿主呼叫 `loginRefresh`
    換成新憑證（`fmp_test_session=fake-session-0001`，之後每次加一），再重跑一次就成功
    （使用者只看到搜尋結果；帳號頁的「最後刷新」更新為「已更新憑證」）。再搜一次 `expired`
    又重來一輪。
  - 登入後搜尋 `expired-hard`：`CredentialInvalid`，而且 `loginRefresh` 也以
    `CredentialInvalid` 失敗，帳號轉成「已失效」，提示「…的登入已失效」附「登入」。重新
    登入（`loginVerify`）清掉狀態。
  - 沒有進行中的 `expired` 時，`loginRefresh` 回 `null`：重啟 App 後的啟動刷新跑一次，
    帳號頁的最後刷新是「不需要更新」。
- 直播（`live`，不連網，給電台的實機驗證）：固定五個直播間，`liveSearch` 任何關鍵字都
  回這五個（`status` 篩選有效，`hasMore` 為假；關鍵字剛好是 `fail` 時以 `RateLimited` 失敗），
  `liveRoomFromUrl` 認 `https://fmp.test/live/<roomId>`（roomId 是下面五個之一，其他網址
  回 `null`）：

  | roomId | `liveStatus` | `resolveLive` | 用途 |
  |---|---|---|---|
  | `live-ok` | 開播中，人數 42 | `live.wav`（60 秒） | 一般收聽 |
  | `live-offline` | 未開播 | `NotFound`（錯誤裡沒有「未開播」；`Unavailable` 的原因都會誤導） | 未開播 |
  | `live-drop` | 一律開播中 | `tone.wav`（2 秒） | 提前結束後重連：每次重連又在 2 秒後結束 |
  | `live-ended` | 插件的 isolate 活著期間第一次查是開播中，之後都是未開播 | `tone.wav` | 提前結束後問狀態，得到「直播已結束」 |
  | `live-broken` | `NetworkError` | `NetworkError` | 查詢失敗（搜尋結果裡標開播中） |

  `live-ended` 的次數不跨 App 重啟；要再看一次「開播中」就重開 App。
- Mix（`mix`，不連網，給「開始 Mix」的實機驗證）：任何曲目的選單「開始 Mix」都開一個新的 Mix
  （標題 `Test mix <n>`；`mixId` 每次不同），曲目鍵是 `mix-<mixId>-<n>`，串流都是 `tone.wav`（2 秒），
  每批 5 首：

  | 批次 | 曲目 `n` | `cursor` | 用途 |
  |---|---|---|---|
  | 第一批（seed） | 1–5 | `2` | 開始 |
  | 第二批（續取） | 3、6–9 | `3` | 第 3 首重複第一批的：宿主去重後只附加 4 首 |
  | 第三批（續取） | 10–14 | 沒有 | Mix 到此為止：下一次補歌改以佇列最後一首當 seed 開新的一批（新的 `mixId`） |

  每首開始時之後只剩 1 首以下就補，所以佇列的第 4 首開始時補第二批（佇列 9 首）、第 8 首開始時補第三批（佇列 14 首）、
  第 13 首開始時換種子（`cursor` 已空，以佇列最後一首開新的一批）。其他 `cursor` 以 `NotFound` 失敗。
- 分 P（`multiPart`，不連網，給搜尋結果的展開與影片選單的實機驗證）：搜尋關鍵字剛好是 `parts` 時，
  三首是三種狀況；其他關鍵字的曲目都帶 `partCount: 1`（確定單 P，不顯示展開鈕）。每個分 P 的曲目鍵
  含 cid，串流都是 `tone.wav`，標題是 `Part one`、`Part two`、`Part three`，各 2 秒：

  | sourceId | 搜尋結果的 `partCount` | `multiPart` | 用途 |
  |---|---|---|---|
  | `parts-220` | 3 | 三個分 P（cid 22001–22003） | 展開、點 P2 播放、選單加入全部 |
  | `parts-440` | 沒有 | 兩個分 P（cid 44001、44002） | 不知道分 P 數：展開鈕照顯示，選單先取分 P 再套用到全部 |
  | `parts-880` | 沒有 | 一個分 P | 展開後鈕消失；選單照單曲處理 |
- 曲目詳細（`trackDetail`，不連網，給播放頁「詳細」分頁的實機驗證）：看搜尋結果裡的曲目（點開播放頁的詳細分頁）。
  `tone-440` 有完整的資料（六行的簡介、2024-05-17 的發佈時間、專輯、七種統計；沒有 `uploaderAvatar`，因為
  `allowedHosts` 是空的，頭像的顯示由 widget 測試守）；`tone-880` 以 `NetworkError` 失敗（看詳細區的失敗與重試）；
  其他曲目回空的詳細資料（詳細區不多顯示東西）。
- 歌單匯入（`importPlaylist`，不連網，給匯入與刷新的實機驗證；狀態存在插件 isolate 的記憶體，到 App 重啟為止）：
  `playlistFromUrl` 認 `https://fmp.test/playlist/<id>`（任何 id 都認，不存在的在取頁時 `NotFound`）與
  `https://fmp.test/mix/<sourceId>`（回 `mixSeed`；這個插件宣告了 `mix`）；其他網址回 `null`。每首的串流都是 `tone.wav`：

  | 歌單 | 內容 | 用途 |
  |---|---|---|
  | `pl-basic` | 5 首、每頁 3 首（`cursor` `3`），第 1、4 首是同一首（`tone-440`，資料也相同）；沒有 `remoteItemId`；給 `total` 5 | 多頁、同曲重複的比對 |
  | `pl-grow` | 單頁、有 `remoteItemId`、給 `total`，每項是不同的曲目（`grow-<n>`，標題 `Grow track <n>`）。每取一次第一頁（＝每刷新一次）輪流：新增一首、移除最前面一首、整張倒序（從 4 首起） | 刷新時新增、移除、重排 |
  | `pl-partial` | 第 1 頁 3 首，第 2 頁 `NetworkError` | 部分完成：不移除任何項目 |
  | `pl-gone` | `NotFound` | 來源失效 |
  | `pl-auth` | 沒有憑證 `AuthRequired`；登入後 3 首、`writable: true` | 需要登入、登入後刷新、可寫 |
  | `pl-unavailable` | 3 首，第 2 首 `unavailable: true` | 失效項目的標示 |
  | `pl-long` | 1200 首、每頁 50 首（`cursor` 是位移）、每頁都給 `total` 1200；曲目 `long-<n>`，標題 `Long track <n>` | 匯入進度「已匯入 n／M 首」與取消的實機驗證 |
  | `pl-long-nototal` | 同 `pl-long`，但不給 `total` | 進度只顯示「已讀 n 首」（不定長的進度條） |
  | `pl-parts` | 一支 3 P 的影片（`parts-220`）展開成 3 首（cid 22001–22003），帶 `partIndex`、`parentTitle`；不給 `total` | 分 P 兩欄存得進去 |
- 帳號的歌單（`libraryRead`，不連網，給帳號頁「歌單」的實機驗證）：`libraryPlaylists` 沒有憑證時
  `AuthRequired`；登入後一頁兩張（不分頁），標題與首數同 `importPlaylist` 回的：

  | `playlistId` | 標題 | 首數 | `writable` |
  |---|---|---|---|
  | `pl-auth` | Private playlist | 3 | 是 |
  | `pl-basic` | Basic playlist | 5 | 否 |

  帳號頁勾選匯入後，這兩張的內容由上面的 `importPlaylist` 提供。`createPlaylist` 建的歌單接在後面
  （見下一項）。
- 帳號關注的直播間（選填的 `libraryLiveRooms`，不連網，給帳號頁「從帳號匯入電台」的實機驗證）：沒有憑證
  `AuthRequired`；登入後回上面「直播」那五個直播間（`live-ok`、`live-offline`、`live-drop`、`live-ended`、
  `live-broken`，資料同 `liveSearch`，不隨操作改變）。帳號頁卡片的「⋯」選單出現「從帳號匯入電台」；匯入一次
  五個全加進電台，再匯入一次全部「已在電台清單」。沒有 `checks.json` 案例（每能力一條）。
- 遠端寫入（`libraryWrite`，不連網，給「加入遠端歌單」與「從遠端歌單移除」的實機驗證；內容存在插件
  isolate 的記憶體，到 App 重啟為止）。可寫的歌單是 `pl-auth`（從 3 首起，每項有 `remoteItemId`
  `auth-<n>`）與 `createPlaylist` 建的 `pl-new-<n>`（空的）；寫入前沒有憑證 `AuthRequired`，歌單不是這兩種
  （例如 `pl-basic`）`NotFound`。`importPlaylist('pl-auth')` 與 `libraryPlaylists` 的首數都反映現在的內容，所以
  寫入之後的刷新看得到變化：

  | 呼叫 | 行為 |
  |---|---|
  | `addToPlaylist` | 歌單裡沒有就接在尾端（`added`），已經有（同 `sourceId` 與 `cid`，初始的三首也算）是 `alreadyPresent`；`sourceId` 是 `fail` 的那一首 `failed`，帶結構化錯誤（`RateLimited`，30 秒），同一次呼叫的其他首不受影響 |
  | `removeFromPlaylist` | 有 `remoteItemId` 就以它找，否則以 `sourceId` 與 `cid` 找；找到移除（`removed`），找不到 `notPresent`；`sourceId` 是 `fail` 的 `failed`（遠端不會有這一首，只有契約測試走得到，實機看不到） |
  | `createPlaylist` | 回 `pl-new-1`、`pl-new-2`…（標題是輸入的，空歌單）；之後 `libraryPlaylists` 列為可寫、可以匯入、可以再加歌 |

  要在實機加一首 `failed`：搜尋關鍵字剛好是 `write-fail`，第一頁第一首的 `sourceId` 就是 `fail`（其餘同 `tone`）。
  實機重播的順序（Android）：登入 → 搜尋 `tone`，把一首「加入遠端歌單」到 `pl-auth`（`added`）→ 再加一次
  （`alreadyPresent`）→ 搜尋 `write-fail` 加第一首（`failed`）→ 在對話框「在遠端新增歌單」→ 帳號頁匯入 `pl-auth`，
  在詳情的曲目選單「從遠端歌單移除」。
- 排行（`charts`，不連網，給首頁排行與排行工作的實機驗證）：`chartList` 回三個榜單，曲目沿用 `tone-<hz>`（可播），
  標題是 `<榜單名> tone <hz> Hz`：

  | `chartId` | `chart` | 用途 |
  |---|---|---|
  | `hot` | 5 首（`tone-440`、`220`、`880`、`330`、`550`） | 一般榜單 |
  | `new` | 3 首（`tone-110`、`660`、`770`） | 第二個榜單 |
  | `broken` | `NetworkError` | 單一榜單更新失敗：標「更新失敗」，其他榜單照常 |

  其他 `chartId` 以 `NotFound` 失敗。
- `tone.wav`：2 秒 440 Hz 正弦波，16 kHz 單聲道 16-bit PCM，64 044 bytes。

## `tone.wav` 的來源與授權

2026-09-30 以 FFmpeg 9.0 的 `lavfi` 合成，沒有取材任何既有錄音：

```sh
ffmpeg -f lavfi -i "sine=frequency=440:duration=2:sample_rate=16000" \
  -ac 1 -c:a pcm_s16le -map_metadata -1 -fflags +bitexact -flags:a +bitexact tone.wav
```

以 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) 釋出至公有領域。

## `live.wav` 的來源與授權

`live-ok` 直播間的串流：60 秒 220 Hz 正弦波（約 -20 dBFS，整數個週期），8 kHz 單聲道
16-bit PCM，960 044 bytes。2026-10-14 以 Python 標準庫 `wave` 合成，沒有取材任何既有錄音，
以 CC0 1.0 釋出至公有領域。選 16-bit 是因為各平台後端都確定能播；8-bit 約一半大小，
但沒有實機驗過。

## 契約檢查

`checks.json` 是契約執行器（`test/plugins/contract/`）跑的案例：`search`、
`resolveStream`、`live`（`liveStatus` 的 `live-ok`）、`mix`（以 `tone-440` 為 seed，五首）、`multiPart`（`parts-220`，三個分 P）、`trackDetail`（`tone-440`）、`importPlaylist`（`pl-basic` 的第一頁，三首）、`charts`（`hot`，五首）、`libraryRead`（`libraryPlaylists` 第一頁，兩張；標 `requiresLogin: true`，重播時宿主把 `login` 案例的假憑證放進隔離環境）`libraryWrite`（`addToPlaylist` 對 `pl-auth` 加兩首；標 `requiresLogin: true` 與
`mutates: true`：健康檢查、命令列錄製與開發工具的真實模式都略過它，只有契約測試的重播會跑）與 `login`（`loginVerify`，輸入是上面的假憑證，標
`requiresLogin: true`）都期望成功（每個能力只有一條，`missing` 的那一首由
`test/plugins/test_plugin_bundle_test.dart` 守）。這個插件不發請求，所以沒有 `fixtures/`。`checks.json`
也會隨目錄打包進 dev flavor 的 asset（`flutter.assets` 是整個目錄），App 不讀它。
