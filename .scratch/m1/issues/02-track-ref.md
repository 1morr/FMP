# 02: 插件 id 與曲目 id 成對的型別

Status: done
Blocked by: None
讀: brief §5.3；`GLOSSARY.md`〈曲目〉；`app/lib/domain/track.dart`；spec〈共同規則〉

## What to build

曲目的身分改成一個型別，把提供它的插件 id 和曲目 id 綁在一起，取代現在的裸字串 `Track.source` 加 `Track.id`。佇列、臨時播放、持久化與系統媒體控制都拿這個型別當鍵，之後找插件、寫 log、存資料庫都從它來。純 Dart，放 `domain/`。名詞缺的話照〈擁有者確認〉補進 `GLOSSARY.md`。

## 驗收

- [x] 新型別有相等與 hash，可以當 map 的鍵；有單元測試。
- [x] `Track`、插件宿主找插件、`Playback`、log 的 `logId` 都改用它，沒有地方再單獨傳插件 id 字串。
- [x] 依賴規則測試照過（Dart 端沒有音源識別碼的字面值）。
- [x] 四平台實跑搜尋並播放一首。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments

### 做了什麼

- `domain/track.dart` 加 `TrackRef(pluginId, trackId)`（相等、hash、`logId`），`Track` 改成持有 `ref`，拿掉 `source`、`id` 與 `Track.logId`，不留轉接。
- `PluginHost.pluginFor(TrackRef)`；`Plugin.resolveStream(TrackRef)`，收到別的插件的曲目丟 `ArgumentError`；`Playback` 用 `track.ref` 找插件、解析串流、寫 log。
- 測試：`test/domain/track_test.dart`（相等、兩個插件的同一個曲目 id 是兩個鍵、log 格式）；`plugin_host_test` 補「別的插件的曲目是程式錯誤」，其餘測試與契約測試的輔助函式跟著改。

### 驗證

- 四平台實跑（匿名，各搜一次 `lemon`、播第一首 `BV1tY411B7T9`，持共用裝置鎖；截圖留在暫存目錄）：
  - macOS：列出 B 站結果；第一次播放 AVPlayer 回 `NetworkError (code -1200: A TLS error…)`，CDN 是 `upos-hz-mirrorakam.akamaized.net`；隨後 `nscurl --ats-diagnostics` 對同一台主機全過。在同一個畫面再點一次（沒有重新搜尋）就播起來，讀回「播放中 0:08 / 4:18」。log 的曲目是 `bilibili/BV1tY411B7T9`，代表 `logId` 已經改由 `TrackRef` 產生。
  - iOS 模擬器：剪貼簿放 `lemon`，長按欄位叫出 Paste 貼上（單一 gesture 帶 60 個 move 點才算長按），讀回欄位是 `lemon` 才按搜尋；讀回「播放中 0:08 / 4:18」。先前試過一次 `orca emulator type`，硬體鍵盤的注音把字吃成組字中的注音，沒有送出搜尋。
  - Android 模擬器：`adb shell input text lemon`，讀回欄位是 `lemon` 才按搜尋；讀回「Playing 0:13 / 4:18」。
  - Windows（`winpc`，擁有者開機後補做，合併 main 之後的 87284c2e）：`shot.ps1 -Type lemon -Click 200,262 -ClickWait 10`，`foreground_is_fmp_*` 全是 True；點第一首「在百万豪装录音棚大声听米津玄师《Lemon》【Hi-res】」，讀回「播放中 0:09 / 4:18」（mp4a.40.2 · 193 kbps）；log 有搜尋、`pagelist`、`playurl?bvid=BV1tY411B7T9` 三個請求，關閉時 `exited_after_close=True`。
- 完整閘門（`dart run tool/check.dart`，commit 87284c2e，`winpc` 開機後重跑）全綠，exit 0：

```
ok   i18n (slang)
ok   codegen (build_runner)
ok   format
ok   analyze
ok   test
ok   schema snapshot (drift)
ok   doc gate
ok   doc gate tests
ok   build macos
ok   build ios
ok   build android
ok   lock shared devices
ok   build windows
ok   integration_test macos: integration_test/app_test.dart
ok   integration_test macos: integration_test/search_and_play_test.dart
ok   integration_test ios: integration_test/app_test.dart
ok   integration_test ios: integration_test/search_and_play_test.dart
ok   integration_test android: integration_test/app_test.dart
ok   integration_test android: integration_test/search_and_play_test.dart
ok   integration_test windows: integration_test/app_test.dart
ok   integration_test windows: integration_test/search_and_play_test.dart
ok   unlock shared devices
ok   plugin bundles (esbuild)
```

  先前在 7950c40b 跑的那次，只有 Windows 三步紅（`winpc` 離線），其餘同上。

  `build windows` 停在 `sync.sh` 打包：`tar` 讀不到 `app/android/.kotlin/sessions/` 底下一個 Gradle 執行時才有的暫存檔；兩個 integration_test 是 `ssh: … Host is down`。

### code-review（54d10543 起）

已處理：`TrackRef` 的 doc 只寫現在的用途（原本預告了佇列、持久化、系統媒體控制）；`pluginFor`、`resolveStream` 的參數改名 `ref`；契約測試輔助函式的參數改名 `trackId`，訊息改成 `empty track id`。

未處理：

- 名詞表〈曲目〉寫「由音源和識別碼確定」，程式寫的是插件 id。審查建議補半句「程式裡以插件 id 表示音源」；這要擁有者確認，這次沒改。
- `resolveStream` 先檢查插件 id、才檢查有沒有宣告這個能力：沒宣告能力的插件收到別人的曲目，丟的是 `ArgumentError`，不是 `Unsupported`。目前沒有呼叫者會走到這條路。
- `pluginFor` 只能用曲目找插件。之後的登入、會員狀態手上沒有曲目，到時要另開入口。
- `track.ref.logId` 多了一層呼叫；`logId` 和 `toString` 輸出一樣。都留著。

Session 紀錄：2026-11-15 曲目身分改成 `TrackRef`，宿主、播放與 log 都用它；三平台實跑搜尋並播放，`winpc` 離線，Windows 實跑與閘門沒做
決定：曲目身分是 `domain/` 的 `TrackRef(pluginId, trackId)`，`Track` 只留 `ref`，不保留 `source`、`id` 轉接（Agent 定）
決定：`Plugin.resolveStream` 收 `TrackRef`，不是這個插件的曲目丟 `ArgumentError`，把「只交回同一個插件」變成斷言（Agent 定）
決定：名詞表不加詞，〈曲目〉已定義身分由音源與識別碼確定，`TrackRef` 是它在程式裡的型別（Agent 定）
決定：`logId` 搬到 `TrackRef`（`<插件 id>/<曲目 id>`），`toString` 輸出相同（Agent 定）
變更：無
等使用者：`winpc`（跑 Windows 建置與測試的那台電腦）從 session 開始就連不上（ping 不通、ssh 回 Host is down）。選項：開機並登入桌面，讓接手的 session 補做 Windows 實跑與完整閘門；或者這張票先不管 Windows。建議開機補做。不處理的話，這張票不能改 done，也不能合併。
決定：使用者已把 winpc 開機，補做 Windows 實跑與完整閘門（使用者定）
Session 紀錄：2026-11-15 winpc 開機後合併 main、補做 Windows 實跑與完整閘門（全綠），票改 done
