# 10: bilibili 解析串流

**What to build:** bilibili 插件多一個插件能力：把一首曲目（含分 P）解析成可播放的串流，回傳音訊網址、有效期與播放時需要的 header。宿主拿得到結果，有契約測試證明；佔位搜尋頁點一首時顯示解析到的串流資訊（音質、到期時間），網址照遮蔽規則顯示。播放留給票 11。

讀：brief §6、§18.1（事實 F1、F4、F5、F6）、§18.6 事實 M5；plan §3；`GLOSSARY.md`〈曲目與播放〉；票 08、09 的 Comments；spec〈共同規則〉

**Blocked by:** 09

**Status:** done

- [x] 解析串流走 DASH 音訊軌（m4a/AAC，事實 F6），四平台都選這種；有效期從網址的 `deadline` 讀（事實 F5），不寫死。
- [x] 回傳的 header 照事實 F4（媒體請求只帶 Referer，不帶憑證）。
- [x] 分 P：同一支影片的不同分 P 解析出不同的串流，有測試。
- [x] 解析失敗轉成錯誤分類（找不到、不可用、限流、解析失敗），有測試。
- [x] 解析串流的 fixture 已錄製，契約測試通過；`live` 冒煙測試加一條。
- [x] 四平台實跑：點一首，讀回畫面看到解析結果（匿名、每平台只解析一首）。
- [x] `dart run tool/check.dart` 完整版綠燈。

## Comments

### 做法

- 介面照票 08 的形狀加一個插件能力：`PluginCapability.resolveStream`、`Plugin.resolveStream(trackId) → AudioStream`（`lib/domain/audio_stream.dart`）。插件端匯出 `resolveStream({trackId}) → {url, headers?, expiresAtMs?, codec?, bitrate?}`，型別在 `host.d.ts`。欄位命名參考 Spotube 插件的音訊來源（`url`、`codec`、`bitrate`）。類別叫 `AudioStream`，不叫 `Stream`，免得和 `dart:async` 撞名；名詞仍是〈串流〉，沒有新詞。
- 宿主檢查回傳形狀：網址要是 http(s) 的絕對網址，數字要是有限值，時間要在 DateTime 的範圍內，不對就是 `ParseFailure`。log 不記網址：`Uri.parse` 的例外會帶整個簽名網址，所以只記訊息。`AudioStream.toString()` 也不印網址。有效期是 UTC，畫面顯示時轉本地時間。
- WBI（協調者的提醒）：這張票不用 WBI。cid 從 `/x/player/pagelist` 拿，串流從 `/x/player/playurl` 拿，兩支都不帶 `wts`、`w_rid`（事實 F1、F21），fixture 照原本的完整網址比對就對得上。票 09 Comments 記的比對問題，留給之後真的用到 WBI 的插件能力。所以 plan §3 沒有改。
- bilibili：先查 pagelist 拿分 P 的 cid，再打 playurl（`fnval=16`），從 `dash.audio` 選頻寬最高的音訊軌（事實 F6）。有效期讀網址的 `deadline`，讀不到就不給（事實 F5）。回傳的 header 只有 `Referer: https://www.bilibili.com`（事實 F4）。
- 曲目 id 照 B 站影片頁網址的慣例（`/video/<bvid>?p=<n>`）：`<bvid>` 是第一個分 P，`<bvid>?p=<n>`（n ≥ 2）是第 n 個分 P。不收 `?p=1`，一首曲目只有一個 id。這個格式寫在插件檔頭。之後會存進資料庫（M3），算持久化格式，擁有者 2026-11-12 採用，已寫進 brief §5.3（見文末〈擁有者決定〉）。
- 錯誤分類：
  - HTTP 412、429 與風控碼是限流（沿用事實 F2）。
  - `-404` 是找不到。舊版把它歸「不可用」，但它是稿件不存在，票上也列了「找不到」。
  - `62002`（稿件不可見）是不可用（下架），`-10403` 是不可用（地區）。
  - 舊版歸「沒有權限」的 `-403`、`62012`，以及 `-503`，在 brief §13 的不可用原因裡沒有對應的，不猜，維持 `parse_failure`。
  - 分 P 不存在、id 格式不對，都是找不到。
  - 沒有 DASH 音訊、pagelist 缺 cid，是解析失敗。
  - 這份代碼對照 search 也共用。
- 佔位頁：點一首就用 `track.source` 對應的插件解析。結果卡片顯示標題、音質（codec 加 kbps）、到期時間（本地，`yyyy-MM-dd HH:mm`）與網址，網址經 `redact()`。連點時只留最後一首的結果。integration_test `plugin_search_test.dart` 加了「點一首、看到音質與遮蔽過的網址」，四平台都跑。
- 遮蔽函式的 bug（`b3d0fa24`）：第一次錄製時，寫檔前的檢查擋下了 fixture（沒有寫檔）。原因：回應內文是 JSON 字串裡再包 JSON，簽名網址後面緊接 `\"`，網址樣式把反斜線吃進最後一個參數值，遮蔽時連它一起換掉，JSON 也壞了。修法是網址結尾不收反斜線。`redaction_test.dart` 補了一條，`plugin_fixtures_test.dart` 也補了一條「帶簽名網址的內文錄下後要通過檢查」：舊的 `redact()` 下紅，修好後綠。

### fixture 與 live

- 案例只有 `resolveStream/first-part.json`（`BV1xx411c7mD`，即 av170001）。原本也要錄 `?p=2`，但這支影片的 pagelist 現在只剩一個分 P，就沒錄，也沒有為了找多 P 的影片多打請求。「不同分 P 解析出不同串流」由 `bilibili_plugin_test.dart` 的單元測試證明，用的是 F21 的 pagelist 形狀。
- 原本 fixture 裡的網址整段遮成 `***`（帶 `upsig`），`deadline` 也一樣，重播時 `expiresAt` 一律是 null，契約測試證明不了「有效期讀 `deadline`」。擁有者決定遮蔽函式留下純時間戳的有效期參數，之後已重錄，見文末〈擁有者決定〉。
- 錄製：共打了 3 次，都是匿名。前兩次被寫檔前的檢查擋下（上面那個遮蔽 bug），只有第 3 次寫了檔：

```
$ FMP_RECORD=bilibili/resolveStream/first-part flutter test --run-skipped --tags live test/plugins/record_plugin_fixture_test.dart
00:00 +0: record the plugin fixture named by FMP_RECORD
recorded 2 request(s) into plugins/bilibili/fixtures/resolveStream/first-part.json:
  GET https://api.bilibili.com/x/player/pagelist?bvid=BV1xx411c7mD -> 200
  GET https://api.bilibili.com/x/player/playurl?bvid=BV1xx411c7mD&cid=62131&fnval=16 -> 200
00:00 +1: All tests passed!
```

- 提交前看過內容：網址的 query 值全是 `***`（含 `mid`、`buvid`、`oi`、`hdnts`），內文只剩 `keep.json` 列的欄位。
- `live` 冒煙測試：`plugin_live_test.dart` 依 fixture 目錄自動多出 `bilibili resolveStream` 這一條。手動執行一次（匿名）：

```
$ flutter test --run-skipped --tags live test/plugins/plugin_live_test.dart --plain-name "bilibili resolveStream"
00:00 +0: bilibili resolveStream against the real source
bilibili resolveStream {trackId: BV1xx411c7mD}:
  GET https://api.bilibili.com/x/player/pagelist?bvid=BV1xx411c7mD -> 200
  GET https://api.bilibili.com/x/player/playurl?bvid=BV1xx411c7mD&cid=62131&fnval=16 -> 200
00:00 +1: (tearDownAll)
00:00 +1: All tests passed!
```

### 四平台實跑

都是匿名，每個平台搜一次、解析一首，持共用裝置鎖；截圖留在暫存目錄。到期時間都比解析當下晚約兩小時，對得上事實 F5 的約 7178 秒。

- macOS：搜 `lemon`，點第一首。畫面顯示「音質：mp4a.40.2 · 190 kbps」「到期：2026-11-12 11:46」；網址的 query 值全是 `***`（`deadline=***`、`upsig=***`……）。log 有 search、pagelist、playurl 各一筆 GET。
- iOS 模擬器：鍵盤是注音（同票 08），`lemon` 打成注音，選第一個候選字「熬過運用」後搜尋。點第一首，顯示「mp4a.40.2 · 105 kbps」「到期：2026-11-12 11:48」。手機寬度下網址在 query 前就被截斷（`maxLines: 3`）。
- Android 模擬器：裝置語言是英文，顯示的是 en 的字串。速成輸入法選字「被一例」後搜尋，點第一首，顯示「Quality: mp4a.40.2 · 107 kbps」「Expires: 2026-11-12 11:49」「URL: https://upos-hz-mirrorakam.akamaized.net/…」。
- Windows（`winpc`）：`shot.ps1` 只能打字、不能點，所以加了 `-Click x,y`（客戶區的邏輯座標，依視窗 DPI 換算），plan §2 已補。
  - 第一次打字前，前景被桌面上別的程式搶走，字沒打進去，也沒有發出請求。改成打字前與點擊前各重新拉一次前景，再跑一次。
  - 第二次 `foreground_is_fmp_*` 全是 True。點到的是第二首，顯示「mp4a.40.2 · 193 kbps」「到期：2026-11-12 11:57」，完整網址的 query 值全是 `***`。log 有三筆 GET。
  - 同步前 `C:\fmp-wt\app` 刪不掉：有一個孤兒 `frontend_server`（`dartaotruntime.exe`，09:14 由 `flutter test -d windows` 啟動，父行程已不在）佔著它。那是 05b 持鎖時完整閘門留下的。我在持鎖時停掉它（只是編譯器行程），之後同步正常。

### 完整閘門

`dart run tool/check.dart`（commit 653843ab），退出碼 0：

```
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
ok   integration_test macos: integration_test/plugin_search_test.dart
ok   integration_test ios: integration_test/app_test.dart
ok   integration_test ios: integration_test/plugin_search_test.dart
ok   integration_test android: integration_test/app_test.dart
ok   integration_test android: integration_test/plugin_search_test.dart
ok   integration_test windows: integration_test/app_test.dart
ok   integration_test windows: integration_test/plugin_search_test.dart
ok   unlock shared devices
ok   plugin bundles (esbuild)
```

### code-review（b6fa2f88 起）

已處理（`52b501ef`）：
- 錯誤代碼原本把 `62012` 歸版權下架，和 F21 寫的「沒有權限」對不上，改成不猜。
- `?p=1` 和裸 bvid 是同一首的兩個 id，改成不收 `?p=1`。
- UI 的能力檢查和 `Plugin` 自己丟 `Unsupported` 重複，拿掉。
- 兩個插件能力的形狀檢查統一成 `_parse`。
- 修了一個壞掉的測試註解；integration_test 結束時還原語言。
- search 補一條共用代碼對照的測試。

未處理：
- 佔位頁解析串流的錯誤文字和搜尋的錯誤文字各有一個 switch，網路與限流兩句借用 `placeholder.search.*` 的字串。M0 的佔位頁到 M1 就整頁換掉，沒有抽共用。
- UI 自己在 `host.plugins` 裡用 `track.source` 找插件。宿主沒有提供 `pluginFor(source)`：目前只有這一個地方要用。票 11 播放時若也要找，再搬進宿主。
- 曲目 id 的格式要不要進 brief：擁有者已採用，見文末〈擁有者決定〉。

### 擁有者決定（2026-11-12，協調者轉達）

- **遮蔽函式留下有效期參數**：簽名網址裡名稱是 `deadline`、`expire`、`expires`、`expiry`（不分大小寫、名稱完全相同），而且值是純時間戳（10 或 13 位數）的參數照原樣留下，其他值與 `upsig` 等簽名照樣遮。照 `w_rid` 的前例，`AGENTS.md`〈公開 repo〉那一句擴充。
  - 測試在 `redaction_test.dart`：留下的案例，以及 `expire=soon`、5 位數、11 位數、`expire_token` 仍要遮的案例。原本「簽名網址的值全遮」那條改成例外留下 `deadline`。
  - 雙向變異：讓例外永遠不成立，兩條紅；拿掉時間戳檢查（任何值都留），「仍要遮」那條紅；還原後綠。
- **契約測試驗有效期**：fixture 案例加了選填的 `expect`，resolveStream 認得 `{"expiresAt": true}`（串流要有有效期），認不得的鍵會紅。錄製、重播與 live 冒煙測試都套用，錄製時照原樣寫回；plan §3 已補。
  - 加上 `expect` 後，舊 fixture（`deadline=***`）在契約測試紅了（`expected an expiresAt, got none`）。重錄（匿名、解析一首）後，網址留下 `deadline=1794456901`，其他值仍是 `***`，契約測試轉綠。`expiresAt` 在約定裡仍是選填。

```
$ FMP_RECORD=bilibili/resolveStream/first-part flutter test --run-skipped --tags live test/plugins/record_plugin_fixture_test.dart
00:00 +0: record the plugin fixture named by FMP_RECORD
recorded 2 request(s) into plugins/bilibili/fixtures/resolveStream/first-part.json:
  GET https://api.bilibili.com/x/player/pagelist?bvid=BV1xx411c7mD -> 200
  GET https://api.bilibili.com/x/player/playurl?bvid=BV1xx411c7mD&cid=62131&fnval=16 -> 200
00:00 +1: All tests passed!
```

- **曲目 id 格式採用**：宿主把曲目 id 當不透明字串，格式由插件定；B 站是 `<bvid>` 與 `<bvid>?p=<n≥2>`。已寫進 brief §5.3，之後改格式要做資料 migration。
- 改了遮蔽函式（`app/lib`），完整閘門重跑（`dart run tool/check.dart`，commit 028c3544），退出碼 0，22 步全部 `ok`：快速閘門 7 步、四平台建置、裝置鎖、四平台的 `app_test.dart` 與 `plugin_search_test.dart`、插件打包產物。
