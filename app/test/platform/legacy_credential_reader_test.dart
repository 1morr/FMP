import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader_android.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader_windows.dart';

// 舊憑證的唯讀讀取器（M5 design §4.3、§9）。Windows 的解密是注入的假函式（Linux 也能跑），
// 真的 DPAPI 往返在 integration_test/legacy_credentials_test.dart。值都是明顯的假值。

const _keys = [
  'account_bilibili_credentials',
  'account_youtube_credentials',
  'account_netease_credentials',
];

Log _log() => Log(redactor: Redactor(), minimumLevel: LogLevel.debug);

/// 假的「加密」：位元組反過來。檔案裡存的是反過來的 JSON，所以沒走解密就讀不出來。
Uint8List _fakeProtect(String json) =>
    Uint8List.fromList(utf8.encode(json).reversed.toList());

Uint8List _fakeUnprotect(Uint8List bytes) =>
    Uint8List.fromList(bytes.reversed.toList());

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('fmp-legacy-creds-');
    addTearDown(() => directory.deleteSync(recursive: true));
  });

  group('Windows reader', () {
    File datFile() => File('${directory.path}/flutter_secure_storage.dat');

    WindowsLegacyCredentialReader reader({
      DpapiUnprotect unprotect = _fakeUnprotect,
      Log? log,
    }) => WindowsLegacyCredentialReader(
      directory: directory,
      unprotect: unprotect,
      log: log,
    );

    void writeDat(String json) =>
        datFile().writeAsBytesSync(_fakeProtect(json));

    test('reads the old keys from the decrypted JSON map', () async {
      writeDat(
        jsonEncode({
          'account_bilibili_credentials': '{"sessdata":"FAKE_SESSDATA_123"}',
          'account_netease_credentials': 'FAKE_NETEASE_JSON',
          // 新版自己的鍵（有前綴）在同一個檔案裡，不相干。
          'fmp.credentials.bilibili': 'FAKE_NEW_VALUE',
        }),
      );
      final result = await reader().read(_keys);
      expect(result, {
        'account_bilibili_credentials': const LegacyCredentialFound(
          '{"sessdata":"FAKE_SESSDATA_123"}',
        ),
        'account_youtube_credentials': const LegacyCredentialMissing(),
        'account_netease_credentials': const LegacyCredentialFound(
          'FAKE_NETEASE_JSON',
        ),
      });
    });

    test('the decrypt function gets the file bytes untouched', () async {
      writeDat('{}');
      Uint8List? seen;
      await reader(
        unprotect: (bytes) {
          seen = bytes;
          return _fakeUnprotect(bytes);
        },
      ).read(_keys);
      expect(seen, _fakeProtect('{}'));
    });

    test('no file: every key is missing', () async {
      final result = await reader().read(_keys);
      expect(result.values, everyElement(const LegacyCredentialMissing()));
      expect(result.keys, _keys);
    });

    test('no directory either: every key is missing', () async {
      final result = await WindowsLegacyCredentialReader(
        directory: Directory('${directory.path}/nope'),
        unprotect: _fakeUnprotect,
      ).read(_keys);
      expect(result.values, everyElement(const LegacyCredentialMissing()));
    });

    test('a value that is not a string counts as missing', () async {
      writeDat(jsonEncode({'account_bilibili_credentials': 5}));
      final result = await reader().read(_keys);
      expect(result.values, everyElement(const LegacyCredentialMissing()));
    });

    test(
      'decryption fails, bad JSON, or not an object: all unreadable',
      () async {
        writeDat('{"account_bilibili_credentials":"FAKE"}');
        for (final unprotect in <DpapiUnprotect>[
          (_) => throw const FormatException('bad blob'),
          (_) => Uint8List.fromList(utf8.encode('{not json')),
          (_) => Uint8List.fromList(utf8.encode('[1,2]')),
          (_) => Uint8List.fromList(const [0xff, 0xfe]),
        ]) {
          final result = await reader(unprotect: unprotect).read(_keys);
          expect(result.keys, _keys);
          expect(
            result.values,
            everyElement(const LegacyCredentialUnreadable()),
          );
        }
      },
    );

    test('never writes: bytes and modification time stay the same', () async {
      for (final json in ['{"account_bilibili_credentials":"FAKE"}', 'junk']) {
        datFile().writeAsBytesSync(_fakeProtect(json));
        final before = datFile().readAsBytesSync();
        final modified = datFile().lastModifiedSync();
        await reader().read(_keys);
        await reader(unprotect: (_) => throw StateError('x')).read(_keys);
        expect(datFile().existsSync(), isTrue);
        expect(datFile().readAsBytesSync(), before);
        expect(datFile().lastModifiedSync(), modified);
      }
      expect(directory.listSync().length, 1);
    });

    test('the log has key names and result kinds, never values', () async {
      writeDat(
        jsonEncode({'account_bilibili_credentials': 'FAKE_SECRET_VALUE_123'}),
      );
      final log = _log();
      await reader(log: log).read(_keys);
      final text = log.history
          .map((r) => '${r.message} ${r.fields}')
          .join('\n');
      expect(text, contains('account_bilibili_credentials'));
      expect(text, contains('found'));
      expect(text, contains('missing'));
      expect(text, isNot(contains('FAKE_SECRET_VALUE_123')));
      expect(
        const LegacyCredentialFound('FAKE_SECRET_VALUE_123').toString(),
        isNot(contains('FAKE_SECRET_VALUE_123')),
      );
    });
  });

  group('Android reader', () {
    File prefs() => AndroidLegacyCredentialReader.prefsFileIn(directory);

    test(
      'the options are the legacy ones: no namespace, no reset, no migration',
      () {
        final map = AndroidLegacyCredentialReader.options.toMap();
        expect(map['resetOnError'], 'false');
        expect(map['migrateOnAlgorithmChange'], 'false');
        expect(map['storageNamespace'], '');
        expect(map['preferencesKeyPrefix'], '');
        // 其餘照預設：舊版沒傳任何選項。
        final defaults = const AndroidOptions().toMap();
        expect(
          {...map}
            ..remove('resetOnError')
            ..remove('migrateOnAlgorithmChange'),
          {...defaults}
            ..remove('resetOnError')
            ..remove('migrateOnAlgorithmChange'),
        );
      },
    );

    test('the prefs file lives in shared_prefs of the data directory', () {
      expect(
        prefs().path.replaceAll(r'\', '/'),
        '${directory.path.replaceAll(r'\', '/')}/shared_prefs/FlutterSecureStorage.xml',
      );
    });

    test('no old prefs file: all missing and no instance is created', () async {
      var created = 0;
      final reader = AndroidLegacyCredentialReader(
        prefsFile: prefs(),
        createReader: (_) {
          created++;
          return (_) async => 'x';
        },
      );
      final result = await reader.read(_keys);
      expect(result.values, everyElement(const LegacyCredentialMissing()));
      expect(created, 0);
      expect(prefs().existsSync(), isFalse);
    });

    test('reads key by key with the legacy options', () async {
      prefs()
        ..createSync(recursive: true)
        ..writeAsStringSync('<map/>');
      final seenOptions = <Map<String, String>>[];
      final asked = <String>[];
      final reader = AndroidLegacyCredentialReader(
        prefsFile: prefs(),
        createReader: (options) {
          seenOptions.add(options.toMap());
          return (key) async {
            asked.add(key);
            return switch (key) {
              'account_bilibili_credentials' => 'FAKE_BILIBILI_JSON',
              'account_netease_credentials' => throw StateError('AEADBadTag'),
              _ => null,
            };
          };
        },
      );
      final result = await reader.read(_keys);
      expect(result, {
        'account_bilibili_credentials': const LegacyCredentialFound(
          'FAKE_BILIBILI_JSON',
        ),
        'account_youtube_credentials': const LegacyCredentialMissing(),
        'account_netease_credentials': const LegacyCredentialUnreadable(),
      });
      // 一個壞條目不影響其他鍵：逐鍵讀。
      expect(asked, _keys);
      expect(seenOptions, hasLength(1));
      expect(seenOptions.single['resetOnError'], 'false');
      expect(seenOptions.single['migrateOnAlgorithmChange'], 'false');
      expect(seenOptions.single['storageNamespace'], '');
    });

    test('an instance that cannot be created: all unreadable', () async {
      prefs()
        ..createSync(recursive: true)
        ..writeAsStringSync('<map/>');
      final reader = AndroidLegacyCredentialReader(
        prefsFile: prefs(),
        createReader: (_) => throw StateError('no keystore'),
      );
      final result = await reader.read(_keys);
      expect(result.values, everyElement(const LegacyCredentialUnreadable()));
    });

    test('the prefs file is left alone', () async {
      prefs()
        ..createSync(recursive: true)
        ..writeAsStringSync('<map/>');
      final modified = prefs().lastModifiedSync();
      await AndroidLegacyCredentialReader(
        prefsFile: prefs(),
        createReader: (_) =>
            (_) async => 'x',
      ).read(_keys);
      expect(prefs().readAsStringSync(), '<map/>');
      expect(prefs().lastModifiedSync(), modified);
    });

    test('the log has key names and result kinds, never values', () async {
      prefs()
        ..createSync(recursive: true)
        ..writeAsStringSync('<map/>');
      final log = _log();
      await AndroidLegacyCredentialReader(
        prefsFile: prefs(),
        createReader: (_) =>
            (key) async => 'FAKE_SECRET_VALUE_123',
        log: log,
      ).read(_keys);
      final text = log.history
          .map((r) => '${r.message} ${r.fields}')
          .join('\n');
      expect(text, contains('account_youtube_credentials'));
      expect(text, contains('found'));
      expect(text, isNot(contains('FAKE_SECRET_VALUE_123')));
    });
  });

  test('platforms without legacy data: every key is missing', () async {
    final result = await const NoLegacyCredentialReader().read(_keys);
    expect(result.keys, _keys);
    expect(result.values, everyElement(const LegacyCredentialMissing()));
  });
}
