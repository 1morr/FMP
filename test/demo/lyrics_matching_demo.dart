// ignore_for_file: avoid_print
/// 歌词匹配可行性 Demo
///
/// 测试 TitleParser + lrclib API 的匹配效果。
/// 运行: dart run test/demo/lyrics_matching_demo.dart

import 'package:dio/dio.dart';

// ============================================================
// 内联精简版（避免依赖 Flutter，demo 可直接 dart run）
// 正式代码在 lib/services/lyrics/ 下
// ============================================================

class ParsedTitle {
  final String trackName;
  final String? artistName;
  final String cleanedTitle;

  const ParsedTitle({
    required this.trackName,
    this.artistName,
    required this.cleanedTitle,
  });

  @override
  String toString() =>
      'track: "$trackName", artist: ${artistName != null ? '"$artistName"' : 'null'}';
}

class RegexTitleParser {
  static const _tagWords =
      r'翻唱|cover|MV|PV|歌ってみた|弾いてみた|叩いてみた|演奏してみた|'
      r'Official|官方|自制|手书|MAD|AMV|MMD|VOCALOID|ボカロ|初音ミク|'
      r'オリジナル曲?|原创|原創|完整版|高音质|Hi-?Res|FLAC|4K|1080P|'
      r'中文字幕|歌词|Lyrics?|字幕|CC|合集|精选|剪辑|Clip|Live|现场|'
      r'Music\s*Video|Lyric\s*Video|Audio|Topic|Visualizer|'
      r'feat\.?[^】」』》\]]*|ft\.?[^】」』》\]]*';

  static final _bracketTag = RegExp('【($_tagWords)】', caseSensitive: false);
  static final _jpQuoteTag = RegExp('「($_tagWords)」', caseSensitive: false);
  static final _parenTag = RegExp(
    r'\s*[(\（](Official\s*(Music\s*)?Video|Music\s*Video|MV|PV|'
    r'Lyric\s*Video|Audio|Official\s*Audio|Official\s*MV|Official\s*Lyric|'
    r'Visualizer|Topic|Live|现场|完整版|高音质|Hi-?Res|FLAC|4K|1080P|'
    r'中文字幕|歌词版|cover|翻唱|歌ってみた|弾いてみた)[)\）]',
    caseSensitive: false,
  );
  static final _animeTag = RegExp(
    r'\s*[(\（][^)\）]*(OP|ED|OST|OVA|主題歌|片頭曲|片尾曲|插曲|'
    r'エンディング|オープニング|Theme\s*Song)[^)\）]*[)\）]',
    caseSensitive: false,
  );
  static final _trailingSuffix = RegExp(
    r'\s*[-–—|]\s*(Official\s*(Music\s*)?Video|Music\s*Video|MV|'
    r'Lyric\s*Video|Audio|Visualizer|Topic)\s*$',
    caseSensitive: false,
  );
  static final _standaloneSuffix = RegExp(
    r'\s+(?:Official\s+(?:Music\s+)?Video|Official\s+MV|'
    r'Official\s+Audio|Official\s+Lyric)\s*$',
    caseSensitive: false,
  );
  static final _jpSuffix = RegExp(
    r'[【\[「（(]オリジナル曲?PV付き?[】\]」）)]',
    caseSensitive: false,
  );
  static final _dashPat = RegExp(r'^(.+?)\s*[-–—]\s*(.+)$');
  static final _quotedPat = RegExp(r'^(.+?)\s*[「『《【](.+?)[」』》】]');
  static final _slashPat = RegExp(r'^(.+?)\s*/\s*(.+)$');
  static final _multiSp = RegExp(r'\s{2,}');
  static final _artistNoise = RegExp(
    r'\s*\b(MV|Official|Channel|チャンネル|VEVO)\b\s*',
    caseSensitive: false,
  );

  ParsedTitle parse(String title, {String? uploader}) {
    var cleaned = _clean(title);
    String? artist, track;

    // 模式 B: Artist「Title」/ Artist【Title】
    var m = _quotedPat.firstMatch(cleaned);
    if (m != null) {
      artist = _post(m.group(1)!);
      track = _post(m.group(2)!);
    }

    // 模式 C: Title / Artist
    if (track == null) {
      m = _slashPat.firstMatch(cleaned);
      if (m != null) {
        track = _post(m.group(1)!.trim());
        artist = _post(m.group(2)!.trim());
      }
    }

    // 模式 A: Artist - Title
    if (track == null) {
      m = _dashPat.firstMatch(cleaned);
      if (m != null) {
        final l = m.group(1)!.trim(), r = m.group(2)!.trim();
        if (l.contains('「') || l.contains('『') || l.contains('《')) {
          track = _post(l);
          artist = _post(r);
        } else {
          artist = _post(l);
          track = _post(r);
        }
      }
    }

    track ??= _post(cleaned);
    if (artist != null) artist = _cleanArtist(artist);
    artist ??= uploader;
    if (artist != null && artist == track) {
      artist = uploader != artist ? uploader : null;
    }

    return ParsedTitle(trackName: track, artistName: artist, cleanedTitle: cleaned.trim());
  }

  String _clean(String t) {
    var r = t;
    r = r.replaceAll(_bracketTag, ' ');
    r = r.replaceAll(_jpQuoteTag, ' ');
    r = r.replaceAll(_jpSuffix, ' ');
    r = r.replaceAll(_parenTag, ' ');
    r = r.replaceAll(_animeTag, ' ');
    r = r.replaceAll(_trailingSuffix, '');
    r = r.replaceAll(_standaloneSuffix, '');
    r = r.replaceAll(RegExp(r'#\S+'), ' ');
    r = r.replaceAll(_multiSp, ' ').trim();
    return r;
  }

  String _post(String text) {
    var r = text.trim();
    final wm = RegExp(r'^[【「『《\[](.*?)[】」』》\]]$').firstMatch(r);
    if (wm != null) r = wm.group(1)!;
    r = r.replaceAll(
      RegExp(
        r'\s*[(\（](cover|翻唱|feat\.?[^)\）]*|ft\.?[^)\）]*|'
        r'prod\.?[^)\）]*|remix|ver\.?|version|inst\.?|instrumental|'
        r'short|full|TV\s*size|anime\s*ver)[)\）]',
        caseSensitive: false,
      ),
      '',
    );
    r = r.replaceAll(
      RegExp(r'\s*\[(?:original\s*)?ver\.?[^\]]*\]', caseSensitive: false),
      '',
    );
    r = r.replaceAll(_multiSp, ' ').trim();
    return r;
  }

  String _cleanArtist(String a) {
    var r = a.replaceAll(_artistNoise, ' ');
    return r.replaceAll(_multiSp, ' ').trim();
  }
}

// --- LrclibResult ---

class LrclibResult {
  final int id;
  final String trackName;
  final String artistName;
  final String albumName;
  final int duration;
  final bool instrumental;
  final String? syncedLyrics;
  final String? plainLyrics;

  LrclibResult.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        trackName = j['trackName'] as String? ?? '',
        artistName = j['artistName'] as String? ?? '',
        albumName = j['albumName'] as String? ?? '',
        duration = (j['duration'] as num?)?.toInt() ?? 0,
        instrumental = j['instrumental'] as bool? ?? false,
        syncedLyrics = j['syncedLyrics'] as String?,
        plainLyrics = j['plainLyrics'] as String?;

  bool get hasSynced => syncedLyrics != null && syncedLyrics!.isNotEmpty;
}

// ============================================================
// 测试样本
// ============================================================

class TestSample {
  final String title;
  final String? uploader;
  final int? durationSec;
  final String? expectedTrack;
  final String? expectedArtist;

  const TestSample(this.title, {
    this.uploader, this.durationSec, this.expectedTrack, this.expectedArtist,
  });
}

const _samples = [
  // === Bilibili ===
  TestSample('周杰伦 - 晴天', uploader: '音乐分享', durationSec: 269,
    expectedTrack: '晴天', expectedArtist: '周杰伦'),
  TestSample('【翻唱】告白气球 - 周杰伦', uploader: 'xxx翻唱', durationSec: 215,
    expectedTrack: '告白气球', expectedArtist: '周杰伦'),
  TestSample('Aimer - 残響散歌 (鬼滅の刃 遊郭編 OP)', uploader: 'Aimer Official', durationSec: 222,
    expectedTrack: '残響散歌', expectedArtist: 'Aimer'),
  TestSample('「歌ってみた」夜に駆ける / YOASOBI', uploader: 'cover歌手', durationSec: 258,
    expectedTrack: '夜に駆ける', expectedArtist: 'YOASOBI'),
  TestSample('陈奕迅 Eason Chan -【十年】(Official Music Video)', uploader: '环球音乐', durationSec: 205,
    expectedTrack: '十年', expectedArtist: '陈奕迅 Eason Chan'),

  // === YouTube ===
  TestSample('YOASOBI「アイドル」Official Music Video', uploader: 'Ayase / YOASOBI', durationSec: 223,
    expectedTrack: 'アイドル', expectedArtist: 'YOASOBI'),
  TestSample('Taylor Swift - Anti-Hero (Official Music Video)', uploader: 'Taylor Swift', durationSec: 200,
    expectedTrack: 'Anti-Hero', expectedArtist: 'Taylor Swift'),
  TestSample('Adele - Rolling in the Deep (Official Music Video)', uploader: 'Adele', durationSec: 228,
    expectedTrack: 'Rolling in the Deep', expectedArtist: 'Adele'),
  TestSample('米津玄師 MV「Lemon」', uploader: '米津玄師', durationSec: 254,
    expectedTrack: 'Lemon', expectedArtist: '米津玄師'),
  TestSample('周杰伦 Jay Chou【晴天 Sunny Day】Official MV', uploader: '周杰伦', durationSec: 269,
    expectedTrack: '晴天 Sunny Day', expectedArtist: '周杰伦 Jay Chou'),

  // === 边界情况 ===
  TestSample('ヨルシカ - だから僕は音楽を辞めた', uploader: 'ヨルシカ', durationSec: 289,
    expectedTrack: 'だから僕は音楽を辞めた', expectedArtist: 'ヨルシカ'),
  TestSample('Kenshi Yonezu - KICK BACK', uploader: '米津玄師', durationSec: 196,
    expectedTrack: 'KICK BACK', expectedArtist: 'Kenshi Yonezu'),
  TestSample('【初音ミク】千本桜【オリジナル曲PV付き】', uploader: '黒うさP', durationSec: 252,
    expectedTrack: '千本桜', expectedArtist: null),
  TestSample('Billie Eilish - lovely (with Khalid) - Official Music Video', uploader: 'Billie Eilish', durationSec: 200,
    expectedTrack: 'lovely', expectedArtist: 'Billie Eilish'),
  TestSample('薛之谦《演员》', uploader: '薛之谦', durationSec: 270,
    expectedTrack: '演员', expectedArtist: '薛之谦'),
  TestSample('LiSA - 紅蓮華 / THE FIRST TAKE', uploader: 'THE FIRST TAKE', durationSec: 275,
    expectedTrack: '紅蓮華', expectedArtist: 'LiSA'),
  TestSample('Ado - 唱 (Official Music Video)', uploader: 'Ado', durationSec: 195,
    expectedTrack: '唱', expectedArtist: 'Ado'),
  TestSample('林俊杰 JJ Lin - 江南', uploader: 'JJ Lin', durationSec: 280,
    expectedTrack: '江南', expectedArtist: '林俊杰 JJ Lin'),
  TestSample('RADWIMPS - スパークル [original ver.] Your name.', uploader: 'RADWIMPS', durationSec: 527,
    expectedTrack: 'スパークル', expectedArtist: 'RADWIMPS'),
  TestSample('邓紫棋 - 光年之外 (Official Music Video)', uploader: 'GEM邓紫棋', durationSec: 235,
    expectedTrack: '光年之外', expectedArtist: '邓紫棋'),
];

// ============================================================
// Main
// ============================================================

void main() async {
  final parser = RegexTitleParser();
  final dio = Dio(BaseOptions(
    baseUrl: 'https://lrclib.net/api',
    headers: {'User-Agent': 'FMP/1.0.0 (lyrics-demo)'},
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  print('=' * 70);
  print('歌词匹配可行性 Demo');
  print('=' * 70);

  final total = _samples.length;
  int parseOk = 0, searchHit = 0, durMatch = 0, syncHit = 0;

  for (var i = 0; i < total; i++) {
    final s = _samples[i];
    print('\n--- [${i + 1}/$total] ---');
    print('原标题: ${s.title}');
    print('UP主:   ${s.uploader ?? "(无)"}');
    print('时长:   ${s.durationSec ?? "(无)"}s');

    // Step 1: 解析
    final p = parser.parse(s.title, uploader: s.uploader);
    print('\n  解析结果: $p');

    if (s.expectedTrack != null) {
      final ok = p.trackName.contains(s.expectedTrack!) ||
          s.expectedTrack!.contains(p.trackName);
      print('  歌曲名: ${ok ? "✓" : "✗"} (期望: "${s.expectedTrack}", 得到: "${p.trackName}")');
    }
    if (s.expectedArtist != null) {
      final ok = p.artistName != null &&
          (p.artistName!.contains(s.expectedArtist!) ||
              s.expectedArtist!.contains(p.artistName!));
      print('  歌手名: ${ok ? "✓" : "✗"} (期望: "${s.expectedArtist}", 得到: "${p.artistName}")');
      if (ok) parseOk++;
    }

    // Step 2: 搜索 lrclib
    print('\n  搜索:');
    List<LrclibResult> results = [];

    // 策略 1: track_name + artist_name
    if (p.artistName != null) {
      print('    [1] track="${p.trackName}" + artist="${p.artistName}"');
      try {
        results = await _search(dio, trackName: p.trackName, artistName: p.artistName);
        print('    → ${results.length} 条');
      } catch (e) {
        print('    → 错误: $e');
      }
    }

    // 策略 2: 仅 track_name
    if (results.isEmpty) {
      print('    [2] track="${p.trackName}"');
      try {
        results = await _search(dio, trackName: p.trackName);
        print('    → ${results.length} 条');
      } catch (e) {
        print('    → 错误: $e');
      }
    }

    // 策略 3: q 全文
    if (results.isEmpty) {
      final q = '${p.trackName} ${p.artistName ?? ""}'.trim();
      print('    [3] q="$q"');
      try {
        results = await _search(dio, q: q);
        print('    → ${results.length} 条');
      } catch (e) {
        print('    → 错误: $e');
      }
    }

    if (results.isNotEmpty) {
      searchHit++;

      if (s.durationSec != null) {
        final filtered = results
            .where((r) => (r.duration - s.durationSec!).abs() <= 10)
            .toList();
        print('\n  Duration ±10s: ${filtered.length}/${results.length}');

        if (filtered.isNotEmpty) {
          durMatch++;
          final b = filtered.first;
          print('  最佳: "${b.trackName}" by "${b.artistName}" (${b.duration}s, id=${b.id})');
          print('  专辑: "${b.albumName}"');
          print('  同步歌词: ${b.hasSynced ? "✓" : "✗"}');
          if (b.hasSynced) {
            syncHit++;
            for (final line in b.syncedLyrics!.split('\n').take(3)) {
              print('    $line');
            }
          }
        } else {
          print('  无匹配，前3:');
          for (final r in results.take(3)) {
            print('    - "${r.trackName}" by "${r.artistName}" (${r.duration}s)');
          }
        }
      }
    } else {
      print('\n  ❌ 未找到');
    }

    await Future.delayed(const Duration(milliseconds: 300));
  }

  print('\n${"=" * 70}');
  print('统计');
  print('=' * 70);
  print('总样本:     $total');
  print('解析成功:   $parseOk/$total (${(parseOk / total * 100).toStringAsFixed(0)}%)');
  print('搜索命中:   $searchHit/$total (${(searchHit / total * 100).toStringAsFixed(0)}%)');
  print('Duration:   $durMatch/$total (${(durMatch / total * 100).toStringAsFixed(0)}%)');
  print('同步歌词:   $syncHit/$total (${(syncHit / total * 100).toStringAsFixed(0)}%)');

  dio.close();
}

Future<List<LrclibResult>> _search(
  Dio dio, {String? q, String? trackName, String? artistName,
}) async {
  final params = <String, String>{};
  if (q != null) params['q'] = q;
  if (trackName != null) params['track_name'] = trackName;
  if (artistName != null) params['artist_name'] = artistName;
  final resp = await dio.get('/search', queryParameters: params);
  if (resp.data is! List) return [];
  return (resp.data as List).cast<Map<String, dynamic>>().map(LrclibResult.fromJson).toList();
}
