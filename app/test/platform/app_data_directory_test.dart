import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_android.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_windows.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fmp_app_data_directory_');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  group('Windows', () {
    late String documents;
    late String roaming;

    setUp(() {
      documents = p.join(root.path, 'Documents');
      roaming = p.join(root.path, 'Roaming');
    });

    /// 在 [programDirectory] 放一個執行檔；[installed] 時加上 `unins000.exe`。
    String install(String programDirectory, {bool installed = false}) {
      Directory(programDirectory).createSync(recursive: true);
      if (installed) {
        File(p.join(programDirectory, 'unins000.exe')).createSync();
      }
      return p.join(programDirectory, 'fmp.exe');
    }

    WindowsAppDataDirectory windows(
      AppFlavor flavor, {
      required String executablePath,
      String? applicationSupport,
      String? roamingAppData,
    }) {
      return WindowsAppDataDirectory(
        flavor: flavor,
        executablePath: executablePath,
        roamingAppDataPath: roamingAppData ?? roaming,
        applicationSupportPath: () async =>
            applicationSupport ?? fail('portable must not ask path_provider'),
        documentsPath: () async => documents,
      );
    }

    test('portable prod uses userdata/ beside the program', () async {
      final program = p.join(root.path, 'FMP-portable');
      final directory = await windows(
        AppFlavor.prod,
        executablePath: install(program),
      ).resolve();

      expect(directory.path, p.join(program, 'userdata'));
      expect(directory.existsSync(), isTrue);
    });

    test('portable dev uses userdata-dev/ beside the program', () async {
      final program = p.join(root.path, 'FMP-portable');
      final directory = await windows(
        AppFlavor.dev,
        executablePath: install(program),
      ).resolve();

      expect(directory.path, p.join(program, 'userdata-dev'));
    });

    test('installed uses the application support directory', () async {
      final support = p.join(roaming, 'com.personal', 'fmp-dev');
      final directory = await windows(
        AppFlavor.dev,
        executablePath: install(
          p.join(root.path, 'Programs', 'FMP'),
          installed: true,
        ),
        applicationSupport: support,
      ).resolve();

      expect(directory.path, support);
      expect(directory.existsSync(), isTrue);
    });

    test(r'dev refuses a directory inside the legacy Documents\FMP', () async {
      final executable = install(p.join(documents, 'FMP', 'portable'));

      await expectLater(
        windows(AppFlavor.dev, executablePath: executable).resolve(),
        throwsA(
          isA<LegacyDataLocationException>().having(
            (error) => error.legacyLocation,
            'legacyLocation',
            p.join(documents, 'FMP'),
          ),
        ),
      );
      expect(
        Directory(p.join(documents, 'FMP', 'portable', 'userdata-dev'))
            .existsSync(),
        isFalse,
      );
    });

    test('dev refuses the legacy application support directory', () async {
      final legacy = p.join(roaming, 'com.personal', 'fmp');

      await expectLater(
        windows(
          AppFlavor.dev,
          executablePath: install(
            p.join(root.path, 'Programs', 'FMP'),
            installed: true,
          ),
          applicationSupport: legacy,
        ).resolve(),
        throwsA(isA<LegacyDataLocationException>()),
      );
    });

    test('prod may use the legacy application support directory', () async {
      // 正式版與舊版同一身分（ADR 0008），目錄重疊是預期的；舊資料匯入在 M5。
      final legacy = p.join(roaming, 'com.personal', 'fmp');
      final directory = await windows(
        AppFlavor.prod,
        executablePath: install(
          p.join(root.path, 'Programs', 'FMP'),
          installed: true,
        ),
        applicationSupport: legacy,
      ).resolve();

      expect(directory.path, legacy);
    });
  });

  group('Android', () {
    AndroidAppDataDirectory android(AppFlavor flavor, String applicationId) {
      return AndroidAppDataDirectory(
        flavor: flavor,
        applicationSupportPath: () async =>
            p.join(root.path, 'data', 'user', '0', applicationId, 'files'),
      );
    }

    test('dev uses its own sandbox, next to the legacy one', () async {
      final directory = await android(
        AppFlavor.dev,
        'com.personal.fmp.dev',
      ).resolve();

      expect(
        directory.path,
        p.join(root.path, 'data', 'user', '0', 'com.personal.fmp.dev', 'files'),
      );
      expect(directory.existsSync(), isTrue);
    });

    test('dev refuses the legacy sandbox', () async {
      await expectLater(
        android(AppFlavor.dev, 'com.personal.fmp').resolve(),
        throwsA(
          isA<LegacyDataLocationException>().having(
            (error) => error.legacyLocation,
            'legacyLocation',
            p.join(root.path, 'data', 'user', '0', 'com.personal.fmp'),
          ),
        ),
      );
    });

    test('prod uses the legacy sandbox (same applicationId)', () async {
      final directory = await android(
        AppFlavor.prod,
        'com.personal.fmp',
      ).resolve();

      expect(
        directory.path,
        p.join(root.path, 'data', 'user', '0', 'com.personal.fmp', 'files'),
      );
    });
  });

  group('ensureOutsideLegacyData', () {
    test('refuses the legacy location itself and anything below it', () {
      final legacy = p.join(root.path, 'FMP');

      expect(
        () => ensureOutsideLegacyData(legacy, [legacy]),
        throwsA(isA<LegacyDataLocationException>()),
      );
      expect(
        () => ensureOutsideLegacyData(p.join(legacy, 'a', 'b'), [legacy]),
        throwsA(isA<LegacyDataLocationException>()),
      );
    });

    test('accepts a sibling whose name only starts with the legacy name', () {
      final legacy = p.join(root.path, 'FMP');

      expect(
        () => ensureOutsideLegacyData(p.join(root.path, 'FMP-dev'), [legacy]),
        returnsNormally,
      );
    });
  });
}
