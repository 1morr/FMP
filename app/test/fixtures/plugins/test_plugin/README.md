# 測試插件 `fmp-test`

ADR 0015 §決定 6 的測試插件：合成資料、不連網。執行環境的測試、實機驗證與量測
都用它；它與旁邊的音檔以 dev flavor 的 asset 打包（`pubspec.yaml` 的
`flutter.assets`），prod 不含。

- `test_plugin.js`：安裝檔（標頭 manifest ＋ ES module），能力 `search`、
  `resolveStream`、`login`。搜尋任何關鍵字都回三首（每頁兩首）；關鍵字剛好是 `fail` 時以
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
- `tone.wav`：2 秒 440 Hz 正弦波，16 kHz 單聲道 16-bit PCM，64 044 bytes。

## `tone.wav` 的來源與授權

2026-09-30 以 FFmpeg 9.0 的 `lavfi` 合成，沒有取材任何既有錄音：

```sh
ffmpeg -f lavfi -i "sine=frequency=440:duration=2:sample_rate=16000" \
  -ac 1 -c:a pcm_s16le -map_metadata -1 -fflags +bitexact -flags:a +bitexact tone.wav
```

以 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) 釋出至公有領域。

## 契約檢查

`checks.json` 是契約執行器（`test/plugins/contract/`）跑的案例：`search`、
`resolveStream` 與 `login`（`loginVerify`，輸入是上面的假憑證，標
`requiresLogin: true`）都期望成功（每個能力只有一條，`missing` 的那一首由
`test/plugins/test_plugin_bundle_test.dart` 守）。這個插件不發請求，所以沒有 `fixtures/`。`checks.json`
也會隨目錄打包進 dev flavor 的 asset（`flutter.assets` 是整個目錄），App 不讀它。
