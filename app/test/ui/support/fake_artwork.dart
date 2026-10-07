import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:fmp/plugins/source_dto.dart';

/// 1×1 的純白與純黑 PNG：播放頁的背景與對比度測試要「最淺」「最深」的封面。
final _white = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC',
);
final _black = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC',
);

/// 測試封面的亮度：網址的檔名決定回哪一張。
enum TestArtwork {
  lightest('https://img.example/white.png'),
  darkest('https://img.example/black.png');

  const TestArtwork(this.url);

  final String url;

  /// 放進 `TrackSummary.artwork` 的封面。
  List<Artwork> get artwork => [Artwork(url: Uri.parse(url))];
}

/// 只實作 `CachedNetworkImage` 會叫的 `getFileStream`：白色網址回白圖，其他回黑圖。
final class FakeArtworkManager implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    final file = MemoryFileSystem().file('/cover.png')
      ..writeAsBytesSync(url.endsWith('white.png') ? _white : _black);
    return Stream.value(
      FileInfo(file, FileSource.Cache, DateTime.utc(2100), url),
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
