# 實驗：macOS 的 Now Playing 接法（M0 票 05）

macOS 上的系統媒體控制怎麼接：`audio_service` 在 macOS 的實作，或自己用 platform channel 接 `MPNowPlayingInfoCenter`、`MPRemoteCommandCenter`。標準照票：顯示標題、封面、播放狀態與進度；接收播放、暫停、上一首、下一首、seek。

實驗程式可丟棄，但留在這裡：換 macOS、Flutter 或套件版本時照〈怎麼跑〉重量。

## 結果（2026-11-11）

環境：macOS 27.0.1，Flutter 3.47.5，just_audio 0.10.6，audio_service 0.18.19。debug 建置。

| 項目 | audio_service 0.18.19 | 自己的 platform channel |
| --- | --- | --- |
| 顯示標題、歌手 | ✅ | ✅ |
| 顯示封面（本機檔） | ✅ | ✅ |
| 顯示封面（HTTP 網址） | ✅（audio_service 用 `flutter_cache_manager` 下載） | 沒測（要自己下載） |
| 播放狀態（面板的播放／暫停鈕跟著變） | ✅ | ✅ |
| 進度（面板進度條前進、暫停時停住、曲長 40 秒） | ✅ | ✅ |
| 面板：播放、暫停、下一首、上一首 | ✅ | ✅ |
| 面板：拖進度條 seek | ✅ | ✅ |
| 媒體鍵：播放／暫停、下一首、上一首 | ✅（播放／暫停經 `click` 轉成 play／pause） | ✅ |
| 關掉 App 後面板清空 | ✅ | ✅ |
| App 開著但還沒出過聲（重啟後不自動播放） | ❌ 不是 Now Playing App | ❌ 同左 |

每格的細節在 `results/<候選>-<情境>.json`：每一步的動作、App 收到的指令、面板讀回的內容、系統 log。面板截圖是 `results/*-panel.png`。

### 觀察

- **兩個候選的表現相同**。audio_service 的 macOS 原生端和 iOS 共用 `darwin/.../AudioServicePlugin.m`：會設 macOS 才有的 `MPNowPlayingInfoCenter.playbackState`（Apple 文件要求每次開始、停止播放都要設），`changePlaybackPosition` 要在 `PlaybackState.systemActions` 放 `MediaAction.seek` 才開。媒體鍵與 AirPods 的播放／暫停走 `togglePlayPauseCommand`，audio_service 轉成 `click(MediaButton.media)`，`BaseAudioHandler.click` 依 `playbackState.playing` 呼叫 `play` 或 `pause`，所以 `playbackState` 必須即時。
- **沒出過聲就不是 Now Playing App**（平台行為，兩個候選一樣）。`AUTOPLAY=false` 時，App 已送出曲目資訊與暫停狀態、channel 版也已註冊指令，系統 log 有 `CanBeNowPlaying changed to true`、`PlaybackState changed from Unknown to Paused`，但選單列沒有出現 Now Playing，等 25 秒也沒有。這時按媒體鍵，系統把 `TogglePlayPause` 轉給「音樂」App，並把它叫起來（第一次跑時實際發生，之後的 coldstart 情境改成不按）。audio_service 另外要等第一次 `playing=true` 才註冊 `MPRemoteCommandCenter`，但就算提早註冊（channel 版）也一樣。含意：重啟後要先在 App 裡按播放，系統媒體控制才會接到 FMP。
- **暫停後仍是 Now Playing App**：basic 情境暫停幾秒後再從面板或媒體鍵播放都收得到。暫停多久會被系統換掉沒有量。
- **封面**：audio_service 的 Dart 端把 `artUri` 下載成檔案（`flutter_cache_manager` 的 `DefaultCacheManager`，`cached_network_image` 預設也用它），原生端用 `NSImage` 讀檔。沙盒 App 要有 `com.apple.security.network.client`。`MediaItem.artHeaders` 可帶 header。
- 依賴：audio_service 會帶進 `flutter_cache_manager`、sqflite、rxdart、audio_session。Android、iOS 本來就用 audio_service（brief §6），所以 macOS 也用它不會讓 App 多出依賴。
- 沒測的候選：`flutter_media_session` 3.1.0（2026-11-08 發佈、repo 2026-04 才建）。它的 macOS 端沒有設 `playbackState`，而且太新，沒有實測。

## 驗證方式

macOS 15.4 起，第三方 App 經 MediaRemote 讀不到 Now Playing（brief 事實 M9）。這個實驗不讀 MediaRemote，改用三份證據：

1. **面板**：macOS 27 選單列的「正在播放」項目由 `MenuBarAgent` 提供（`AXIdentifier` 是 `com.apple.menuextra.now-playing`），點開後的面板是 ControlCenter 的視窗。呼叫端有「輔助使用」權限時，`np-panel.sh` 經 System Events 讀得到標題與歌手（一段文字）、按鈕（`backward.fill`、`play.fill` 或 `pause.fill`、`forward.fill`）、進度條的值與最大值（= 曲長）、有沒有封面的影像元素；也能按按鈕、設定進度條的值（= 拖進度條 seek）。封面對不對看截圖（`np-panel.sh shot`，要「螢幕錄製」權限）。
2. **App 收到的指令**：App 把收到的每個系統指令寫進容器暫存目錄的 `events.jsonl`，也印到 stdout。
3. **系統 log**：`mediaremoted` 記下每個指令（`Sending command … command = Pause, SenderBundleIdentifier = <com.apple.controlcenter>` 與目標 App）與播放狀態的變化（`PlaybackState changed from Playing to Paused`）。面板的指令來自 `com.apple.controlcenter`，媒體鍵來自 `com.apple.rcd`（和實體鍵同一條路）。用 `/usr/bin/log show --predicate 'process == "mediaremoted"'` 讀；zsh 的 `log` 是內建指令，要寫全路徑。

媒體鍵由 `mediakey.swift` 模擬：送出和實體鍵相同的 `NSSystemDefined`（subtype 8）事件，要「輔助使用」權限。

只有系統選為 Now Playing 的那一個 App 會出現在面板上（最近出過聲的那個），所以跑實驗時不要讓別的 App 播放。

## 檔案

| 路徑 | 內容 |
| --- | --- |
| `probe_common/` | 兩個候選共用：產生三首 40 秒的正弦波 WAV 與單色封面（不連網）、just_audio 播放器、畫面、指令紀錄；候選只實作 `NowPlayingBridge` |
| `probe_audio_service/` | 候選一：audio_service 的 `BaseAudioHandler` 當橋，播放器仍是 just_audio（`com.personal.fmp.exp.probeAudioService`） |
| `probe_channel/` | 候選二：`macos/Runner/MainFlutterWindow.swift` 的 `NowPlayingChannel`（約 100 行）加 Dart 端的 MethodChannel（`com.personal.fmp.exp.probeChannel`） |
| `run.py` | 建置、啟動、照情境操作、收集三份證據，寫 `results/<候選>-<情境>.json` |
| `np-panel.sh` | 讀與操作選單列的「正在播放」面板 |
| `mediakey.swift` | 模擬媒體鍵（`run.py` 編成 `build/mediakey`） |
| `results/` | 上表的原始結果與面板截圖。原始 log（`raw-*`）含本機路徑，不提交 |

## 怎麼跑

```bash
cd scripts/experiments/macos-now-playing
python3 run.py audio_service basic       # 自動播放；面板與媒體鍵的五個指令；關 App
python3 run.py channel basic
python3 run.py audio_service coldstart   # AUTOPLAY=false：沒出過聲時是不是 Now Playing App
python3 run.py channel coldstart
python3 run.py audio_service remote-art  # 封面改用本機 HTTP server 的網址
```

需要：

- Flutter 3.47.5、Xcode。實驗 App 的 bundle id 是 `com.personal.fmp.exp.*`，不碰 dev App（`com.personal.fmp.dev`）、模擬器與 `winpc`，所以不拿共用裝置鎖。
- 執行的終端機有「輔助使用」與「螢幕錄製」權限（讀面板、送媒體鍵、截圖）。
- 選單列的「正在播放」設成播放時顯示（系統預設）。
- App 會以 15% 音量播放測試音；跑的時候不要讓別的 App 播放。coldstart 情境在 App 不是 Now Playing 時不按媒體鍵，避免叫起「音樂」。
