# YouTube 插件與 `idempotent`（M3 PR 1）

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`。技術設計在父任務 `design.md` §4.2（`HttpRequest.idempotent`）、§5.1（YouTube 插件、`expire` 不遮）、§5.4（Android 時長未知的前瞻）；ADR 0028 §決定 1、ADR 0013 §決定 4 的補充（已在 PR 0）。執行清單在父任務 `implement.md`「1.」。本檔只列做什麼與驗收。

## 目標

App 能以 `--fmp-dev-plugin` 裝上 YouTube 插件，匿名搜尋並播放 YouTube 的音訊；YouTube 的 innertube POST 在暫時失敗時會重試；錄下的 YouTube fixture 帶得到串流期限。

## 做什麼

### FMP（本 repo）

1. **`HttpRequest.idempotent?: boolean`**：`fmp-plugin.d.ts`、`hostApiShapes`、`SourceHttpClient` 的重試判斷。空＝依方法（現況：冪等方法才重試）；`true` 讓 POST 也重試；`false` 讓 GET 也不重試。只影響重試，不影響 `auth`、限流、網路紀錄（`retry` 欄位照記）。
2. **`officialPluginIds` 加 `youtube`**，`fmp_source_id_literal` 的案例跟著加。
3. **`googlevideo.com` 的 `expire` 不再遮**：從內建遮蔽的簽名參數移除（理由同 B 站 `deadline`：公開的到期時間，不是憑證）；`sig`、`lsig`、`ip` 等照拿掉。
4. **Android 時長未知**：實機確認 YouTube 串流在 just_audio 有沒有時長事件。沒有時，`PlaybackSession` 對時長未知的那一首不排前瞻（不呼叫 `setNext`），以 `completed` 換歌；寫進 `AudioBackend` 的 dartdoc。有時長就不改程式，只在 PR 描述記錄。
5. 文件：`app/AGENTS.md`（§ 網路的重試、§ 插件的官方 id）、需要時 network／plugins spec；每條寫閘門。

### fmp-plugins（`../fmp-plugins`，該 repo 自己的 PR）

6. **`youtube/`**：
   - YouTube.js 18.1.0 以 esbuild 打成單一 `youtube.js`（M1 探針的做法，`.trellis/tasks/archive/2026-09/09-30-youtubejs-probe/research/youtubejs-probe.md`），打包腳本與版本釘死，產物與原始碼一起提交。
   - manifest 1.0.0，能力 `search`、`resolveStream`；innertube POST 標 `idempotent: true`。
   - `resolveStream`：匿名、不需要 PO token 的 client；依 `quality` 挑 opus／aac；`expiresAt` 從網址的 `expire` 參數讀。
   - 錯誤對應表：「確認你不是機器人」→ `VerificationRequired`；`LOGIN_REQUIRED`（年齡限制）→ `Unavailable(age)`；`UNPLAYABLE` 地區 → `Unavailable(region)`；429 由網路層轉 `RateLimited`。
   - `checks.json`：`search` 與 `resolveStream`（含 `expiresAtPattern` `[?&]expire=(\d+)`）；以命令列錄 fixture（匿名，兩個案例）；手改的 `VerificationRequired`、`Unavailable(age)` fixture 各一。
   - README：能力、錯誤對應、打包方式。

## 不做

- 登入、`authHeaders`、`credentialsAttached`、「憑證無效」判定（PR 7–10）。
- `fmp-plugins` 的 CI、`index.json`、插件頁、首次啟動引導（PR 3–6）。
- 網易插件（PR 2）。

## 驗收

- [ ] 測試：`source_http_client_test.dart` 的 `retry`：`idempotent` 的 POST 重試、沒標的 POST 不重試、`idempotent: false` 的 GET 不重試；`type_definitions_test.dart`；`redactor_test.dart` 的 googlevideo 案例（`expire` 保留、簽名參數拿掉）；`fmp_source_id_literal` 的案例；Android 時長未知時：`playback_session_test.dart` 斷言不呼叫 `setNext`、`completed` 換下一首。
- [ ] YouTube 的契約（`FMP_PLUGIN_DIR=../fmp-plugins/youtube`）全綠：DTO、媒體請求不帶憑證、`expiresAt`；錯誤對應由 `fmp-plugins/youtube` 的 `npm test` 守（契約每能力只有一條案例，ADR 0015 §決定 4）。
- [ ] 驗證清單全綠（`app/AGENTS.md` § 驗證）。
- [ ] 實機（主對話做；**真實，匿名**）：兩平台以 `--fmp-dev-plugin` 裝 `youtube.js`、搜尋一次、播一首到交接下一首（記 Android 有沒有時長、交接是否無縫）；兩平台各跑一次 `plugin_runtime_benchmark_test.dart` 量載入時間，寫進 PR 描述（超過 3 秒另議）。
