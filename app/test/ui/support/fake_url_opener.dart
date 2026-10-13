import 'package:fmp/platform/url_opener/url_opener.dart';

/// 假的網址開啟器：記下開過的網址，回傳 [result]（`false` 是開不了）。
final class FakeUrlOpener implements UrlOpener {
  FakeUrlOpener({this.result = true});

  bool result;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}
