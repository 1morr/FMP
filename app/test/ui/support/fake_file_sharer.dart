import 'dart:io';

import 'package:fmp/platform/share/share.dart';

/// 假的檔案分享：記下分享當下檔案的內容，回傳 [finished]（`false` 是平台不回報結果）；
/// [error] 非空時拋出它（分享視窗開不起來）。
final class FakeFileSharer implements FileSharer {
  FakeFileSharer({this.finished = true});

  bool finished;
  Object? error;
  final shared = <({String path, List<int> bytes, String mimeType})>[];

  @override
  Future<bool> shareFiles(
    List<String> paths, {
    required String mimeType,
  }) async {
    for (final path in paths) {
      shared.add((
        path: path,
        bytes: File(path).readAsBytesSync(),
        mimeType: mimeType,
      ));
    }
    if (error case final error?) throw error;
    return finished;
  }
}
