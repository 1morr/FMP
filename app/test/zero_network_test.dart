import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'flutter_test_config.dart';

/// 零聯網的兩道防線（ADR 0015 §決定 3）：`dart_test.yaml` 跳過 `live`，
/// `flutter_test_config.dart` 擋下真實 [HttpClient]。
void main() {
  final blockedByGuard = throwsA(
    isA<StateError>().having(
      (error) => error.message,
      'message',
      startsWith(NoNetworkHttpOverrides.message),
    ),
  );

  test('creating a real HttpClient fails', () {
    expect(HttpClient.new, blockedByGuard);
  });

  testWidgets('the guard survives the widget test binding', (tester) async {
    expect(HttpClient.new, blockedByGuard);
  });

  test('a test allows the network only inside its own zone', () {
    final client = HttpOverrides.runWithHttpOverrides(
      HttpClient.new,
      _AllowNetwork(),
    );
    addTearDown(() => client.close(force: true));

    expect(client, isA<HttpClient>());
    expect(HttpClient.new, blockedByGuard);
  });

  group('dart_test.yaml', () {
    test('skips the live tag by default', () {
      expect(liveTagSkip(File('dart_test.yaml').readAsStringSync()), isTrue);
    });

    test('a removed or disabled skip is detected', () {
      expect(liveTagSkip('tags:\n  live:\n'), isFalse);
      expect(liveTagSkip('tags:\n  live:\n    skip: false\n'), isFalse);
      expect(liveTagSkip('tags:\n  other:\n    skip: "x"\n'), isFalse);
    });

    test('layout and wording do not matter', () {
      expect(liveTagSkip('tags: {live: {skip: "hits real APIs"}}'), isTrue);
      expect(liveTagSkip('tags:\n  live:\n    skip: true\n'), isTrue);
    });
  });

  // 裸 `flutter test` 跳過這條（第一道）；以 `--run-skipped --tags live` 解除
  // 後，它證明第二道仍然擋下未放行的連線。
  test(
    'an unskipped live test is still blocked by the guard',
    () => expect(HttpClient.new, blockedByGuard),
    tags: 'live',
  );
}

/// 不覆寫 createHttpClient：沿用 dart:io 建立真實 client。
final class _AllowNetwork extends HttpOverrides {}

/// `dart_test.yaml` 是否讓 `live` tag 預設跳過（`skip` 為 true 或理由字串）。
bool liveTagSkip(String dartTestYaml) {
  Object? field(Object? map, String key) => map is YamlMap ? map[key] : null;
  final skip = field(
    field(field(loadYaml(dartTestYaml), 'tags'), 'live'),
    'skip',
  );
  return skip == true || (skip is String && skip.isNotEmpty);
}
