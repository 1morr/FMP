# test/manual

跑起來就一直跑、要靠人看結果的探針。**不是測試** —— 這裡的檔案一律不叫
`*_test.dart`，否則 `flutter test` 會把它們撿走然後永遠等下去。

| 檔案 | 用途 |
|------|------|
| `pathological_stream_servers.dart` | 兩個故意壞掉的 HTTP 音訊伺服器，用來重現「一直轉圈」與「一卡一卡」兩種播放症狀 |

## pathological_stream_servers.dart

```bash
dart run test/manual/pathological_stream_servers.dart
```

同時起兩個 port（可用 `--hold-port` / `--stall-port` / `--host` 覆寫）：

- **hold**（預設 8742）：回 `200` + `Content-Length` + WAV header 之後**一個位元組都不送、
  也不關閉連線**。重現「連得上但零位元組」。
- **stall**（預設 8741）：送 4 秒音訊之後直接切斷連線，之後所有帶 `Range` 的重連一律拒絕。
  重現「播到一半連線斷掉」。

Windows 端用 `http://127.0.0.1:<port>/...`，Android 模擬器用 `http://10.0.2.2:<port>/...`。

**為什麼需要它們**：這兩種病態沒有辦法用單元測試代替 —— 要驗的正是音訊引擎
（mpv / ExoPlayer）自己對一條生病的連線會做什麼，而那是 FMP 這一側看不到、
也沒有辦法假造的。真實 CDN 也不會配合你演出這兩種行為。

各平台的實測基準記在 `docs/review/02-playback-sources.md` §12.14，
程式碼開頭的註解也抄了一份。
