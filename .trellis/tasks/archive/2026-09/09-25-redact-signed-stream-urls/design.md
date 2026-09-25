# Design

## 邊界

遮蔽放在 `lib/services/audio/playback_media.dart`，跟 `PreparedPlaybackMedia`
同一處：網址的「哪一部分能寫進 log」是媒體描述的知識，不是 logger 的。

```dart
/// 串流網址寫進 log 的形狀：scheme + host + 最後一個 path 段。
String redactStreamUrl(String url);

sealed class PreparedPlaybackMedia {
  /// fallback 比對鍵；含簽章，不寫進 log。
  String get debugUrl;

  /// 寫進 log 用的標籤。
  String get logLabel;
}
```

- `RemotePlaybackMedia.logLabel` → `redactStreamUrl(url.toString())`。
- `LocalPlaybackMedia.logLabel` → `path`。
- `redactStreamUrl`：`Uri.tryParse`；沒有 host 時回 `'[unparsed URL]'`；有 path 段時
  `'$scheme://$host/…/$last'`，沒有時 `'$scheme://$host'`。

取 host + 最後一段的理由：host 分得出 CDN mirror（除錯最常用的資訊），最後一段
分得出容器格式（`.m4s` / `.m3u8` / `.flac`）；三個來源的簽章都在 query 或中間
的 path 段，不在最後一段。

`debugUrl` 不改名：它是 fallback 的比對鍵，改名會牽動 session 與測試，不是這個
issue 的範圍。在 dartdoc 寫清楚「不寫進 log」。

## 呼叫點

| 檔案 | 改成 |
|------|------|
| 兩個後端 `playUrl` / `setUrl` | `redactStreamUrl(url)`，拿掉 substring 截斷 |
| 兩個後端 arm / advanced | `media.logLabel` |
| `playback_request_session.dart` fallback info | `selection.media.logLabel` |
| `audio_provider.dart` `_onBackendAdvanced` warning | `media.logLabel` |

## 閘門

- 行為：`media_kit_audio_service_state_test.dart` 的假引擎、
  `playback_request_session_test.dart`、`audio_controller_next_medium_test.dart`
  各加一條，讀 `AppLogger.logs`。
- 靜態：`audio_backend_shared_rules_static_rule_test.dart` 的 `_sharedUnits`
  加上 `playback_media.dart`，`_delegation` 的兩個真後端加 `redactStreamUrl`。
  既有的 mutation 測試覆蓋入口解析；新入口只是資料，不需要新的 mutation 測試。
- 純函式：`playback_media_test.dart`。

## 替代方案

- **在 `AppLogger.redactSensitive` 統一遮網址**：一個閘門涵蓋所有未來的 log 行，
  但會把 API 請求、播放清單網址這類除錯需要的網址一併遮掉；而且 path 段簽章要
  靠猜測式 regex 才抓得到。否決。
- **只遮 query**：YouTube HLS 與網易雲把簽章放在 path，不夠。否決。

## 回退

單一 commit，`git revert` 即可；不碰持久化資料與對外介面。
