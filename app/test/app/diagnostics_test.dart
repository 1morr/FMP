import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/diagnostics/diagnostics_report.dart';
import 'package:fmp/app/diagnostics/diagnostics_service.dart';
import 'package:fmp/app/diagnostics/diagnostics_zip.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/platform/share/share.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:path/path.dart' as p;

import '../support/credentials.dart';
import '../support/memory_database.dart';

// 所有憑證、帳號名稱與家目錄都是明顯的假值（FAKE_…），不得換成真實值。
const _fakeHome = r'C:\Users\FAKE_USER';
const _fakeSecret = 'FAKE_SESSDATA_123';
const _fakeDisplayName = 'FAKE_DISPLAY_NAME';
const _signedUrl =
    'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/x.m4s'
    '?e=FAKE_E_PAYLOAD_123&deadline=1700000000&upsig=FAKE_UPSIG_123';

/// 四種不該出現在診斷包的東西。
const _forbidden = [
  _fakeSecret,
  'FAKE_E_PAYLOAD_123',
  'FAKE_UPSIG_123',
  _fakeDisplayName,
  'FAKE_USER',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Redactor redactor;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fmp_diagnostics_test');
    addTearDown(() => temp.delete(recursive: true));
    redactor = Redactor()..registerHomeDirectory(_fakeHome);
  });

  /// 解開 zip，鍵是檔名。
  Map<String, String> unzip(Uint8List bytes) => {
    for (final file in ZipDecoder().decodeBytes(bytes))
      file.name: utf8.decode(file.content),
  };

  group('report', () {
    Map<String, Object?> dirty() => {
      'app': {'version': '1.0.0', 'dataDirectory': '$_fakeHome\\AppData\\fmp'},
      'untrusted': [
        'Cookie: SESSDATA=$_fakeSecret; theme=dark',
        _signedUrl,
        'registered $_fakeSecret value',
        _fakeDisplayName,
      ],
      'plugins': [
        {'id': 'bilibili', 'version': '1.0.0', 'enabled': true},
        {'id': 'fmp-test', 'version': '2.0.0', 'enabled': false},
      ],
      'nothing': null,
    };

    test('text and JSON hold the same data, both masked', () {
      redactor
        ..registerSecret(_fakeSecret)
        ..registerSecret(_fakeDisplayName);

      final report = DiagnosticsReport.build(dirty(), redactor);

      expect(jsonDecode(report.json), report.data);
      for (final output in [report.text, report.json]) {
        for (final value in _forbidden) {
          expect(output, isNot(contains(value)), reason: value);
        }
      }
      expect(report.text, contains(r'dataDirectory: ~\AppData\fmp'));
      // 診斷包的 JSON 裡反斜線是兩個：家目錄在編碼之後也要遮到。
      expect(report.json, contains(r'"dataDirectory": "~\\AppData\\fmp"'));
      expect(
        report.text,
        contains('- id=bilibili, version=1.0.0, enabled=yes'),
      );
      expect(report.text, contains('- id=fmp-test, version=2.0.0, enabled=no'));
      expect(report.text, contains('nothing: -'));
    });
  });

  group('zip', () {
    test('every entry can be read back, in a separate isolate', () async {
      final bytes = await zipEntries([
        ZipEntry('a.txt', Uint8List.fromList(utf8.encode('alpha'))),
        ZipEntry('b.jsonl', Uint8List.fromList(utf8.encode('{"n":1}\n'))),
      ]);

      expect(unzip(bytes), {'a.txt': 'alpha', 'b.jsonl': '{"n":1}\n'});
    });
  });

  group('service', () {
    late Directory logs;
    late LogFile logFile;
    setUp(() {
      logs = Directory(p.join(temp.path, 'logs'));
      logFile = LogFile(logs);
    });

    DiagnosticsService service({LogFile? file, bool includeDirty = true}) =>
        DiagnosticsService(
          redactor: redactor,
          logFile: file,
          collect: () async => {
            'app': {'version': '1.0.0'},
            if (includeDirty) 'untrusted': 'Cookie: SESSDATA=$_fakeSecret',
          },
        );

    test('the diagnostics zip holds the summary and every log file', () async {
      logFile.write('{"n":1}');
      await logFile.flush();
      await logs.create(recursive: true);
      File(p.join(logs.path, 'fmp.1.jsonl')).writeAsStringSync('{"n":0}\n');

      final bundle = await withClock(
        Clock.fixed(DateTime(2026, 10, 14, 15, 30, 9)),
        service(file: logFile).diagnosticsBundle,
      );

      expect(bundle.fileName, 'fmp-diagnostics-20261014-153009.zip');
      expect(bundle.fileName, isNot(contains(':')));
      final files = unzip(bundle.bytes);
      expect(files.keys, [
        'diagnostics.txt',
        'diagnostics.json',
        'fmp.jsonl',
        'fmp.1.jsonl',
      ]);
      expect(files['fmp.jsonl'], '{"n":1}\n');
      expect(files['diagnostics.txt'], contains('version: 1.0.0'));
      expect(jsonDecode(files['diagnostics.json']!), {
        'app': {'version': '1.0.0'},
        'untrusted': 'Cookie: ***',
      });
    });

    test('the log export holds the log files and nothing else', () async {
      logFile.write('{"n":1}');
      await logFile.flush();

      final bundle = await withClock(
        Clock.fixed(DateTime(2026, 1, 2, 3, 4, 5)),
        service(file: logFile).logsBundle,
      );

      expect(bundle.fileName, 'fmp-logs-20260102-030405.zip');
      expect(unzip(bundle.bytes), {'fmp.jsonl': '{"n":1}\n'});
    });

    test('a platform without a log file still gets the summary', () async {
      final bundle = await service().diagnosticsBundle();

      expect(unzip(bundle.bytes).keys, ['diagnostics.txt', 'diagnostics.json']);
    });

    test('log lines written through the facade carry no fake values', () async {
      // log 檔寫入時已經遮蔽（ADR 0011 §決定 3）；這裡驗的是「經門面寫的」東西進了 zip
      // 之後仍然乾淨，包括家目錄。
      redactor
        ..registerSecret(_fakeSecret)
        ..registerSecret(_fakeDisplayName);
      final log = Log(
        redactor: redactor,
        minimumLevel: LogLevel.debug,
        file: logFile,
      );
      log.info(
        'App started',
        tag: 'app',
        fields: {'dataDirectory': '$_fakeHome\\AppData\\fmp'},
      );
      log.error(
        'Request failed: Cookie: SESSDATA=$_fakeSecret $_signedUrl',
        tag: 'net',
        error: 'user $_fakeDisplayName at $_fakeHome',
      );

      final bundle = await service(file: logFile).diagnosticsBundle();

      final content = unzip(bundle.bytes)['fmp.jsonl']!;
      for (final value in _forbidden) {
        expect(content, isNot(contains(value)), reason: value);
      }
      expect(content, contains('~'));
    });

    test('lines written before the home directory was registered are masked '
        'in both zips', () async {
      // 更早的版本（或這次登記之前）寫的行：家目錄、之後才登記的憑證都還是原值。
      await logs.create(recursive: true);
      final old = LogRecord(
        time: DateTime.utc(2026, 10, 10),
        level: LogLevel.info,
        tag: 'app',
        message: 'App started',
        error: 'user $_fakeDisplayName',
        fields: {
          'dataDirectory': '$_fakeHome\\AppData\\Roaming\\fmp',
          'cookie': 'SESSDATA=$_fakeSecret',
        },
      ).toJsonLine();
      File(p.join(logs.path, 'fmp.1.jsonl'))
          .writeAsStringSync('$old\n{"truncated":"$_fakeHome\n');
      expect(
        File(p.join(logs.path, 'fmp.1.jsonl')).readAsStringSync(),
        contains(r'C:\\Users\\FAKE_USER\\AppData'),
      );
      redactor
        ..registerSecret(_fakeSecret)
        ..registerSecret(_fakeDisplayName);
      logFile.write(old);
      await logFile.flush();

      for (final bundle in [
        await service(file: logFile).diagnosticsBundle(),
        await service(file: logFile).logsBundle(),
      ]) {
        final files = unzip(bundle.bytes);
        for (final name in ['fmp.jsonl', 'fmp.1.jsonl']) {
          final content = files[name]!;
          for (final value in _forbidden) {
            expect(content, isNot(contains(value)), reason: '$name: $value');
          }
          // 仍是 JSON Lines：解析得出的行照樣解析得出。
          final record = LogRecord.tryParseJsonLine(content.split('\n').first)!;
          expect(record.fields['dataDirectory'], r'~\AppData\Roaming\fmp');
        }
      }
    });
  });

  group('the collected data', () {
    late ProviderContainer container;
    late InMemorySecureStorage storage;

    setUp(() async {
      final database = memoryDatabase();
      storage = InMemorySecureStorage();
      final plugins = PluginRepository(database);
      String manifest(String id, {required bool login}) => jsonEncode({
        'id': id,
        'name': id,
        'version': '1.0.0',
        'author': 'FMP tests',
        'apiVersion': 1,
        'capabilities': ['search', if (login) 'login'],
        'allowedHosts': ['example.test'],
        if (login)
          'login': {
            'methods': ['qr'],
          },
      });
      await plugins.install(
        InstalledPlugin(
          id: 'fake-login',
          version: '1.2.3',
          manifestJson: manifest('fake-login', login: true),
          script: '',
          installedAt: DateTime.utc(2026),
        ),
      );
      await plugins.install(
        InstalledPlugin(
          id: 'fake-plain',
          version: '2.0.0',
          manifestJson: manifest('fake-plain', login: false),
          script: '',
          installedAt: DateTime.utc(2026),
        ),
      );
      await plugins.setEnabled('fake-plain', enabled: false);
      await AccountRepository(database).upsert(
        Account(
          pluginId: 'fake-login',
          userId: 'FAKE_UID_1',
          displayName: _fakeDisplayName,
          status: AccountStatus.active,
          loggedInAt: DateTime.utc(2026, 10, 9),
        ),
      );
      storage.values['credentials.fake-login'] = jsonEncode(
        const LoginCredentials(cookies: {'SESSDATA': _fakeSecret}).toJson(),
      );
      container = ProviderContainer.test(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          secureStorageProvider.overrideWithValue(storage),
          redactorProvider.overrideWithValue(redactor),
          logProvider.overrideWithValue(
            Log(redactor: redactor, minimumLevel: LogLevel.debug),
          ),
          appFlavorProvider.overrideWithValue(AppFlavor.dev),
          appInfoProvider.overrideWithValue(
            const AppInfo(
              version: '1.0.0',
              platform: 'Windows',
              osVersion: 'FAKE OS 10.0',
              homeDirectory: _fakeHome,
            ),
          ),
          dataDirectoryProvider.overrideWithValue(
            Directory('$_fakeHome\\AppData\\Roaming\\fmp-dev'),
          ),
          platformCapabilitiesProvider.overrideWithValue(
            const PlatformCapabilities(
              dataDirectory: true,
              singleInstance: false,
              secureStorage: true,
              fontFallback: FontFallback.none,
              playback: null,
              networkInterfaces: false,
              files: false,
              loginWebView: false,
              urlOpener: false,
              restartsItself: false,
              shareFiles: false,
              cache: CacheSizes(
                defaultLimitMebibytes: 256,
                memoryImages: 1,
                memoryImageMebibytes: 1,
              ),
            ),
          ),
        ],
      );
    });

    test('names the plugins and whether each is logged in, not who', () async {
      final report = await container.read(diagnosticsServiceProvider).report();

      final plugins = (report.data['plugins']! as List).cast<Map>();
      expect(plugins, [
        {
          'id': 'fake-login',
          'version': '1.2.3',
          'enabled': true,
          'loggedIn': true,
          'credentials': 'active',
        },
        {'id': 'fake-plain', 'version': '2.0.0', 'enabled': false},
      ]);
      expect(report.data['app'], containsPair('version', '1.0.0'));
      expect(report.data['platform'], containsPair('name', 'Windows'));
    });

    test('the four fake values never appear in the summary', () async {
      // 憑證在 CredentialStore 載入時登記到遮蔽函式；帳號名稱根本不在資料裡；家目錄由遮蔽函式換掉。
      final bundle = await container
          .read(diagnosticsServiceProvider)
          .diagnosticsBundle();

      final files = unzip(bundle.bytes);
      for (final output in files.values) {
        for (final value in _forbidden) {
          expect(output, isNot(contains(value)), reason: value);
        }
      }
      expect(files['diagnostics.txt'], contains(r'dataDirectory: ~\AppData'));
    });

    test('settings are summarized without paths or device names', () async {
      final report = await container.read(diagnosticsServiceProvider).report();

      final settings = report.data['settings']! as Map;
      expect(settings.keys, ['appearance', 'network', 'playback', 'developer']);
      expect((settings['playback']! as Map)['outputDeviceSelected'], isFalse);
      expect((settings['developer']! as Map)['pluginDevFolderSet'], isFalse);
    });
  });

  group('exporter', () {
    late _FakeDialogs dialogs;
    late _FakeSharer sharer;
    late Directory tempDirectory;
    late DiagnosticsExporter exporter;
    final bundle = DiagnosticsBundle(
      fileName: 'fmp-diagnostics-20261014-153009.zip',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    setUp(() {
      dialogs = _FakeDialogs();
      sharer = _FakeSharer();
      tempDirectory = Directory(
        p.join(temp.path, diagnosticsTempDirectoryName),
      );
      exporter = DiagnosticsExporter(
        fileDialogs: dialogs,
        fileSharer: sharer,
        tempDirectory: tempDirectory,
        log: Log(redactor: redactor, minimumLevel: LogLevel.debug),
      );
    });

    test('a saved file goes to the dialog and leaves no temp file', () async {
      expect(await exporter.save(bundle), isTrue);

      expect(dialogs.saved.single.name, bundle.fileName);
      expect(dialogs.saved.single.mimeType, 'application/zip');
      expect(tempDirectory.existsSync(), isFalse);
    });

    test('cancelling the dialog is not a save and leaves no temp', () async {
      dialogs.result = null;

      expect(await exporter.save(bundle), isFalse);
      expect(tempDirectory.existsSync(), isFalse);
    });

    test('shares a temp file and deletes it once the share finished', () async {
      await exporter.share(bundle);

      expect(sharer.shared.single.bytes, [1, 2, 3]);
      expect(p.dirname(sharer.shared.single.path), tempDirectory.path);
      expect(tempDirectory.listSync(), isEmpty);
    });

    test(
      'keeps the temp file when the platform cannot say it finished',
      () async {
        sharer.finished = false;

        await exporter.share(bundle);

        expect(tempDirectory.listSync(), hasLength(1));

        // 下一次分享前先清掉殘留的。
        sharer.finished = true;
        await exporter.share(
          DiagnosticsBundle(fileName: 'fmp-logs.zip', bytes: bundle.bytes),
        );
        expect(tempDirectory.listSync(), isEmpty);
      },
    );

    test('a share that cannot open removes the temp file and throws', () async {
      sharer.error = StateError('no share window');

      await expectLater(exporter.share(bundle), throwsStateError);

      expect(tempDirectory.listSync(), isEmpty);
    });

    test('deleteDiagnosticsTemp removes only the leftover directory', () async {
      tempDirectory.createSync(recursive: true);
      File(p.join(tempDirectory.path, 'old.zip')).writeAsBytesSync([1]);
      File(p.join(tempDirectory.path, 'older.zip')).writeAsBytesSync([1]);
      final keep = [
        File(p.join(temp.path, 'fmp.db'))..writeAsBytesSync([1]),
        File(p.join(temp.path, 'logs', 'fmp.jsonl'))
          ..createSync(recursive: true),
        File(p.join(temp.path, 'backups', 'fmp-1.db'))
          ..createSync(recursive: true),
      ];

      expect(await deleteDiagnosticsTemp(temp), 2);

      expect(tempDirectory.existsSync(), isFalse);
      for (final file in keep) {
        expect(file.existsSync(), isTrue, reason: file.path);
      }
      expect(await deleteDiagnosticsTemp(temp), 0);
    });
  });
}

final class _FakeDialogs implements FileDialogs {
  /// 存檔的結果；`null` 是取消。
  Uri? result = Uri.file('/fake/saved.zip');
  final saved = <({String name, Uint8List bytes, String mimeType})>[];

  @override
  Future<PickedFile?> pickFile({required String extension}) async => null;

  @override
  Future<Uri?> saveFile({
    required String name,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    saved.add((name: name, bytes: bytes, mimeType: mimeType));
    return result;
  }
}

final class _FakeSharer implements FileSharer {
  bool finished = true;
  Object? error;
  final shared = <({String path, Uint8List bytes})>[];

  @override
  Future<bool> shareFiles(
    List<String> paths, {
    required String mimeType,
  }) async {
    // 呼叫當下檔案必須在。
    for (final path in paths) {
      shared.add((path: path, bytes: File(path).readAsBytesSync()));
    }
    if (error case final error?) throw error;
    return finished;
  }
}
