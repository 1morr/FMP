import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/share/share_plus_file_sharer.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  late List<ShareParams> calls;
  SharePlusFileSharer sharerReporting(ShareResultStatus status) {
    calls = [];
    return SharePlusFileSharer((params) async {
      calls.add(params);
      return ShareResult('', status);
    });
  }

  test('hands the files and their MIME type to the share window', () async {
    final sharer = sharerReporting(ShareResultStatus.success);

    await sharer.shareFiles([
      '/a/one.zip',
      '/a/two.zip',
    ], mimeType: 'application/zip');

    final files = calls.single.files!;
    expect([for (final file in files) file.path], ['/a/one.zip', '/a/two.zip']);
    expect({for (final file in files) file.mimeType}, {'application/zip'});
    expect(calls.single.text, isNull);
  });

  test('is finished when the platform reports an outcome', () async {
    for (final status in [
      ShareResultStatus.success,
      ShareResultStatus.dismissed,
    ]) {
      expect(
        await sharerReporting(status)
            .shareFiles(['/a.zip'], mimeType: 'application/zip'),
        isTrue,
        reason: '$status',
      );
    }
  });

  test('is not finished when the platform reports nothing', () async {
    // Windows 的 DataTransferManager：視窗開了就回傳 unavailable，接收端之後才讀檔。
    expect(
      await sharerReporting(ShareResultStatus.unavailable)
          .shareFiles(['/a.zip'], mimeType: 'application/zip'),
      isFalse,
    );
  });

  test('a share that fails to open throws', () async {
    final sharer = SharePlusFileSharer((_) => throw StateError('no window'));

    await expectLater(
      sharer.shareFiles(['/a.zip'], mimeType: 'application/zip'),
      throwsStateError,
    );
  });
}
