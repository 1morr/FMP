import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `release.yml` 用 `sed` 把 tag 的版本寫進 `pubspec.yaml`，但**不回寫 repo**，
/// 所以 committed 的版本會靜靜落後最新的 tag。這不是潔癖問題：開發建置會自報
/// 舊版本，然後對使用者跳出「有新版可用」—— 對著自己喊狼來了。
///
/// 修過一次（`8d04147e`），兩個月後原樣復發，因為沒有任何東西守著它。
///
/// 允許 pubspec **超前** tag：發版前先 bump 是正常的。擋的是落後。
void main() {
  test('pubspec version is not behind the newest reachable tag', () {
    final tag = _newestReachableTag();
    if (tag == null) {
      // 淺 checkout 或沒有 tag 的 fork。CI 的 validate job 用 fetch-depth: 0，
      // 所以那裡一定拿得到。
      markTestSkipped('no vX.Y.Z tag reachable from HEAD');
      return;
    }

    final pubspec = _pubspecVersion();
    expect(
      _compare(pubspec, tag) >= 0,
      isTrue,
      reason:
          'pubspec.yaml says $pubspec but the newest tag is v$tag. '
          'A build from this tree would tell users it is $pubspec and then '
          'offer them v$tag as an update.',
    );
  });

  test('the build number matches the formula release.yml uses', () {
    final line = _pubspecVersionLine();
    final parts = line.split('+');
    expect(parts, hasLength(2), reason: 'version needs a +buildNumber');

    final v = parts[0].split('.').map(int.parse).toList();
    expect(
      int.parse(parts[1]),
      v[0] * 1000000 + v[1] * 1000 + v[2],
      reason:
          'Android only accepts an increasing versionCode, and release.yml '
          'derives it from the tag with this formula.',
    );
  });
}

String _pubspecVersionLine() {
  final line = File(
    'pubspec.yaml',
  ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
  return line.substring('version:'.length).trim();
}

String _pubspecVersion() => _pubspecVersionLine().split('+').first;

String? _newestReachableTag() {
  final ProcessResult result;
  try {
    result = Process.runSync('git', [
      'describe',
      '--tags',
      '--abbrev=0',
      '--match',
      'v[0-9]*.[0-9]*.[0-9]*',
      'HEAD',
    ]);
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) return null;
  final tag = (result.stdout as String).trim();
  return tag.isEmpty ? null : tag.substring(1);
}

/// `1.10.0` 排在 `1.9.1` 之後 —— 字串比較會說反。
int _compare(String a, String b) {
  final x = a.split('.').map(int.parse).toList();
  final y = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    final c = x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return 0;
}
