import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/log_directory.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.support);

  final String support;

  @override
  Future<String?> getApplicationSupportPath() async => support;
}

void main() {
  late PathProviderPlatform original;
  setUp(() => original = PathProviderPlatform.instance);
  tearDown(() => PathProviderPlatform.instance = original);

  test('log files live in logs/ under the app support directory', () async {
    PathProviderPlatform.instance = _FakePathProvider('/fake/support');

    final dir = await logDirectory();

    expect(dir.path, '/fake/support/logs');
  });
}
