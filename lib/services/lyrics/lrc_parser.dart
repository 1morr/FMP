// LRC 格式歌词解析器
//
// 支持标准 LRC 时间戳格式：[mm:ss.xx] 或 [mm:ss.xxx]
// 参考：https://en.wikipedia.org/wiki/LRC_(file_format)

/// 一行歌词（带时间戳）
class LyricsLine {
  final Duration timestamp;
  final String text;

  /// 附加文本（翻译/罗马音），显示在原文下方
  final String? subText;

  const LyricsLine({required this.timestamp, required this.text, this.subText});

  /// 创建带 subText 的副本
  LyricsLine withSubText(String? subText) =>
      LyricsLine(timestamp: timestamp, text: text, subText: subText);

  @override
  String toString() => 'LyricsLine(${timestamp.inMilliseconds}ms, "$text"${subText != null ? ', sub: "$subText"' : ''})';
}

/// LRC 格式解析结果
class ParsedLyrics {
  /// 按时间排序的歌词行
  final List<LyricsLine> lines;

  /// 是否为同步歌词（有时间戳）
  final bool isSynced;

  const ParsedLyrics({required this.lines, required this.isSynced});

  /// 是否为空
  bool get isEmpty => lines.isEmpty;

  /// 是否非空
  bool get isNotEmpty => lines.isNotEmpty;

  /// 是否有任何行包含附加文本
  bool get hasSubText => lines.any((l) => l.subText != null && l.subText!.isNotEmpty);
}

/// LRC 格式解析器
class LrcParser {
  // [mm:ss.xx] 或 [mm:ss.xxx]
  static final _timestampRegex = RegExp(r'\[(\d{1,2}):(\d{2})\.(\d{2,3})\]');

  /// 解析歌词内容
  ///
  /// 优先使用同步歌词（syncedLyrics），如果没有则使用纯文本歌词（plainLyrics）。
  /// 返回 null 如果两者都为空。
  static ParsedLyrics? parse(String? syncedLyrics, String? plainLyrics) {
    // 优先解析同步歌词
    if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
      final lines = _parseSynced(syncedLyrics);
      if (lines.isNotEmpty) {
        return ParsedLyrics(lines: lines, isSynced: true);
      }
    }

    // 回退到纯文本歌词
    if (plainLyrics != null && plainLyrics.isNotEmpty) {
      final lines = _parsePlain(plainLyrics);
      if (lines.isNotEmpty) {
        return ParsedLyrics(lines: lines, isSynced: false);
      }
    }

    return null;
  }

  /// 解析同步歌词（LRC 格式）
  static List<LyricsLine> _parseSynced(String text) {
    final lines = <LyricsLine>[];

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 一行可能有多个时间戳：[00:12.34][00:56.78]歌词内容
      final matches = _timestampRegex.allMatches(trimmed).toList();
      if (matches.isEmpty) continue;

      // 歌词文本在最后一个时间戳之后
      final lastMatch = matches.last;
      final text = trimmed.substring(lastMatch.end).trim();

      // 跳过空歌词行（间奏标记等）
      if (text.isEmpty) continue;

      // 为每个时间戳创建一行
      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final msStr = match.group(3)!;
        // 处理 2 位和 3 位毫秒
        final milliseconds = msStr.length == 2
            ? int.parse(msStr) * 10
            : int.parse(msStr);

        final timestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        lines.add(LyricsLine(timestamp: timestamp, text: text));
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  /// 解析纯文本歌词（无时间戳）
  static List<LyricsLine> _parsePlain(String text) {
    final lines = <LyricsLine>[];

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 纯文本歌词没有时间戳，使用 Duration.zero
      lines.add(LyricsLine(timestamp: Duration.zero, text: trimmed));
    }

    return lines;
  }

  /// 将附加歌词（翻译/罗马音）合并到原文歌词中
  ///
  /// 通过时间戳匹配，将 [subLyricsText] 中的对应行作为 subText 附加到原文行上。
  /// 如果 [subLyricsText] 为空或无法解析，返回原始 [lyrics] 不变。
  static ParsedLyrics mergeSubLyrics(ParsedLyrics lyrics, String? subLyricsText) {
    if (subLyricsText == null || subLyricsText.isEmpty) return lyrics;
    if (!lyrics.isSynced) return lyrics;

    final subLines = _parseSynced(subLyricsText);
    if (subLines.isEmpty) return lyrics;

    // 构建时间戳 → subText 映射（毫秒精度）
    final subMap = <int, String>{};
    for (final sub in subLines) {
      subMap[sub.timestamp.inMilliseconds] = sub.text;
    }

    // 合并：为每行原文查找对应时间戳的 subText
    final merged = lyrics.lines.map((line) {
      final sub = subMap[line.timestamp.inMilliseconds];
      return sub != null ? line.withSubText(sub) : line;
    }).toList();

    return ParsedLyrics(lines: merged, isSynced: true);
  }

  /// 根据当前播放位置找到当前歌词行索引
  ///
  /// [lines] 按时间排序的歌词行
  /// [position] 当前播放位置
  /// [offsetMs] 用户设置的偏移（正值=歌词提前，负值=歌词延后）
  ///
  /// 返回 -1 表示还没到第一行歌词
  static int findCurrentLineIndex(
    List<LyricsLine> lines,
    Duration position,
    int offsetMs,
  ) {
    if (lines.isEmpty) return -1;

    // 应用偏移：position + offset = 歌词时间轴上的位置
    final adjustedMs = position.inMilliseconds + offsetMs;

    // 二分查找最后一个 timestamp <= adjustedMs 的行
    int low = 0;
    int high = lines.length - 1;
    int result = -1;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].timestamp.inMilliseconds <= adjustedMs) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return result;
  }
}
