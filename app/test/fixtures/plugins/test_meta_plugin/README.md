# 測試插件 `fmp-test-meta`

僅元資料來源的測試插件（M4 design §4.9）：合成資料、不連網。外部匯入（匯入預覽頁、
匹配結果）的實機重播用，扮演 Spotify、QQ 這種只有 `importPlaylist` 的插件。和 `fmp-test`
一樣以 dev flavor 的 asset 打包（`pubspec.yaml` 的 `flutter.assets`），prod 不含。

- `test_meta_plugin.js`：安裝檔，能力只有 `importPlaylist`（`playlistFromUrl` 與
  `importPlaylist`），沒有 `search`、`resolveStream`，所以不會出現在搜尋頁，匯入對話框認出它的網址
  就開匯入預覽頁。
- 歌曲的標題、歌手、時長照 `fmp-test` 的搜尋結果寫（`Test tone 220 Hz`、歌手 `FMP`、2 秒）：
  裝了 `fmp-test`（而且它是匹配目標）時匹配得到。`fmp-test` 不管關鍵字是什麼都回同樣的曲目，
  標題後面接著括號裡的關鍵字，所以每一首的候選都是 `Test tone 220 Hz` 與 `440 Hz`（第一頁兩首）。
- `playlistFromUrl` 認 `https://fmp.test/meta/<id>`（任何 id 都認，不存在的在取頁時 `NotFound`），
  其他網址回 `null`。每頁 2 首：

  | 歌單 | 內容 | 用途 |
  |---|---|---|
  | `meta-basic` | 6 首、3 頁：4 首匹配得到（220 Hz 出現兩次、外部 id 相同）、2 首匹配不到（時長 999 秒與 300 秒，超出時長門檻） | 預覽、改選、重搜、排除、建立；再匯入一次全部沿用 |
  | `meta-truncated` | 3 首、2 頁，最後一頁 `truncated: true` | 「來源只提供了部分曲目」的提示 |
  | `meta-broken` | 第 1 頁 2 首，第 2 頁 `NetworkError` | 讀取失敗：停在錯誤與「重試」，不進匹配 |

- 實機重播（Android）：先照 `fmp-test` 的 README 裝好 `fmp-test`，再以 `--fmp-dev-plugin` 裝這個檔
  （裝好的插件留在清單上）→ 音樂庫「匯入」貼 `https://fmp.test/meta/meta-basic` → 預覽頁「開始匹配」→
  改選一首、重搜一首、排除一首 → 建立歌單 → 再匯入一次（全部沿用、沒有搜尋）。
- 「配對到其他音源」用 `fmp-test` 自己的歌單（`https://fmp.test/playlist/pl-basic`）：對話框多出
  選擇，預覽頁的目標預設不勾 `fmp-test`。

## 契約檢查

`checks.json` 只有 `importPlaylist`（`meta-basic` 的第一頁，兩首），期望成功；契約執行器
（`test/plugins/contract/`）以重播跑它。這個插件不發請求，所以沒有 `fixtures/`。其餘歌單與
「匹配得到 `fmp-test`」由 `test/plugins/test_plugin_bundle_test.dart` 守。
