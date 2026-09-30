# YouTube.js 在 FMP 插件執行環境的可行性驗證

- 日期：2026-09-30
- 問題：擁有者決定 3、ADR 0014 §決定 10。YouTube.js（npm `youtubei.js`，LuanRT）能否在 FMP 的插件執行環境
  （`flutter_js` 0.8.7 的 QuickJS、每插件一個背景 isolate、只有宿主 API v1）裡搜尋並解出可播的串流
- 分支：`probe/youtubejs`（已 push 保存，不合併）。下文的 `research/youtubejs-probe/`、`app/lib/probe/`、`app/test/probe/` 都在那個分支上
- 模式：真實連線（ADR 0027 §決定 2），沒有登入，沒有 cookie，也沒有 PO token

## 結論

**全部 PASS。** 能過關，前提是 `resolveStream` 改用 **VISIONOS** client（IOS 當備援）。
原本預期的 ANDROID_VR 從 2026-08-26 起已經不能用：沒帶 token 的 URL 只給得出大約前 60 秒的媒體。

| 條件 | Android（emulator-5554，dev） | Windows（dev） |
|---|---|---|
| 1. YouTube.js 能在執行環境載入 | PASS | PASS |
| 2. 搜尋有結果 | PASS（19／20 筆） | PASS（19／23 筆） |
| 3. 解出的音訊 URL 能在 FMP 端播出聲音 | PASS（Android 音訊堆疊層級，見下方但書） | PASS（WASAPI 峰值表量得到非零訊號） |
| 4. 不需要登入，也不需要另外產生 PO token | PASS | PASS |

給 ADR 0014 §決定 10 追加的一句：

> 2026-09-30 驗證通過：YouTube.js 18.1.0 以 esbuild 打包成單一插件檔（793 KB，約 204 KB gzip），在插件檔內用 JS 墊片補上 fetch／URL／TextEncoder 等 Web API（全部建在 `fmp.http.request` 上），不改宿主 API v1，就能在 Android 與 Windows 的 QuickJS 裡搜尋，並以 VISIONOS client 解出不需登入、不需 PO token 的完整音訊 URL，由 just_audio／media_kit 實際播出。前提是 client 會隨 YouTube 的封鎖更換（ANDROID_VR 從 2026-08-26 起只給約 60 秒），所以 YouTube 走插件，不改用 Dart 實作。

## 做了什麼

1. 用 Node 當基準，確認 YouTube.js 18.1.0（npm 最新版，2026-09-22 發佈）在未登入時，哪個 client 拿得到可播的音訊。
2. 用 esbuild 打包成符合 FMP 安裝檔格式的單一檔：開頭是 `/* ==FMP Plugin== {json} ==/FMP Plugin== */`，之後是 ES module。
   能力宣告 `search`、`resolveStream`；`allowedHosts` 為 `youtube.com`、`googlevideo.com`、`ytimg.com`、`googleapis.com`。
3. 在 `flutter test` 裡用真的 QuickJS 與宿主的網路層實跑：`app/test/probe/youtubejs_live_test.dart`，帶 `live` tag。
4. 裝進 dev App：透過開發入口 `--fmp-dev-plugin=`，由一個一次性的觸發器（`app/lib/probe/youtubejs_probe.dart`，掛在首頁）
   依序執行載入量測、搜尋、解析、播放、跳到 70% 的位置，timing 寫進 log（tag `probe`）。
   Android 用 just_audio，Windows 用 media_kit，與 ADR 0018 的兩個後端相同。

重現：

```
cd research/youtubejs-probe && npm ci && node build.mjs           # → dist/youtubejs_probe.js
cd app && flutter test --run-skipped --tags live test/probe/youtubejs_live_test.dart
cd app && flutter build windows --flavor dev --debug
app\build\windows\x64\dev\runner\Debug\fmp.exe --fmp-dev-plugin=<dist 的絕對路徑>
```

## 證據

以下 log 摘自 `logs/fmp.jsonl` 與 Android logcat。媒體 URL 的 query 一律以 `***` 遮蔽，沒有 cookie 與 token。

### Windows（2026-09-30 05:4x UTC，dev debug build）

```
probe  FMP_PROBE platform=windows plugin ready at 1354ms after main, rss=355MB
probe  FMP_PROBE loadBench empty ms=[15, 2, 2] rss +1MB for 3 runtimes
probe  FMP_PROBE loadBench youtubejs ms=[99, 106, 90] rss +9MB for 3 runtimes (357MB -> 366MB)
youtubejs-probe [probe] Innertube.create ms=19            ← 會話快取（fmp.storage）命中，0 個請求
network POST www.youtube.com/youtubei/v1/search 200 482ms 305484B
probe  FMP_PROBE search ms=582 items=19
network POST www.youtube.com/youtubei/v1/search 200 405ms 653498B
probe  FMP_PROBE search#2 ms=487 items=23
network POST www.youtube.com/youtubei/v1/player 200 83ms 88294B
youtubejs-probe [probe] resolveStream ms=113 client=VISIONOS candidates=5 first=mp4/aac@130677
probe  FMP_PROBE mpv v ffmpeg: Opening https://rr*---sn-***.googlevideo.com/videoplayback?***
probe  FMP_PROBE mpv info cplayer: (+) Audio --aid=1 (*) (aac 2ch 44100Hz)
probe  FMP_PROBE mpv info cplayer: AO: [wasapi] 48000Hz stereo 2ch float
probe  FMP_PROBE t+1s position=470ms duration=213s playing=true buffering=false audio=floatp/44100Hz
probe  FMP_PROBE t+6s position=5441ms ...
probe  FMP_PROBE seek to 149s
probe  FMP_PROBE t+8s position=150104ms ...
probe  FMP_PROBE t+16s position=158152ms duration=213s playing=true buffering=false
```

同時以 `research/youtubejs-probe/audio-peak.ps1` 讀 Windows Core Audio 裡 fmp.exe 那個 audio session 的峰值表，
結果是 `state=active`，24 次取樣的峰值都落在 0.196～0.835 之間，一次都沒有 0。
這表示送到預設輸出裝置的是有內容的聲音，不是靜音。

### Android（emulator-5554，Android 17 x86_64，2026-09-30 05:36–05:37 UTC，dev debug build）

```
FMP_PROBE platform=android plugin ready at 4802ms after main, rss=287MB
FMP_PROBE loadBench empty ms=[19, 5, 6] rss +0MB for 3 runtimes
FMP_PROBE loadBench youtubejs ms=[137, 294, 169] rss +10MB for 3 runtimes (285MB -> 295MB)
[youtubejs-probe] [probe] Innertube.create ms=63
network POST www.youtube.com/youtubei/v1/search 200 2132ms 299149B
FMP_PROBE search ms=2465 items=19
network POST www.youtube.com/youtubei/v1/search 200 902ms 587999B
FMP_PROBE search#2 ms=1198 items=20
network POST www.youtube.com/youtubei/v1/player 200 234ms 88926B
[youtubejs-probe] [probe] resolveStream ms=367 client=VISIONOS candidates=5 first=mp4/aac@130677
FMP_PROBE backend opened ms=3245
FMP_PROBE t+1s position=1155ms duration=213s ready/playing=true
FMP_PROBE seek to 149s
FMP_PROBE t+8s position=150087ms duration=213s ready/playing=true
FMP_PROBE t+16s position=158188ms duration=213s ready/playing=true
```

播放中的系統狀態：

```
dumpsys audio:  AudioPlaybackConfiguration ... type:android.media.AudioTrack u/pid:10241/14054 state:started
                attr: usage=USAGE_MEDIA content=CONTENT_TYPE_MUSIC ... mutedState:none
dumpsys audio:  STREAM_MUSIC Muted: false, streamVolume:15 (Max 15)
audio_flinger:  output thread Standby: no, Output devices: 0x2 (AUDIO_DEVICE_OUT_SPEAKER)
                track 60 Active=yes pid 14054 Usg 1 G/L/R dB 0/0/0 Underruns 0
```

這一次在 App 首次啟動（沒有會話快取）時，`Innertube.create ms=2103`：`GET /sw.js_data` 1456ms，`POST /v1/config` 237ms。

**Android 條件 3 的但書**：模擬器是另一個 session 以 `-no-audio` 啟動的，Windows 端聽不到模擬器的聲音，
我沒有為此重啟共用的模擬器。所以這一項的證據停在 Android 音訊堆疊：

- ExoPlayer 的 AudioTrack 狀態是 started，而且沒被靜音；
- AudioFlinger 把 frame 寫到 speaker 輸出，增益 0 dB、沒有 underrun；
- 媒體音量 15/15；
- 播放位置在跳過 60 秒上限之後仍持續前進。

同一條串流、同一種 AAC 解碼，在 Windows 量得到非零峰值，所以 Android 播出靜音的可能性很低。
如果需要耳朵聽得到的證據，要在沒有 `-no-audio` 的模擬器或實機上重跑。

### 共用的量測

`flutter test` 在 Windows 主機上跑真的 QuickJS 與宿主網路層：

```
FMP_PROBE load ms=121
FMP_PROBE search#1 ms=713 ... items=19
FMP_PROBE resolve dQw4w9WgXcQ ms=143 ... client=VISIONOS candidates=5
FMP_PROBE range GET bytes=2759557- (80% of 3449447) status=206 type=audio/mp4 bytes=689890
```

另外，`app/test/probe/quickjs_eval_test.dart` 證實插件裡可以用 `new Function` 與間接 `eval`。

## 哪個 client 能用：PO token 現況

2026-09-30 的實測，影片為 `dQw4w9WgXcQ`，未登入，沒有 PO token：

| client | playability | 音訊 URL | 開放式 `Range: bytes=0-` | 檔案 80% 位置的 Range |
|---|---|---|---|---|
| **VISIONOS** | OK | 明文（139/140/249/250/251） | 206（UA 用 libmpv、ExoPlayer、Dart 或不帶都一樣；不帶 Range 回 200） | 206 |
| IOS | OK | 明文（139/140） | 206 | 206 |
| ANDROID_VR | OK | 明文 | **403** | **403** |
| TV | UNPLAYABLE（"The page needs to be reloaded."） | — | — | — |
| WEB_EMBEDDED | "This video is unavailable" | — | — | — |

- ANDROID_VR：`bytes=0-1048575`、`bytes=1048576-1114111` 回 206；從約 1.1 MB 開始，以及 `bytes=2097152-…`，一律 403。
  這個檔案是 3,449,447 bytes、213 秒，換算大約是前 60～70 秒。等 60 秒後重試，結果不變。
  第一版探針用的就是 ANDROID_VR：Windows 上 mpv 送出開放式 Range，拿到 `HTTP error 403 Forbidden`，一直停在緩衝。
- VISIONOS、IOS 的 URL 不需要解密，也沒有 `n` 參數，所以不必下載或執行 player JS（`retrieve_player: false`）。

來源：

- yt-dlp Wiki〈PO Token Guide〉，2026-07-12 編修（https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide）：
  當時 `android_vr`、`tv`、`web_embedded` 的 GVS 不需要 PO token；`web`、`mweb`、`web_music`、`tv_simply` 需要；
  `android`、`ios` 標為「GVS 或 Player」需要。
- yt-dlp #15751、#15756，2026-01-29（https://github.com/yt-dlp/yt-dlp/issues/15756）：
  失去 `android_sdkless` 之後，未登入時預設拿 HTTPS 格式的 client 改成 `android_vr`。
- PSX-Place〈Yo! Player fix for videos longer than 1 minute (VISIONOS patch)〉，2026-08-30／31
  （https://www.psx-place.com/threads/yo-player-fix-for-videos-longer-than-1-minute-visionos-patch.50952）：
  - 從 2026-08-26 起，沒帶 token 的 ANDROID_VR googlevideo URL 只給約 60 秒的媒體，之後一律 403；
  - 改用 VISIONOS（client id 101，版本 1.02）可以拿到完整長度、不需要 PO token（2026-08-31）。
  - 本次實測與這篇的描述一致。
- VRChat 論壇（https://ask.vrchat.com/t/video-players-completely-broken/48829）：
  2026 年 7 月 `web_safari` client 失效。

風險：哪個 client 能用由 YouTube 決定，每隔幾個月就會變，VISIONOS 也可能下週就被加上同樣的上限。
這與用 YouTube.js 還是 Dart 無關，兩者都得跟著換 client。
差別在更新方式：插件可以不發新版 App 就更新，YouTube.js 上游也會跟著調整 client 常數（18.1.0 已經內含 VISIONOS）。
`resolveStream` 應該準備一串候選 client 依序嘗試（探針用 `['VISIONOS', 'IOS']`）。

## 需要的墊片

全部寫在插件腳本內（`research/youtubejs-probe/src/shims.js`），宿主程式碼沒有改。

| 缺的東西 | 怎麼補 |
|---|---|
| `fetch`、`Request`、`Response`、`Headers` | 自己寫的精簡版，底層走 `fmp.http.request`。`Response.text()`／`json()`／`arrayBuffer()`，沒有 `body` 串流（`VideoInfo#download` 不能用） |
| `URL`、`URLSearchParams`、`atob`、`btoa`、`structuredClone` | core-js 3 的 `actual/*` polyfill（打包後約 76 KB） |
| `TextEncoder`、`TextDecoder` | 自己寫的 UTF-8 版 |
| `crypto.getRandomValues`、`randomUUID` | 以 `Math.random` 實作（只用在產生 visitor／cpn，沒有安全用途） |
| `setTimeout`、`clearTimeout`、`queueMicrotask` | 以 microtask 執行，忽略延遲。搜尋與解析的路徑都不會呼叫；只有 LiveChat、OAuth2 會用 |
| `Intl.DateTimeFormat` | 不補，建立 Innertube 時直接給 `timezone: 'UTC'`（`Session` 的參數預設值會讀 `Intl`） |
| 平台層 | 自己呼叫 `Platform.load({...})`：Cache 以 `fmp.storage` 存 base64，讓會話資料跨啟動重用；`eval` 用 `new Function`；`server: true` |

打包時踩到的一個雷：從 `youtubei.js/agnostic` 進入，esbuild 會把循環 import 排錯順序，載入時出現
`TypeError: parent class must be constructor`（`class extends YTNode` 時 `YTNode` 還是 undefined）。
改從 `youtubei.js/web` 進入就正常，因為它先 import `Utils`。

## 打包大小

`dist/youtubejs_probe.js` 是 **793,075 bytes**（minify 後，約 204 KB gzip）；不 minify 是 1,673,453 bytes。組成：

| 套件 | 打包後的 bytes |
|---|---|
| youtubei.js | 564,374 |
| meriyah（解析 player JS 用；VISIONOS 路徑用不到，可以砍掉） | 118,860 |
| core-js | 76,311 |
| @bufbuild/protobuf | 10,750 |
| fflate | 9,544 |
| 插件本身與墊片 | 約 7,600 |

## 效能

只記錄，不作為過關條件。數字都來自 debug build：Dart 是 JIT，QuickJS 是原生碼。

| 項目 | Windows | Android 模擬器 |
|---|---|---|
| 插件載入（spawn isolate、建立 QuickJS、執行 793 KB module） | 90～106 ms（`flutter test` 裡 121～156 ms） | 137～294 ms |
| 對照：空插件載入 | 2～15 ms | 5～19 ms |
| 每多一個 runtime 增加的 RSS | 約 3 MB | 約 3.3 MB |
| `Innertube.create` 第一次（2 個請求） | 302～374 ms | 2103 ms（模擬器網路慢） |
| `Innertube.create` 會話快取命中（0 個請求） | 19～23 ms | 63 ms |
| search（總計；其中 HTTP 的時間） | 485～635 ms（405～482 ms） | 1168～2358 ms（902～2132 ms） |
| search 在 JS 端的解析 | 約 80～150 ms | 約 220～270 ms |
| resolveStream（總計；其中 HTTP 的時間） | 113～167 ms（83～93 ms） | 367～368 ms（234～245 ms） |
| 後端開啟到有聲音 | media_kit 55～95 ms，1 秒內開始走 | just_audio `setUrl` 約 3.2～3.5 s |
| App RSS：載入後 → 播放 16 秒後 | 355 → 392 MB | 284 → 303 MB（`dumpsys meminfo` TOTAL PSS 264.6 MB） |

30 秒的看門狗在這條路徑上不是問題：單次呼叫最長是模擬器的第一次 search，約 3 秒。

## 宿主 API 的缺口

搜尋、解析、播放都**不需要**新的宿主 primitive。以下是發現的缺口與注意事項：

1. **二進位 body**：`HttpResponse.body` 是 UTF-8 解碼後的字串，request body 也只能是字串。
   這次用到的都是 JSON 端點，所以沒事。但 YouTube 的 SABR／UMP 串流與 protobuf 端點需要能安全傳送二進位的 body；
   墊片遇到二進位 request body 時直接拋錯，不去破壞資料。將來如果 web client 只剩 SABR，這裡就是缺口。
2. **計時器**：沒有 `setTimeout`。這條路徑用不到；LiveChat 或輪詢類的功能會用到。
3. **player JS**：萬一將來只剩需要解密（signature／`n`）的 client，就要下載約 2.5 MB 的 player JS，
   再用 meriyah 在 QuickJS 裡解析。這次沒有量它會不會碰到 30 秒看門狗；`new Function` 可以用（已測）。
   解析結果可以存進 `fmp.storage` 快取。
4. **播放後端的 log 會帶出簽名的媒體 URL**：mpv 的 log（`Opening https://…googlevideo.com/videoplayback?…`）含有完整 query。
   探針在寫 log 前自己遮掉了。正式的 `MediaKitBackend` 必須讓 mpv 的 log 經過 `Redactor`（ADR 0011）。
   這不是 YouTube.js 的問題，但只要播 YouTube 就一定會遇到。
5. **`allowedHosts` 夠用**：`youtube.com`（Innertube）、`googlevideo.com`（串流）、`ytimg.com`（封面）。
   有列 `googleapis.com`，但這次沒有用到。

## 這次連網做了什麼

全程未登入，沒有 cookie，也沒有 token。

- 約 20 次建立 Innertube 會話：每次 `sw.js_data` 加 `config`，有快取時是 0 次。
- 約 15 次 search。
- 約 25 次 player 請求：client 掃描含 VISIONOS、ANDROID_VR、IOS、TV、WEB_EMBEDDED。
- 約 60 次小範圍的 googlevideo GET，多數收到 header 就中斷。
- 2 次讀取音訊檔的後 20%。
- 4 次實際播放，各約 16 秒：Windows 2 次、Android 2 次。
- 另有 2 次 Windows 以 ANDROID_VR 播放，因 403 失敗。

沒有大量抓取。
