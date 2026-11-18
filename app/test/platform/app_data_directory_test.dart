import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/app_data_directory.dart';
import 'package:fmp/platform/cover_image.dart';
import 'package:fmp/platform/database_file.dart';
import 'package:fmp/platform/log_directory.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../support/no_network.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider({required this.support, required this.temporary});

  final Directory support;
  final Directory temporary;

  @override
  Future<String?> getApplicationSupportPath() async => support.path;

  @override
  Future<String?> getTemporaryPath() async => temporary.path;
}

/// App 的資料放在哪（docs/development.md〈實跑驅動〉）：平常在 application
/// support 目錄；實跑帶了隔離資料的名稱，就整份放進系統暫存目錄底下那一格，
/// 不碰 dev 版的資料。
void main() {
  late PathProviderPlatform original;
  late Directory root;
  late Directory support;
  late Directory temporary;

  setUp(() {
    original = PathProviderPlatform.instance;
    root = Directory.systemTemp.createTempSync('fmp_data_');
    support = Directory('${root.path}/support')..createSync();
    temporary = Directory('${root.path}/tmp')..createSync();
    PathProviderPlatform.instance = _FakePathProvider(
      support: support,
      temporary: temporary,
    );
  });
  tearDown(() {
    PathProviderPlatform.instance = original;
    root.deleteSync(recursive: true);
  });

  test(
    'without a scratch name the data lives in the app support directory',
    () async {
      final data = await appDataDirectory(scratch: '');

      expect(data.path, support.path);
      expect((await databaseFile(data)).path, '${support.path}/fmp.sqlite');
      expect(logDirectory(data).path, '${support.path}/logs');
    },
  );

  test('with a scratch name the database, the log and the cover cache all '
      'live under it, and the app support directory stays untouched', () async {
    final data = await appDataDirectory(scratch: 'fmp-real-run');
    expect(data.path, '${temporary.path}/fmp-real-run');

    final database = await databaseFile(data);
    database.writeAsStringSync('db');
    logDirectory(data).createSync(recursive: true);
    // 換位置時還不建快取：開真的 App 的 integration_test 裝了零聯網守門，
    // 沒顯示封面就不該碰 http client。
    keepCoverCacheIn(data);
    // 套件建 Config 時就建一個 http client（不連線）；putFile 不下載，
    // 這個測試不會連網。
    final cache = HttpOverrides.runZoned(
      () => coverCache,
      createHttpClient: (_) => realHttpClient(),
    );
    final cover = await cache.putFile(
      'https://i0.hdslb.com/bfs/archive/cover.jpg',
      Uint8List.fromList([1, 2, 3]),
    );

    expect(database.path, startsWith(data.path));
    expect(cover.path, startsWith(data.path));
    expect(support.listSync(recursive: true), isEmpty);
    expect(
      temporary
          .listSync(recursive: true)
          .where((entry) => !entry.path.startsWith(data.path)),
      isEmpty,
    );
  });
}
