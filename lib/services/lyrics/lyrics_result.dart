/// 统一歌词搜索结果（适用于 lrclib / netease / qqmusic 等多个歌词源）
class LyricsResult {
  /// 外部 ID（lrclib/netease 为数字字符串，QQ 音乐为 songmid）
  final String id;
  final String trackName;
  final String artistName;
  final String albumName;
  final int duration; // 秒
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;

  /// 歌词来源标识（"lrclib" / "netease" / "qqmusic"）
  final String source;

  /// 翻译歌词（LRC 格式，网易云/QQ音乐）
  final String? translatedLyrics;

  /// 罗马音歌词（LRC 格式，网易云专用）
  final String? romajiLyrics;

  const LyricsResult({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.duration,
    required this.instrumental,
    this.plainLyrics,
    this.syncedLyrics,
    this.source = 'lrclib',
    this.translatedLyrics,
    this.romajiLyrics,
  });

  factory LyricsResult.fromJson(Map<String, dynamic> json) {
    // 兼容旧缓存：id 可能是 int 或 String
    final rawId = json['id'];
    final id = rawId is int ? rawId.toString() : (rawId as String? ?? '0');

    return LyricsResult(
      id: id,
      trackName: json['trackName'] as String? ?? '',
      artistName: json['artistName'] as String? ?? '',
      albumName: json['albumName'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      instrumental: json['instrumental'] as bool? ?? false,
      plainLyrics: json['plainLyrics'] as String?,
      syncedLyrics: json['syncedLyrics'] as String?,
      source: json['source'] as String? ?? 'lrclib',
      translatedLyrics: json['translatedLyrics'] as String?,
      romajiLyrics: json['romajiLyrics'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'trackName': trackName,
    'artistName': artistName,
    'albumName': albumName,
    'duration': duration,
    'instrumental': instrumental,
    'plainLyrics': plainLyrics,
    'syncedLyrics': syncedLyrics,
    'source': source,
    'translatedLyrics': translatedLyrics,
    'romajiLyrics': romajiLyrics,
  };

  /// 是否有同步歌词（LRC 格式）
  bool get hasSyncedLyrics =>
      syncedLyrics != null && syncedLyrics!.isNotEmpty;

  /// 是否有纯文本歌词
  bool get hasPlainLyrics =>
      plainLyrics != null && plainLyrics!.isNotEmpty;

  /// 是否有翻译歌词
  bool get hasTranslatedLyrics =>
      translatedLyrics != null && translatedLyrics!.isNotEmpty;

  /// 是否有罗马音歌词
  bool get hasRomajiLyrics =>
      romajiLyrics != null && romajiLyrics!.isNotEmpty;

  @override
  String toString() =>
      'LyricsResult(id: $id, "$trackName" by "$artistName", '
      'source: $source, album: "$albumName", ${duration}s, '
      'synced: $hasSyncedLyrics, plain: $hasPlainLyrics, '
      'translated: $hasTranslatedLyrics, romaji: $hasRomajiLyrics, '
      'id: $id)';
}
