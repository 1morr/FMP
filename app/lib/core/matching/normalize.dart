/// 匹配用的正規化（M4 design §8.1）：折疊、拆括號、去裝飾、找版本、拆歌手。
///
/// 只給 `matching.dart` 用；詞表是以 `test/core/matching/match_corpus.dart` 的語料
/// 校準的，改了要語料全綠。
library;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'ts_characters.g.dart';

/// NFKC → 小寫 → 繁簡統一（OpenCC 字表，字級）。兩邊都經過同一張表，
/// 所以 `乾隆` 折成 `干隆` 也兩邊一致。
String foldText(String text) {
  final lowered = unorm.nfkc(text).toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lowered.runes) {
    buffer.writeCharCode(tsCharacters[rune] ?? rune);
  }
  return buffer.toString();
}

final _notWordCharacter = RegExp(r'[^\p{L}\p{N}\p{M}]+', unicode: true);

/// 只留字母、數字（含 CJK）與附加符號，去掉標點與空白。
String compact(String folded) => folded.replaceAll(_notWordCharacter, '');

const _cjkCharacters =
    r'\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}ー';

final _cjk = RegExp('[$_cjkCharacters]', unicode: true);

final _scriptRun = RegExp(
  '[$_cjkCharacters]+|[^$_cjkCharacters]+',
  unicode: true,
);

/// 依文字系統切段：CJK（漢字、假名、諺文）與其他（拉丁字母、數字）交替處切開。
/// `晴天sunnyday` → `晴天`、`sunnyday`。輸入是 [compact] 過的字串。
List<String> scriptRuns(String compacted) => [
  for (final run in _scriptRun.allMatches(compacted)) run[0]!,
];

final _latinOrDigit = RegExp(r'[\p{Script=Latin}\p{N}]', unicode: true);

/// 拉丁字的邊界：前後不是拉丁字母或數字。CJK 緊貼著也算邊界（`晴天mv`）。
const _latinBefore = r'(?<![\p{Script=Latin}\p{N}])';
const _latinAfter = r'(?![\p{Script=Latin}\p{N}])';

/// 比對一個名稱（歌手）的 pattern：名稱的字母之間允許任意標點與空白
/// （`g.e.m.邓紫棋` 對得上 `gem 邓紫棋`），頭尾是拉丁字母或數字時要在拉丁字的邊界
/// （`sia` 不比到 `asia`）。名稱 [compact] 後不到兩個字回 `null`。
RegExp? namePattern(String folded) {
  final characters = [
    for (final rune in compact(folded).runes) String.fromCharCode(rune),
  ];
  if (characters.length < 2) return null;
  final body = characters.map(RegExp.escape).join(r'[^\p{L}\p{N}]*');
  final start = _latinOrDigit.hasMatch(characters.first) ? _latinBefore : '';
  final end = _latinOrDigit.hasMatch(characters.last) ? _latinAfter : '';
  return RegExp('$start$body$end', unicode: true);
}

/// 拆多位歌手（design §8.1）。輸入是 [foldText] 過的字串（全形的 `，；` 經 NFKC
/// 已是半形）。
List<String> splitArtists(String folded) => [
  for (final part in folded.split(_artistSeparator))
    if (compact(part).isNotEmpty) part.trim(),
];

final _artistSeparator = RegExp(
  r'\s*(?:/|、|,|&|;|×|\bfeat\.?(?=\s)|\bft\.?(?=\s)|\bfeaturing\b|\s+x\s+)\s*',
);

/// 同 [splitArtists]，但輸入是插件給的原字串（沒有 [foldText]）：分隔符不分大小寫，
/// 全形的 `，；` 也認。各段保留原文（給搜尋的關鍵字用）。
List<String> splitRawArtists(String raw) => [
  for (final part in raw.split(_rawArtistSeparator))
    if (compact(foldText(part)).isNotEmpty) part.trim(),
];

final _rawArtistSeparator = RegExp(
  r'\s*(?:/|、|,|，|&|;|；|×|\bfeat\.?(?=\s)|\bft\.?(?=\s)|\bfeaturing\b|\s+x\s+)\s*',
  caseSensitive: false,
);

/// 上傳者名稱裡不是歌手的部分：YouTube 自動產生的 `- Topic` 頻道、VEVO 頻道。
final _uploaderDecoration = RegExp(r'\s*-\s*topic\s*$|vevo\s*$');

/// 去掉 [_uploaderDecoration]。
String stripUploaderDecoration(String folded) =>
    folded.replaceAll(_uploaderDecoration, '');

/// 標題要清掉多少。原曲的標題清完沒有字時，那些字就是歌名（`Karaoke`、`Audio`
/// 整首歌名是詞表的詞；Black Sabbath 的 `Black Sabbath` 與歌手同名），改用下一級；
/// 候選用原曲那一級，兩邊才比得起來。
enum TitleCleaning {
  /// 拿掉原曲歌手、版本標記與裝飾。
  full,

  /// 只拿掉原曲歌手；版本標記照樣找，但留在文字裡。
  keepKeywords,

  /// 都留著（版本標記照樣找）。
  none,
}

/// 原曲的標題：歌名本體（[compact] 過）、版本標記（[_versionKeywords] 的值）與
/// 用到的 [TitleCleaning]。
///
/// Spotify 的 ` - Live`、` - Remastered 2011` 這類後綴與括號都不算歌名，歌名本體
/// 只取第一段；版本標記從整個標題找。[artists]（原曲歌手的 [namePattern]）從
/// 標題裡拿掉（`See You Again (feat. Charlie Puth)`）。
({String core, Set<String> versions, TitleCleaning cleaning}) parseQueryTitle(
  String title,
  List<RegExp> artists,
) {
  final folded = foldText(title);
  var cleaning = TitleCleaning.full;
  var cleaned = _clean(folded, artists, cleaning);
  while (compact(cleaned.text).isEmpty && cleaning != TitleCleaning.none) {
    cleaning = TitleCleaning.values[cleaning.index + 1];
    cleaned = _clean(folded, artists, cleaning);
  }
  final core = cleaned.text
      .replaceAll(_bracketSegment, ' ')
      .split(_suffixSeparator)
      .map(compact)
      .firstWhere((part) => part.isNotEmpty, orElse: () => '');
  return (
    core: core.isNotEmpty ? core : compact(cleaned.text),
    versions: cleaned.versions,
    cleaning: cleaning,
  );
}

/// 候選（上傳）的標題：可能是歌名本體的片段與版本標記。
///
/// 片段都 [compact] 過、非空：去掉括號後的主標題、主標題以分隔符切開的每一段、
/// 每個括號的內容，以及它們依文字系統切開的每一段（[scriptRuns]）。上傳標題的
/// 歌名常在括號裡、與譯名並列（`周杰倫【晴天 Sunny Day】Official MV`），或與歌手名
/// 以 ` - ` 隔開。[artists] 是原曲歌手的 [namePattern]，先從標題裡拿掉；
/// [cleaning] 是 [parseQueryTitle] 給原曲用的那一級。
({List<String> variants, Set<String> versions}) parseCandidateTitle(
  String title,
  List<RegExp> artists,
  TitleCleaning cleaning,
) {
  final cleaned = _clean(foldText(title), artists, cleaning);
  final segments = [
    for (final match in _bracketSegment.allMatches(cleaned.text))
      match.groups([1, 2, 3, 4, 5, 6]).nonNulls.single,
  ];
  final main = cleaned.text.replaceAll(_bracketSegment, ' ');
  final pieces = {
    main,
    ...main.split(_titleSeparator),
    ...segments,
  }.map(compact).where((piece) => piece.isNotEmpty);
  final variants = <String>{};
  for (final piece in pieces) {
    variants
      ..add(piece)
      ..addAll(scriptRuns(piece));
  }
  return (variants: variants.toList(), versions: cleaned.versions);
}

/// 依序：拿掉原曲歌手、抽出版本標記、去掉裝飾與 feat.；[cleaning] 決定哪些
/// 從文字裡拿掉。
({String text, Set<String> versions}) _clean(
  String folded,
  List<RegExp> artists,
  TitleCleaning cleaning,
) {
  var text = folded;
  if (cleaning != TitleCleaning.none) {
    for (final artist in artists) {
      text = text.replaceAll(artist, ' ');
    }
  }
  final versions = <String>{};
  for (final MapEntry(key: pattern, value: version) in _versionPatterns) {
    if (pattern.hasMatch(text)) {
      versions.add(version);
      if (cleaning == TitleCleaning.full) text = text.replaceAll(pattern, ' ');
    }
  }
  if (cleaning == TitleCleaning.full) text = text.replaceAll(_decoration, ' ');
  text = text.replaceAll(_featuring, ' ');
  return (text: text, versions: versions);
}

/// 括號（design §8.1 的五種，加上日文常用的 `『』` 與 B 站常用的 `〖〗`）。
/// 全形的 `（）［］` 經 NFKC 已是半形。不處理巢狀：不同種的（`【…(…)…】`）外層
/// 整段算一個；同種的（`(…(…)…)`）只抽出最內層，外層的括號留在主標題當標點。
final _bracketSegment = RegExp(
  r'\(([^()]*)\)|\[([^\[\]]*)\]|【([^【】]*)】|「([^「」]*)」|『([^『』]*)』|〖([^〖〗]*)〗',
);

/// 上傳標題裡隔開歌手與歌名的符號。` - ` 要有空白（`hi-fi` 不切）。
final _titleSeparator = RegExp(r'\s+[-–—~]+\s+|[|/]');

/// 原曲標題的後綴分隔（Spotify 的 `Title - Live`）。
final _suffixSeparator = RegExp(r'\s+[-–—]\s+');

final _featuring = RegExp(r'\b(?:feat|ft|featuring)\b\.?');

/// 拉丁字的詞表比對要在字的邊界；CJK 沒有空白，直接比子字串。長的詞先比
/// （`official video` 先於 `official`）；含 CJK 的詞排在前面，`dj版` 先於 `dj`。
/// 拉丁字的邊界放在整組外面共用：每個詞各帶一份時，每個位置要對每個詞各做一次
/// lookbehind，一次 `rank` 慢好幾倍。
RegExp _keywords(List<String> words) {
  final sorted = [...words]..sort((a, b) => b.length.compareTo(a.length));
  final cjk = [
    for (final word in sorted)
      if (_cjk.hasMatch(word)) RegExp.escape(word),
  ];
  final latin = [
    for (final word in sorted)
      if (!_cjk.hasMatch(word)) RegExp.escape(word),
  ];
  return RegExp(
    [
      ...cjk,
      if (latin.isNotEmpty) '$_latinBefore(?:${latin.join('|')})$_latinAfter',
    ].join('|'),
    unicode: true,
  );
}

/// 不影響是不是同一首的裝飾：畫質、字幕、MV、官方等。兩邊都去掉。詞表是繁簡統一
/// 之後的寫法（簡體）。
final _decoration = _keywords([
  'official music video',
  'official lyric video',
  'official video',
  'official audio',
  'official mv',
  'official pv',
  'music video',
  'lyric video',
  'lyrics video',
  'music clip',
  'visualizer',
  'with lyrics',
  'lyrics',
  'lyric',
  'official',
  'audio',
  'mv',
  'pv',
  'm/v',
  'hd',
  'hq',
  'uhd',
  '4k',
  '8k',
  '1080p',
  '720p',
  '60fps',
  'hi-res',
  'hires',
  'flac',
  'ost',
  'soundtrack',
  'remastered',
  'remaster',
  '中文字幕',
  '中英字幕',
  '中日字幕',
  '中字',
  '字幕',
  '官方',
  '高清',
  '超清',
  '高音质',
  '高品质',
  '无损音质',
  '无损',
  '完整版',
  '动态歌词',
  '歌词版',
  '歌词',
  '首发',
  '修复',
  '公式',
]);

/// 版本標記：同一首歌的不同錄音。兩邊的集合不同時標題分打折
/// （`matching.dart` 的 `versionMismatchFactor`）。鍵是詞，值是標記。
const _versionKeywords = {
  'live': 'live',
  '现场版': 'live',
  '现场': 'live',
  '演唱会': 'live',
  'concert': 'live',
  'cover': 'cover',
  'covered by': 'cover',
  '翻唱': 'cover',
  '翻自': 'cover',
  '女声版': 'cover',
  '男声版': 'cover',
  'instrumental': 'instrumental',
  'inst': 'instrumental',
  'karaoke': 'instrumental',
  'off vocal': 'instrumental',
  'backing track': 'instrumental',
  '伴奏': 'instrumental',
  '纯音乐': 'instrumental',
  '消音': 'instrumental',
  'カラオケ': 'instrumental',
  'remix': 'remix',
  '混音': 'remix',
  'dj': 'remix',
  'dj版': 'remix',
  'mashup': 'remix',
  'acoustic': 'acoustic',
  'unplugged': 'acoustic',
  '不插电': 'acoustic',
  'piano version': 'piano',
  'piano ver': 'piano',
  '钢琴版': 'piano',
  'sped up': 'altered',
  'speed up': 'altered',
  'slowed': 'altered',
  'nightcore': 'altered',
  '加速版': 'altered',
  '降调': 'altered',
  '升调': 'altered',
  '片段': 'excerpt',
  '铃声': 'excerpt',
  'tv size': 'excerpt',
  'tv ver': 'excerpt',
  'short ver': 'excerpt',
  'demo': 'demo',
};

final _versionPatterns = [
  for (final version in _versionKeywords.values.toSet())
    MapEntry(
      _keywords([
        for (final MapEntry(:key, :value) in _versionKeywords.entries)
          if (value == version) key,
      ]),
      version,
    ),
];
