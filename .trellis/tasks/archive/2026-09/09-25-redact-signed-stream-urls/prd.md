# Redact signed stream URLs from logs (#163)

## 目標

log 不再寫出完整的簽名串流網址。來源：GitHub issue #163。

## 現況（已讀程式碼確認）

`PreparedPlaybackMedia.debugUrl`（`lib/services/audio/playback_media.dart`）對
遠端媒體回傳 `url.toString()`，也就是含簽章與到期參數的完整網址。以下 log 行
直接印它或它的前綴：

| 位置 | 等級 | 內容 |
|------|------|------|
| `just_audio_service.dart` / `media_kit_audio_service.dart` `setNextMedia` | debug | `Next medium armed: <完整網址>` |
| 兩個後端的 advanced-to-next 監聽 | debug | `Backend advanced to next medium: <完整網址>` |
| 兩個後端的 `playUrl` / `setUrl` | debug | 網址前 80 / 50 字元 |
| `playback_request_session.dart` fallback | **info** | `(failed URL: <完整網址>)` |
| `audio_provider.dart` `_onBackendAdvanced` | **warning** | `arm (<完整網址>)` |

後兩行是 info / warning，release build 也會寫，比 issue 描述的範圍大。

簽名不只在 query：YouTube HLS manifest 與網易雲的網址把到期時間與簽章放在
path 段裡，所以「只去掉 query」不夠。

`debugUrl` 同時是 fallback 的比對鍵（`failedUrl` / `attemptedUrl` 會和來源
adapter 回傳的網址逐字比對），不能改它的值。

## 需求

- 上表每一行改為只寫出不含簽章的標籤：scheme + host + 最後一個 path 段
  （例 `https://upos-sz-mirror.bilivideo.com/…/123-1-30280.m4s`）。本機檔案
  照舊寫路徑。
- 兩個後端寫出的標籤格式一致（ADR 0003）。
- `debugUrl` 的值與 fallback 比對行為不變。
- 更新 `.trellis/spec/shared/errors-and-logging.md` 裡「Signed stream URLs are
  **not** redacted」那一條。

## 不在範圍

- 引擎回報的錯誤字串（`media_kit error: $error`、`logError(..., e)` 的例外內容）
  是否含網址：沒有 repro，不修。
- `AppLogger.redactSensitive` 的通用網址遮蔽：會一併遮掉 API 與使用者輸入的
  網址（播放清單網址、電台匯入網址），不是這個 issue 要的。
- 非串流網址的 log（YouTube 播放清單網址、電台匯入網址）：不含簽章。

## 驗收

- [ ] 新增的測試在修正前會紅：`MediaKitAudioService`（假引擎）開啟遠端媒體、
      排入下一首、推進到下一首後，`AppLogger.logs` 不含簽章參數與完整網址。
- [ ] 新增的測試在修正前會紅：`PlaybackRequestSession` 走 fallback、控制器收到
      未 arm 的推進時，`AppLogger.logs` 不含完整網址。
- [ ] `JustAudioService` 在 `flutter test` 裡建不起來；由
      `audio_backend_shared_rules_static_rule_test.dart` 釘住兩個後端都轉呼叫
      同一個遮蔽函式（ADR 0003 的既有做法）。
- [ ] 遮蔽函式有純函式測試，覆蓋 query 簽章、path 簽章、無 path、解析失敗。
- [ ] `flutter test test/services/audio`、`flutter test test/core/logger` 通過；
      `flutter analyze`、`dart format` 乾淨。
