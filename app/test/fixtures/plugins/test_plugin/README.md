# 測試插件 `fmp-test`

ADR 0015 §決定 6 的測試插件：合成資料、不連網。執行環境的測試、實機驗證與量測
都用它；它與旁邊的音檔以 dev flavor 的 asset 打包（`pubspec.yaml` 的
`flutter.assets`），prod 不含。

- `test_plugin.js`：安裝檔（標頭 manifest ＋ ES module），能力 `search`、
  `resolveStream`。搜尋任何關鍵字都回三首（每頁兩首）；關鍵字剛好是 `fail` 時以
  `RateLimited` 失敗，實機不連網也能看到錯誤提示。關鍵字剛好是 `missing` 時，第一頁
  第二首（`missing-440`）的串流指向不存在的 `missing.wav`：兩首依序加進佇列再按
  播放，第二首的前瞻開不起來，第一首照常播完、第二首重新解析後走恢復。
- `tone.wav`：2 秒 440 Hz 正弦波，16 kHz 單聲道 16-bit PCM，64 044 bytes。

## `tone.wav` 的來源與授權

2026-09-30 以 FFmpeg 9.0 的 `lavfi` 合成，沒有取材任何既有錄音：

```sh
ffmpeg -f lavfi -i "sine=frequency=440:duration=2:sample_rate=16000" \
  -ac 1 -c:a pcm_s16le -map_metadata -1 -fflags +bitexact -flags:a +bitexact tone.wav
```

以 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) 釋出至公有領域。

## 契約檢查

`checks.json` 是契約執行器（`test/plugins/contract/`）跑的案例：`search` 與
`resolveStream` 都期望成功（每個能力只有一條，`missing` 的那一首由
`test/plugins/test_plugin_bundle_test.dart` 守）。這個插件不發請求，所以沒有 `fixtures/`。`checks.json`
也會隨目錄打包進 dev flavor 的 asset（`flutter.assets` 是整個目錄），App 不讀它。
