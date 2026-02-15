// 视频标题解析器 — 从 Bilibili/YouTube 视频标题中提取歌曲信息
//
// 设计为抽象接口，当前实现为正则解析 [RegexTitleParser]。
// 未来可添加 AI 解析器实现同一接口。

/// 解析后的标题信息
class ParsedTitle {
  /// 歌曲名
  final String trackName;

  /// 歌手名（可能为 null）
  final String? artistName;

  /// 专辑名（通常为 null，多P视频可能有）
  final String? albumName;

  /// 清理后的完整标题（去除标签/后缀，用于全文搜索降级）
  final String cleanedTitle;

  const ParsedTitle({
    required this.trackName,
    this.artistName,
    this.albumName,
    required this.cleanedTitle,
  });

  @override
  String toString() =>
      'ParsedTitle(track: "$trackName", artist: ${artistName != null ? '"$artistName"' : 'null'}, '
      'album: ${albumName != null ? '"$albumName"' : 'null'}, cleaned: "$cleanedTitle")';
}

/// 标题解析器接口
abstract class TitleParser {
  /// 解析视频标题，提取歌曲信息
  ///
  /// [title] 视频标题
  /// [uploader] UP主/频道名（作为 artistName 的降级来源）
  ParsedTitle parse(String title, {String? uploader});
}

/// 基于正则表达式的标题解析器
class RegexTitleParser implements TitleParser {
  // ========== 标签词（共享，用于多种括号类型） ==========

  static const _tagWords =
      r'翻唱|cover|MV|PV|歌ってみた|弾いてみた|叩いてみた|演奏してみた|'
      r'Official|官方|自制|手书|MAD|AMV|MMD|VOCALOID|ボカロ|初音ミク|'
      r'オリジナル曲?|原创|原創|完整版|高音质|Hi-?Res|FLAC|4K|1080P|'
      r'中文字幕|歌词|Lyrics?|字幕|CC|合集|精选|剪辑|Clip|Live|现场|'
      r'Music\s*Video|Lyric\s*Video|Audio|Topic|Visualizer|'
      r'feat\.?[^】」』》\]]*|ft\.?[^】」』》\]]*';

  // ========== 清理用正则 ==========

  /// 【】内的标签词
  static final _bracketTagPattern = RegExp(
    '【($_tagWords)】',
    caseSensitive: false,
  );

  /// 「」内的标签词
  static final _jpQuoteTagPattern = RegExp(
    '「($_tagWords)」',
    caseSensitive: false,
  );

  /// ()内的后缀标签
  static final _parenTagPattern = RegExp(
    r'\s*[(\（](Official\s*(Music\s*)?Video|'
    r'Music\s*Video|MV|PV|Lyric\s*Video|Audio|'
    r'Official\s*Audio|Official\s*MV|Official\s*Lyric|'
    r'Visualizer|Topic|Live|现场|完整版|高音质|'
    r'Hi-?Res|FLAC|4K|1080P|中文字幕|歌词版|'
    r'cover|翻唱|歌ってみた|弾いてみた)[)\）]',
    caseSensitive: false,
  );

  /// ()内的动漫/影视标注
  static final _animeTagPattern = RegExp(
    r'\s*[(\（][^)\）]*(OP|ED|OST|OVA|主題歌|片頭曲|片尾曲|插曲|'
    r'エンディング|オープニング|Theme\s*Song)[^)\）]*[)\）]',
    caseSensitive: false,
  );

  /// 尾部常见后缀
  static final _trailingSuffixPattern = RegExp(
    r'\s*[-–—|]\s*(Official\s*(Music\s*)?Video|Music\s*Video|MV|'
    r'Lyric\s*Video|Audio|Visualizer|Topic)\s*$',
    caseSensitive: false,
  );

  /// 独立的 Official MV 等词（尾部）
  static final _standaloneTagPattern = RegExp(
    r'\s+(?:Official\s+(?:Music\s+)?Video|Official\s+MV|'
    r'Official\s+Audio|Official\s+Lyric)\s*$',
    caseSensitive: false,
  );

  /// PV付き等日文后缀
  static final _jpSuffixPattern = RegExp(
    r'[【\[「（(]オリジナル曲?PV付き?[】\]」）)]',
    caseSensitive: false,
  );

  // ========== 提取用正则 ==========

  /// 模式 A: "Artist - Title"
  static final _dashPattern = RegExp(r'^(.+?)\s*[-–—]\s*(.+)$');

  /// 模式 B: "Artist「Title」" / "Artist《Title》" / "Artist【Title】"
  static final _quotedTitlePattern = RegExp(
    r'^(.+?)\s*[「『《【](.+?)[」』》】]',
  );

  /// 模式 C: "Title / Artist"
  static final _slashPattern = RegExp(r'^(.+?)\s*/\s*(.+)$');

  /// 多余空格
  static final _multiSpace = RegExp(r'\s{2,}');

  /// artist 中的噪音词
  static final _artistNoisePattern = RegExp(
    r'\s*\b(MV|Official|Channel|チャンネル|VEVO)\b\s*',
    caseSensitive: false,
  );

  @override
  ParsedTitle parse(String title, {String? uploader}) {
    // Phase 1: 清理
    var cleaned = _clean(title);

    // Phase 2: 提取 artist / track
    String? artist;
    String? track;

    // 模式 B: Artist「Title」/ Artist【Title】（优先，括号很明确）
    var match = _quotedTitlePattern.firstMatch(cleaned);
    if (match != null) {
      artist = _postProcess(match.group(1)!);
      track = _postProcess(match.group(2)!);
    }

    // 模式 C: Title / Artist
    if (track == null) {
      match = _slashPattern.firstMatch(cleaned);
      if (match != null) {
        track = _postProcess(match.group(1)!.trim());
        artist = _postProcess(match.group(2)!.trim());
      }
    }

    // 模式 A: Artist - Title
    if (track == null) {
      match = _dashPattern.firstMatch(cleaned);
      if (match != null) {
        final left = match.group(1)!.trim();
        final right = match.group(2)!.trim();
        if (left.contains('「') || left.contains('『') || left.contains('《')) {
          track = _postProcess(left);
          artist = _postProcess(right);
        } else {
          artist = _postProcess(left);
          track = _postProcess(right);
        }
      }
    }

    // 降级：整个清理后标题作为 trackName
    track ??= _postProcess(cleaned);

    // 清理 artist 中的噪音词
    if (artist != null) {
      artist = _cleanArtist(artist);
    }

    // 如果没有提取到 artist，使用 uploader
    artist ??= uploader;

    // 如果 artist 和 track 相同，清除 artist
    if (artist != null && artist == track) {
      artist = uploader != artist ? uploader : null;
    }

    return ParsedTitle(
      trackName: track,
      artistName: artist,
      cleanedTitle: cleaned.trim(),
    );
  }

  /// 清理标题中的噪音
  String _clean(String title) {
    var result = title;

    // 移除【】内的标签词
    result = result.replaceAll(_bracketTagPattern, ' ');

    // 移除「」内的标签词
    result = result.replaceAll(_jpQuoteTagPattern, ' ');

    // 移除日文PV后缀
    result = result.replaceAll(_jpSuffixPattern, ' ');

    // 移除()内的后缀标签
    result = result.replaceAll(_parenTagPattern, ' ');

    // 移除()内的动漫/影视标注
    result = result.replaceAll(_animeTagPattern, ' ');

    // 移除尾部后缀
    result = result.replaceAll(_trailingSuffixPattern, '');

    // 移除独立的 Official MV 等词
    result = result.replaceAll(_standaloneTagPattern, '');

    // 移除 #hashtag
    result = result.replaceAll(RegExp(r'#\S+'), ' ');

    // 合并多余空格
    result = result.replaceAll(_multiSpace, ' ').trim();

    return result;
  }

  /// 后处理：清理残留括号、多余空格
  String _postProcess(String text) {
    var result = text.trim();

    // 去除整体包裹的括号
    final wrapMatch = RegExp(r'^[【「『《\[](.*?)[】」』》\]]$').firstMatch(result);
    if (wrapMatch != null) {
      result = wrapMatch.group(1)!;
    }

    // 移除残留的标签括号内容
    result = result.replaceAll(
      RegExp(
        r'\s*[(\（](cover|翻唱|feat\.?[^)\）]*|ft\.?[^)\）]*|'
        r'prod\.?[^)\）]*|remix|ver\.?|version|inst\.?|instrumental|'
        r'short|full|TV\s*size|anime\s*ver)[)\）]',
        caseSensitive: false,
      ),
      '',
    );

    // 移除尾部的 [xxx ver.] 等方括号标注
    result = result.replaceAll(
      RegExp(r'\s*\[(?:original\s*)?ver\.?[^\]]*\]', caseSensitive: false),
      '',
    );

    // 合并空格并 trim
    result = result.replaceAll(_multiSpace, ' ').trim();

    return result;
  }

  /// 清理 artist 名中的噪音词
  String _cleanArtist(String artist) {
    var result = artist;
    result = result.replaceAll(_artistNoisePattern, ' ');
    result = result.replaceAll(_multiSpace, ' ').trim();
    return result;
  }
}
