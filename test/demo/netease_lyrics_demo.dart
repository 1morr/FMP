// ignore_for_file: avoid_print
//
// 网易云音乐歌词 API Demo 测试脚本
//
// 运行方式:
//   dart run test/demos/netease_lyrics_demo.dart
//
// 测试内容:
//   1. 搜索歌曲
//   2. 获取歌词（原文 + 翻译）
//   3. 日文/英文歌曲测试

import 'dart:convert';

import 'package:dio/dio.dart';

// ── 内联的精简版模型 ──

class NeteaseSong {
  final int id;
  final String name;
  final List<String> artists;
  final String albumName;
  final int durationMs;

  NeteaseSong({
    required this.id,
    required this.name,
    required this.artists,
    required this.albumName,
    required this.durationMs,
  });

  factory NeteaseSong.fromJson(Map<String, dynamic> json) {
    final artistList = (json['artists'] as List<dynamic>?)
            ?.map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList() ??
        [];
    return NeteaseSong(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      artists: artistList,
      albumName:
          (json['album'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      durationMs: (json['duration'] as num?)?.toInt() ?? 0,
    );
  }

  String get artistsJoined => artists.join(', ');
  int get durationSeconds => (durationMs / 1000).round();
}

class NeteaseLyrics {
  final int songId;
  final String? lrc;
  final String? tlyric;
  final String? romalrc;

  NeteaseLyrics({
    required this.songId,
    this.lrc,
    this.tlyric,
    this.romalrc,
  });

  factory NeteaseLyrics.fromJson(int songId, Map<String, dynamic> json) {
    return NeteaseLyrics(
      songId: songId,
      lrc: (json['lrc'] as Map<String, dynamic>?)?['lyric'] as String?,
      tlyric: (json['tlyric'] as Map<String, dynamic>?)?['lyric'] as String?,
      romalrc: (json['romalrc'] as Map<String, dynamic>?)?['lyric'] as String?,
    );
  }

  bool get hasLrc => lrc != null && lrc!.trim().isNotEmpty;
  bool get hasTranslation => tlyric != null && tlyric!.trim().isNotEmpty;
  bool get hasRomaji => romalrc != null && romalrc!.trim().isNotEmpty;
}

// ── 工具函数 ──

/// 确保响应数据是 Map（处理 Dio 可能返回 String 的情况）
Map<String, dynamic> ensureMap(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  if (data is String) return jsonDecode(data) as Map<String, dynamic>;
  throw FormatException('Unexpected response type: ${data.runtimeType}');
}

// ── Demo 主函数 ──

Future<void> main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://music.163.com',
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': 'https://music.163.com/',
    },
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  print('=' * 60);
  print('网易云音乐歌词 API Demo');
  print('=' * 60);

  // ── Test 1: 搜索歌曲 ──
  await _testSearch(dio, '周杰伦 晴天', testLyrics: true);

  // ── Test 2: 日文歌曲 ──
  await _testSearch(dio, 'YOASOBI 夜に駆ける');

  // ── Test 3: 英文歌曲 ──
  await _testSearch(dio, 'Adele Someone Like You');

  print('\n${'=' * 60}');
  print('Demo 完成');
  print('=' * 60);

  dio.close();
}

Future<void> _testSearch(
  Dio dio,
  String keywords, {
  bool testLyrics = true,
}) async {
  print('\n── 搜索: "$keywords" ──');

  try {
    // 搜索歌曲
    final searchResp = await dio.post(
      '/api/search/get',
      data: 's=${Uri.encodeComponent(keywords)}&type=1&limit=5&offset=0',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );

    final searchData = ensureMap(searchResp.data);
    final searchCode = searchData['code'] as int?;

    if (searchCode != 200) {
      print('搜索失败: code=$searchCode');
      return;
    }

    final result = searchData['result'] as Map<String, dynamic>?;
    final songs = (result?['songs'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>()
            .map(NeteaseSong.fromJson)
            .toList() ??
        [];

    print('找到 ${songs.length} 首歌曲:');
    for (final song in songs.take(5)) {
      print(
          '  [${song.id}] ${song.name} - ${song.artistsJoined} '
          '(${song.albumName}, ${song.durationSeconds}s)');
    }

    // 获取歌词
    if (songs.isNotEmpty && testLyrics) {
      final song = songs.first;
      print('\n  获取歌词: ${song.name} (ID: ${song.id})');

      final lyricResp = await dio.get(
        '/api/song/lyric',
        queryParameters: {
          'id': song.id,
          'lv': 1,
          'tv': 1,
          'rv': 1,
        },
        options: Options(responseType: ResponseType.plain),
      );

      final lyricData = ensureMap(lyricResp.data);
      if (lyricData['code'] != 200) {
        print('  获取歌词失败: code=${lyricData['code']}');
        return;
      }

      final lyrics = NeteaseLyrics.fromJson(song.id, lyricData);
      print('  原文歌词: ${lyrics.hasLrc ? "✓" : "✗"}');
      print('  翻译歌词: ${lyrics.hasTranslation ? "✓" : "✗"}');
      print('  罗马音: ${lyrics.hasRomaji ? "✓" : "✗"}');

      if (lyrics.hasLrc) {
        print('\n  ── 歌词预览（前 15 行）──');
        final lines = lyrics.lrc!.split('\n');
        for (var i = 0; i < lines.length && i < 15; i++) {
          print('    ${lines[i]}');
        }
        if (lines.length > 15) {
          print('    ... (共 ${lines.length} 行)');
        }
      }

      if (lyrics.hasTranslation) {
        print('\n  ── 翻译歌词预览（前 8 行）──');
        final lines = lyrics.tlyric!.split('\n');
        for (var i = 0; i < lines.length && i < 8; i++) {
          print('    ${lines[i]}');
        }
      }

      if (lyrics.hasRomaji) {
        print('\n  ── 罗马音预览（前 5 行）──');
        final lines = lyrics.romalrc!.split('\n');
        for (var i = 0; i < lines.length && i < 5; i++) {
          print('    ${lines[i]}');
        }
      }
    }
  } catch (e) {
    print('错误: $e');
  }
}
