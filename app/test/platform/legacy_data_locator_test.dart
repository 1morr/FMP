import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader_android.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader_windows.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locations.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';
import 'package:fmp/platform/legacy_data/legacy_dev_entry.dart';
import 'package:path/path.dart' as p;

// 找舊資料（M5 design §4.1、§4.3、§8.1）：候選位置的順序、dev 入口只在 dev 讀、真實的舊資料
// 位置被拒。路徑全部注入，在暫存目錄上跑。

void main() {
  group('the dev entry', () {
    const arguments = ['--fmp-legacy-dir=/copy', '--other'];
    const environment = {'FMP_LEGACY_DIR': '/from-env'};

    test('prod reads neither the argument nor the environment variable', () {
      expect(legacyDirectoryPath(AppFlavor.prod, arguments, environment), null);
      expect(legacyDirectoryPath(AppFlavor.prod, const [], environment), null);
      expect(legacyDirectoryPath(AppFlavor.prod, arguments, const {}), null);
    });

    test('dev prefers the argument, then the environment variable', () {
      expect(
        legacyDirectoryPath(AppFlavor.dev, arguments, environment),
        '/copy',
      );
      expect(
        legacyDirectoryPath(AppFlavor.dev, const ['--other'], environment),
        '/from-env',
      );
      expect(legacyDirectoryPath(AppFlavor.dev, const [], const {}), isNull);
    });

    test('an empty value counts as not given', () {
      expect(
        legacyDirectoryPath(
          AppFlavor.dev,
          const ['--fmp-legacy-dir='],
          const {'FMP_LEGACY_DIR': ''},
        ),
        isNull,
      );
      expect(
        legacyDirectoryPath(AppFlavor.dev, const [
          '--fmp-legacy-dir=',
        ], environment),
        '/from-env',
      );
    });
  });

  group('Windows', () {
    late Directory temp;
    late Directory documents;
    late Directory support;
    late Directory roaming;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('fmp_legacy_locator_test');
      addTearDown(() => temp.delete(recursive: true));
      documents = Directory(p.join(temp.path, 'Documents'))..createSync();
      support = Directory(p.join(temp.path, 'support'))..createSync();
      roaming = Directory(p.join(temp.path, 'Roaming'))..createSync();
    });

    LegacyDataLocator locator({
      AppFlavor flavor = AppFlavor.prod,
      String? devDirectory,
    }) => windowsLegacyDataLocator(
      flavor: flavor,
      devDirectory: devDirectory,
      documentsPath: () async => documents.path,
      applicationSupportPath: () async => support.path,
      roamingAppDataPath: roaming.path,
    );

    File put(String directory, [String name = legacyDatabaseFile]) {
      final file = File(p.join(directory, name))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      return file;
    }

    test('prod looks at Documents/FMP first, then Documents', () async {
      expect(await locator().locate(), isNull);

      final root = put(documents.path);
      expect((await locator().locate())!.database.path, root.path);

      final fmp = put(p.join(documents.path, 'FMP'));
      expect((await locator().locate())!.database.path, fmp.path);
    });

    test('prod reads the credentials from application support', () async {
      put(documents.path);
      final source = (await locator().locate())!;
      expect(source.credentialReader, isA<WindowsLegacyCredentialReader>());
      // 憑證檔在 application support，不在資料庫旁。
      File(p.join(support.path, legacySecureStorageFileName))
          .writeAsStringSync('not DPAPI');
      final read = await source.credentialReader.read(['k']);
      expect(read['k'], isA<LegacyCredentialUnreadable>());
    });

    test('prod ignores the dev directory', () async {
      final copy = Directory(p.join(temp.path, 'copy'));
      put(copy.path);
      expect(await locator(devDirectory: copy.path).locate(), isNull);
    });

    test('dev looks only at the given directory', () async {
      put(documents.path);
      put(p.join(documents.path, 'FMP'));
      expect(await locator(flavor: AppFlavor.dev).locate(), isNull);

      final copy = Directory(p.join(temp.path, 'copy'));
      expect(
        await locator(flavor: AppFlavor.dev, devDirectory: copy.path).locate(),
        isNull,
      );
      final file = put(copy.path);
      final source = (await locator(
        flavor: AppFlavor.dev,
        devDirectory: copy.path,
      ).locate())!;
      expect(source.database.path, file.path);
      expect(source.credentialReader, isA<WindowsLegacyCredentialReader>());
    });

    for (final (name, path) in [
      ('Documents/FMP', 'Documents/FMP'),
      ('inside Documents/FMP', 'Documents/FMP/copy'),
      ('the roaming secure storage directory', 'Roaming/com.personal/fmp'),
      ('inside it', 'Roaming/com.personal/fmp/copy'),
      // 繞路的寫法：`..` 與結尾的分隔符號比對前會正規化。
      ('a path through ..', 'copy/../Documents/FMP/copy'),
      ('a trailing separator', 'Documents/FMP/'),
    ]) {
      test('dev refuses $name', () async {
        final directory = p.join(temp.path, p.joinAll(path.split('/')));
        put(directory);
        await expectLater(
          locator(flavor: AppFlavor.dev, devDirectory: directory).locate(),
          throwsA(isA<LegacyDataLocationException>()),
        );
      });
    }

    test('dev accepts a directory that only shares the prefix', () async {
      final near = p.join(temp.path, 'Documents', 'FMP-copy');
      final file = put(near);
      final source = await locator(
        flavor: AppFlavor.dev,
        devDirectory: near,
      ).locate();
      expect(source!.database.path, file.path);
    });
  });

  group('Android', () {
    late Directory temp;
    late Directory sandbox;
    late Directory documents;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('fmp_legacy_locator_test');
      addTearDown(() => temp.delete(recursive: true));
      // `<資料根>/<applicationId>/app_flutter` 與 `.../files`
      sandbox = Directory(p.join(temp.path, 'com.personal.fmp'))..createSync();
      documents = Directory(p.join(sandbox.path, 'app_flutter'))..createSync();
    });

    LegacyDataLocator locator({
      AppFlavor flavor = AppFlavor.prod,
      String? devDirectory,
      Directory? applicationSandbox,
    }) {
      final root = applicationSandbox ?? sandbox;
      return androidLegacyDataLocator(
        flavor: flavor,
        devDirectory: devDirectory,
        documentsPath: () async => p.join(root.path, 'app_flutter'),
        applicationSupportPath: () async => p.join(root.path, 'files'),
      );
    }

    File put(String directory) => File(p.join(directory, legacyDatabaseFile))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');

    test('prod looks at app_flutter/FMP first, then app_flutter', () async {
      expect(await locator().locate(), isNull);

      final root = put(documents.path);
      expect((await locator().locate())!.database.path, root.path);

      final fmp = put(p.join(documents.path, 'FMP'));
      expect((await locator().locate())!.database.path, fmp.path);
    });

    test('prod reads the old preferences file in the sandbox', () async {
      put(documents.path);
      final source = (await locator().locate())!;
      expect(source.credentialReader, isA<AndroidLegacyCredentialReader>());
      // 沒有 shared_prefs/FlutterSecureStorage.xml：全部「沒有」，不建立套件實例。
      final read = await source.credentialReader.read(['k']);
      expect(read['k'], isA<LegacyCredentialMissing>());
    });

    test('dev reads only the given directory and no credentials', () async {
      final dev = Directory(p.join(temp.path, 'com.personal.fmp.dev'));
      put(p.join(dev.path, 'app_flutter', 'FMP'));
      final copy = p.join(dev.path, 'files', 'legacy-copy');
      expect(
        await locator(flavor: AppFlavor.dev, applicationSandbox: dev).locate(),
        isNull,
      );
      final file = put(copy);
      final source = (await locator(
        flavor: AppFlavor.dev,
        devDirectory: copy,
        applicationSandbox: dev,
      ).locate())!;
      expect(source.database.path, file.path);
      expect(source.credentialReader, isA<NoLegacyCredentialReader>());
    });

    test('prod ignores the dev directory', () async {
      final copy = p.join(temp.path, 'copy');
      put(copy);
      expect(await locator(devDirectory: copy).locate(), isNull);
    });

    test('dev refuses the old applicationId sandbox', () async {
      // dev 的沙盒是 `com.personal.fmp.dev`；位於 `com.personal.fmp` 之下的路徑被拒。
      final dev = Directory(p.join(temp.path, 'com.personal.fmp.dev'));
      final inside = p.join(sandbox.path, 'files', 'legacy-copy');
      put(inside);
      await expectLater(
        locator(
          flavor: AppFlavor.dev,
          devDirectory: inside,
          applicationSandbox: dev,
        ).locate(),
        throwsA(isA<LegacyDataLocationException>()),
      );
      // 只是前綴相同的 dev 沙盒不算。
      final own = p.join(dev.path, 'files', 'legacy-copy');
      final file = put(own);
      expect(
        (await locator(
          flavor: AppFlavor.dev,
          devDirectory: own,
          applicationSandbox: dev,
        ).locate())!.database.path,
        file.path,
      );
    });
  });

  group('macOS', () {
    late Directory copy;

    setUp(() async {
      copy = await Directory.systemTemp.createTemp('fmp_legacy_macos_test');
      addTearDown(() => copy.delete(recursive: true));
      File(p.join(copy.path, legacyDatabaseFile)).writeAsStringSync('x');
    });

    test(
      'prod has no legacy location, even when --fmp-legacy-dir is given',
      () async {
        final locator = macosLegacyDataLocator(
          flavor: AppFlavor.prod,
          devDirectory: copy.path,
        );

        expect(await locator.locate(), isNull);
      },
    );

    test('dev reads only the given copy, without legacy credentials', () async {
      final source = await macosLegacyDataLocator(
        flavor: AppFlavor.dev,
        devDirectory: copy.path,
      ).locate();

      expect(source!.database.path, p.join(copy.path, legacyDatabaseFile));
      expect(source.credentialReader, isA<NoLegacyCredentialReader>());
    });

    test('dev without a copy has no legacy location', () async {
      final locator = macosLegacyDataLocator(
        flavor: AppFlavor.dev,
        devDirectory: null,
      );

      expect(await locator.locate(), isNull);
    });
  });
}
