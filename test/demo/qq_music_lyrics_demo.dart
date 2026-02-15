// ignore_for_file: avoid_print
//
// QQ 音乐歌词 API Demo 测试脚本
//
// 运行方式:
//   dart run test/demo/qq_music_lyrics_demo.dart
//
// 测试内容:
//   1. 搜索歌曲（获取 songmid）
//   2. 获取歌词（原文 + 翻译，base64 解码）
//   3. 中文/日文/英文歌曲测试
//
// API 说明:
//   搜索: POST https://u.y.qq.com/cgi-bin/musicu.fcg
//         body: JSON (music.search.SearchCgiService / DoSearchForQQMusicDesktop)
//   歌词: POST https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_yqq.fcg
//         body: format=json&nobase64=1&g_tk=5381&songmid=xxx
//         headers: Referer: y.qq.com
//         返回 lyric / trans 字段（base64 编码或明文，取决于 nobase64 参数）

import 'dart:convert';

import 'package:dio/dio.dart';

// ── 内联模型 ──

class QQMusicSong {
  final String songmid;
  final String songname;
  final List<String> singers;
  final String albumName;
  final String albumMid;
  final int interval; // seconds

  QQMusicSong({
    required this.songmid,
    required this.songname,
    required this.singers,
    required this.albumName,
    required this.albumMid,
    required this.interval,
  });

  factory QQMusicSong.fromJson(Map<String, dynamic> json) {
    final singerList = (json['singer'] as List<dynamic>?)
            ?.map((s) => (s as Map<String, dynamic>)['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList() ??
        [];
    return QQMusicSong(
      songmid: json['mid'] as String? ?? json['songmid'] as String? ?? '',
      songname: json['name'] as String? ?? json['songname'] as String? ?? '',
      singers: singerList,
      albumName:
          (json['album'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      albumMid:
          (json['album'] as Map<String, dynamic>?)?['mid'] as String? ?? '',
      interval: (json['interval'] as num?)?.toInt() ?? 0,
    );
  }

  String get singersJoined => singers.join(', ');
}

class QQMusicLyrics {
  final String songmid;
  final String? lyric;
  final String? trans;

  QQMusicLyrics({
    required this.songmid,
    this.lyric,
    this.trans,
  });

  bool get hasLyric => lyric != null && lyric!.trim().isNotEmpty;
  bool get hasTranslation => trans != null && trans!.trim().isNotEmpty;
}

// ── 工具函数 ──

Map<String, dynamic> ensureMap(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  if (data is String) return jsonDecode(data) as Map<String, dynamic>;
  throw FormatException('Unexpected response type: ${data.runtimeType}');
}

/// 尝试 base64 解码，失败则返回原文
String? tryDecodeBase64(dynamic value) {
  if (value == null) return null;
  final str = value.toString().trim();
  if (str.isEmpty) return null;
  try {
    return utf8.decode(base64Decode(str));
  } catch (_) {
    return str; // 已经是明文
  }
}

/// 解码 HTML 实体（QQ 音乐歌词接口返回的 HTML 编码）
/// 例如: &#58; → :  &#32; → 空格  &#10; → \n  &#13; → \r  &#38; → &  &apos; → '
String decodeHtmlEntities(String input) {
  // 先处理命名实体
  var result = input
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#38;apos&#59;', "'"); // 双重编码的 &apos;

  // 处理数字实体 &#xx;
  result = result.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (match) => String.fromCharCode(int.parse(match.group(1)!)),
  );

  // 处理十六进制实体 &#xHH;
  result = result.replaceAllMapped(
    RegExp(r'&#x([0-9a-fA-F]+);'),
    (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
  );

  return result;
}

/// 对可能含 HTML 实体的字段做解码
String? _decodeField(String? value) {
  if (value == null) return null;
  return decodeHtmlEntities(value);
}

// ── API 调用 ──

/// 搜索歌曲，返回歌曲列表
Future<List<QQMusicSong>> searchSongs(Dio dio, String keyword,
    {int limit = 10}) async {
  final body = jsonEncode({
    'comm': {'ct': '19', 'cv': '1859', 'uin': '0'},
    'req': {
      'method': 'DoSearchForQQMusicDesktop',
      'module': 'music.search.SearchCgiService',
      'param': {
        'grp': 1,
        'num_per_page': limit,
        'page_num': 1,
        'query': keyword,
        'search_type': 0, // 0=歌曲
      },
    },
  });

  final resp = await dio.post(
    'https://u.y.qq.com/cgi-bin/musicu.fcg',
    data: body,
    options: Options(
      contentType: 'application/json;charset=utf-8',
      responseType: ResponseType.plain,
    ),
  );

  final data = ensureMap(resp.data);
  final songBody =
      data['req']?['data']?['body']?['song'] as Map<String, dynamic>?;
  final list = (songBody?['list'] as List<dynamic>?) ?? [];

  return list
      .cast<Map<String, dynamic>>()
      .map(QQMusicSong.fromJson)
      .toList();
}

/// 获取歌词（方式一：nobase64=1，直接返回明文）
Future<QQMusicLyrics> getLyrics(Dio dio, String songmid) async {
  // 方式一：使用 fcg_query_lyric_yqq.fcg + nobase64=1
  final resp = await dio.post(
    'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_yqq.fcg',
    data: 'format=json&nobase64=1&g_tk=5381&songmid=$songmid',
    options: Options(
      contentType: Headers.formUrlEncodedContentType,
      responseType: ResponseType.plain,
      headers: {
        'Referer': 'https://y.qq.com',
      },
    ),
  );

  final data = ensureMap(resp.data);
  final retcode = data['retcode'] as int?;

  if (retcode != 0) {
    print('  歌词接口返回 retcode=$retcode，尝试 base64 模式...');
    return getLyricsBase64(dio, songmid);
  }

  return QQMusicLyrics(
    songmid: songmid,
    lyric: data['lyric'] != null
        ? decodeHtmlEntities(data['lyric'] as String)
        : null,
    trans: data['trans'] != null
        ? decodeHtmlEntities(data['trans'] as String)
        : null,
  );
}

/// 获取歌词（方式二：不带 nobase64，返回 base64 编码）
Future<QQMusicLyrics> getLyricsBase64(Dio dio, String songmid) async {
  final resp = await dio.post(
    'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_yqq.fcg',
    data: 'format=json&g_tk=5381&songmid=$songmid',
    options: Options(
      contentType: Headers.formUrlEncodedContentType,
      responseType: ResponseType.plain,
      headers: {
        'Referer': 'https://y.qq.com',
      },
    ),
  );

  final data = ensureMap(resp.data);
  final retcode = data['retcode'] as int?;

  if (retcode != 0) {
    print('  歌词接口 (base64 模式) 也失败: retcode=$retcode');
    return QQMusicLyrics(songmid: songmid);
  }

  return QQMusicLyrics(
    songmid: songmid,
    lyric: _decodeField(tryDecodeBase64(data['lyric'])),
    trans: _decodeField(tryDecodeBase64(data['trans'])),
  );
}

/// 获取歌词（方式三：通过 musicu.fcg 统一接口）
Future<QQMusicLyrics> getLyricsViaMusicu(Dio dio, String songmid) async {
  final body = jsonEncode({
    'comm': {'ct': '19', 'cv': '1859', 'uin': '0'},
    'req': {
      'method': 'GetPlayLyricInfo',
      'module': 'music.musichallSong.PlayLyricInfo',
      'param': {
        'songMID': songmid,
        'songID': 0,
      },
    },
  });

  final resp = await dio.post(
    'https://u.y.qq.com/cgi-bin/musicu.fcg',
    data: body,
    options: Options(
      contentType: 'application/json;charset=utf-8',
      responseType: ResponseType.plain,
    ),
  );

  final data = ensureMap(resp.data);
  final lyricData = data['req']?['data'] as Map<String, dynamic>?;

  if (lyricData == null) {
    print('  musicu.fcg 歌词接口返回空数据');
    return QQMusicLyrics(songmid: songmid);
  }

  return QQMusicLyrics(
    songmid: songmid,
    lyric: _decodeField(tryDecodeBase64(lyricData['lyric'])),
    trans: _decodeField(tryDecodeBase64(lyricData['trans'])),
  );
}

// ── Demo 主函数 ──

Future<void> main() async {
  final dio = Dio(BaseOptions(
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) '
              'Gecko/20100101 Firefox/115.0',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.8,en-US;q=0.3,en;q=0.2',
    },
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  print('=' * 60);
  print('QQ 音乐歌词 API Demo');
  print('=' * 60);

  // ── Test 1: 中文歌曲 ──
  await _testFull(dio, '周杰伦 晴天');

  // ── Test 2: 日文歌曲 ──
  await _testFull(dio, 'YOASOBI 夜に駆ける');

  // ── Test 3: 英文歌曲 ──
  await _testFull(dio, 'Adele Someone Like You');

  // ── Test 4: 测试 musicu.fcg 统一接口 ──
  await _testMusicuLyric(dio, '周杰伦 七里香');

  print('\n${'=' * 60}');
  print('Demo 完成');
  print('=' * 60);

  dio.close();
}

Future<void> _testFull(Dio dio, String keyword) async {
  print('\n${'─' * 50}');
  print('搜索: "$keyword"');
  print('─' * 50);

  try {
    // 1. 搜索
    final songs = await searchSongs(dio, keyword, limit: 5);
    print('找到 ${songs.length} 首歌曲:');
    for (final song in songs) {
      print('  [${song.songmid}] ${song.songname} - ${song.singersJoined} '
          '(${song.albumName}, ${song.interval}s)');
    }

    if (songs.isEmpty) {
      print('  无搜索结果');
      return;
    }

    // 2. 获取歌词
    final song = songs.first;
    print('\n获取歌词: ${song.songname} (mid: ${song.songmid})');

    final lyrics = await getLyrics(dio, song.songmid);
    _printLyrics(lyrics);
  } catch (e) {
    print('错误: $e');
  }
}

Future<void> _testMusicuLyric(Dio dio, String keyword) async {
  print('\n${'─' * 50}');
  print('测试 musicu.fcg 统一歌词接口: "$keyword"');
  print('─' * 50);

  try {
    final songs = await searchSongs(dio, keyword, limit: 1);
    if (songs.isEmpty) {
      print('  无搜索结果');
      return;
    }

    final song = songs.first;
    print('歌曲: ${song.songname} - ${song.singersJoined} (mid: ${song.songmid})');

    final lyrics = await getLyricsViaMusicu(dio, song.songmid);
    _printLyrics(lyrics);
  } catch (e) {
    print('错误: $e');
  }
}

void _printLyrics(QQMusicLyrics lyrics) {
  print('  原文歌词: ${lyrics.hasLyric ? "✓" : "✗"}');
  print('  翻译歌词: ${lyrics.hasTranslation ? "✓" : "✗"}');

  if (lyrics.hasLyric) {
    print('\n  ── 歌词预览（前 15 行）──');
    final lines = lyrics.lyric!.split('\n');
    for (var i = 0; i < lines.length && i < 15; i++) {
      print('    ${lines[i]}');
    }
    if (lines.length > 15) {
      print('    ... (共 ${lines.length} 行)');
    }
  }

  if (lyrics.hasTranslation) {
    print('\n  ── 翻译歌词预览（前 8 行）──');
    final lines = lyrics.trans!.split('\n');
    for (var i = 0; i < lines.length && i < 8; i++) {
      print('    ${lines[i]}');
    }
  }
}
