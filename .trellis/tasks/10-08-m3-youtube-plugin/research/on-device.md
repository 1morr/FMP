# PR 1 實機紀錄

日期：2026-10-08。模式：**真實，匿名**（無 cookie、無登入）。插件：`fmp-plugins/youtube/youtube.js`（793,944 bytes），以 `--fmp-dev-plugin` 安裝。

## Android（`Medium_Phone`，API 37，dev debug）

- 請求：`GET /sw.js_data`、`POST /youtubei/v1/config`、`POST /youtubei/v1/search` 各 1；封面 `i.ytimg.com` 7；`POST /youtubei/v1/player` 2（目前這首與前瞻）；串流 `googlevideo.com`（播放器）。
- 搜尋 17 筆（session 1777 ms、search 1580 ms）。
- 播放：VISIONOS、5 個候選，第一個 `webm/opus` 170 kbps；從請求到出聲 4501 ms。
- **時長有回報**：交接時 `previousDurationMs` 3881061；`Look-ahead handover`（`end: completed`）→ 下一首 `Track audible`，`estimatedGapMs` 21。design §5.4 的「時長未知」在 YouTube 用不到，不改程式。
- 載入時間（`plugin_runtime_benchmark_test.dart`，debug）：YouTube 插件 9 次中位數 **69.2 ms**（空插件 4.8 ms、測試插件 5.1 ms）。

## Windows（dev debug，media_kit）

- 搜尋：`sw.js_data`、`config`、`search` 各 1，封面 12；16 筆（session 317 ms、search 722 ms）。
- **播放失敗**：VISIONOS 的 `mp4/aac`（itag 139、140）開流回 **HTTP 403**，重解析一次、換候選一次後跳過。佇列是「測試音 + 兩首 YouTube」、循環全部，測試音每輪都播得出來，所以「連續跳過」的計數一直被重設（ADR 0018 §決定 7 的規則），在關掉 App 前循環了約 32 輪：`POST /youtubei/v1/player` **160 次**、播放器開串流約 190 次（都 403）。這超出「最少操作」，是測試佈置的失誤（佇列裡放了一首必定成功的本機曲目又開循環）。
- 之後以 Node（YouTube.js 18.1.0，VISIONOS）發 1 個 player 請求查 403：回 `LOGIN_REQUIRED`「Sign in to confirm you’re not a bot」，本機 IP 被暫時標記，停止所有真實請求。
- 載入時間：YouTube 插件 9 次中位數 **72.7 ms**（空插件 1.6 ms、測試插件 1.7 ms）。

## 待追蹤

- Windows 403 的根因（見下一節）。
- 「連續跳過」被中間成功的曲目重設：一個系統性失敗的音源在循環佇列裡會一直被請求。照 ADR 0018 是預期行為；記到 M3a 的待辦，之後評估要不要加每音源的退避。
