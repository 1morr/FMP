# 代码修复记录 2026-03-19

## 1. 音源文件使用通用 Exception 而非类型化异常

**文件**: `lib/data/sources/bilibili_source.dart`, `lib/data/sources/youtube_source.dart`

**问题**: 多处使用 `throw Exception(...)` 而非 `BilibiliApiException` / `YouTubeApiException`。
`AudioController` 使用 `on SourceApiException` 统一捕获音源错误，通用 `Exception` 会绕过此 catch 块，
导致错误进入 generic catch，无法触发正确的重试/提示逻辑。

**修复**:
- `bilibili_source.dart`: 4 处 `throw Exception` → `throw BilibiliApiException`
  - `getAudioUrl()` 中 cid 获取失败 → `numericCode: -404`
  - `_getAudioStreamWithCid()` 无可用流 → `numericCode: -1`
  - `refreshAudioUrl()` source type 不匹配 → `numericCode: -3`
  - `getFavoritesList()` URL 解析失败 → `numericCode: -3`
- `youtube_source.dart`: 1 处 `throw Exception` → `throw YouTubeApiException`
  - `refreshAudioUrl()` source type 不匹配 → `code: 'invalid_source'`

---

## 2. classifyDioError 缺少常见 HTTP 状态码分类

**文件**: `lib/data/sources/source_exception.dart`

**问题**: `SourceApiException.classifyDioError()` 只处理 429/412（限流），
其他常见错误状态码（403、404、503）全部归入 `api_error`，丢失语义信息。

**修复**: 新增三个状态码分类：
- `403` → `code: 'forbidden'`（权限/地区限制）
- `404` → `code: 'not_found'`（资源不存在）
- `503` → `code: 'service_unavailable'`（服务暂时不可用）

---

## 3. 排行榜缓存刷新静默吞掉异常

**文件**: `lib/services/cache/ranking_cache_service.dart`

**问题**: `_refreshAll()` 中 `catchError((_) => {})` 完全忽略异常，
虽然 `refreshBilibili()` / `refreshYouTube()` 内部已有 try-catch，
但如果出现未预期的异常（如 StreamController 已关闭），会被静默吞掉，增加调试难度。

**修复**: `catchError` 回调中添加 `debugPrint` 日志输出。

---

## 4. lrclib 歌词自动匹配缺少 hasSyncedLyrics 检查

**文件**: `lib/services/lyrics/lyrics_auto_match_service.dart`

**问题**: `_tryNeteaseMatch()` 和 `_tryQQMusicMatch()` 都检查 `best.hasSyncedLyrics`，
只返回有同步歌词（LRC 格式）的结果。但 `_tryLrclibMatch()` 没有此检查，
可能返回只有纯文本歌词的结果，导致播放器歌词滚动功能无法使用。

**修复**: 在 `_tryLrclibMatch()` 返回前添加 `if (!result.hasSyncedLyrics) return null;`。

---

## 5. 歌词匹配魔法数字未提取为常量

**文件**: `lib/services/lyrics/lyrics_auto_match_service.dart`, `lib/core/constants/app_constants.dart`

**问题**: 时长容差 `10`（秒）在 3 处硬编码，得分阈值 `0.6` 在 1 处硬编码。
修改时容易遗漏某处，造成不一致。

**修复**:
- `AppConstants` 新增 `lyricsDurationToleranceSec = 10` 和 `lyricsMatchScoreThreshold = 0.6`
- 所有使用处替换为常量引用

---

## 6. 下载 Isolate 中手动拼接 JSON 字符串

**文件**: `lib/services/download/download_service.dart`

**问题**: Isolate 错误处理中使用 `'{"type":"...","message":"${e.message.replaceAll('"', r'\"')}"}'`
手动构造 JSON。这种方式无法正确处理反斜杠、换行符等特殊字符，可能导致 JSON 解析失败。

**修复**: 替换为 `jsonEncode({'type': '...', 'message': e.message})`，
利用标准库的 JSON 编码器正确转义所有特殊字符。
