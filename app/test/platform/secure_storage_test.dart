import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/secure_storage/flutter_secure_storage_adapter.dart';

void main() {
  group('FlutterSecureStorageAdapter', () {
    late Map<String, String> raw;
    late FlutterSecureStorageAdapter dev;
    late FlutterSecureStorageAdapter prod;

    FlutterSecureStorageAdapter adapter(String prefix) =>
        FlutterSecureStorageAdapter(
          prefix: prefix,
          read: (key) async => raw[key],
          write: (key, value) async => raw[key] = value,
          delete: (key) async => raw.remove(key),
          readAll: () async => {...raw},
        );

    setUp(() {
      raw = {};
      dev = adapter('fmp-dev.');
      prod = adapter('fmp.');
    });

    test('keys are stored under the flavor prefix and read back', () async {
      await dev.write('credentials.bilibili', 'FAKE-VALUE');

      expect(raw, {'fmp-dev.credentials.bilibili': 'FAKE-VALUE'});
      expect(await dev.read('credentials.bilibili'), 'FAKE-VALUE');
      expect(await prod.read('credentials.bilibili'), isNull);
    });

    test('delete removes one key and ignores a missing one', () async {
      await dev.write('a', 'one');
      await dev.write('b', 'two');
      await dev.delete('a');
      await dev.delete('missing');

      expect(await dev.read('a'), isNull);
      expect(await dev.read('b'), 'two');
    });

    test('deleteAll removes only its own prefix', () async {
      await dev.write('a', 'one');
      await prod.write('a', 'two');
      raw['foreign'] = 'three';

      await dev.deleteAll();

      expect(raw, {'fmp.a': 'two', 'foreign': 'three'});
    });

    for (final key in ['', 'Upper', 'a:b', 'a/b', 'a_b', '.dot', 'a b']) {
      test('the key "$key" is rejected', () async {
        await expectLater(dev.read(key), throwsArgumentError);
        await expectLater(dev.write(key, 'x'), throwsArgumentError);
        await expectLater(dev.delete(key), throwsArgumentError);
        expect(raw, isEmpty);
      });
    }

    test('a read failure is not swallowed', () async {
      final failing = FlutterSecureStorageAdapter(
        prefix: 'fmp.',
        read: (_) async => throw StateError('keystore'),
        write: (_, _) async {},
        delete: (_) async {},
        readAll: () async => {},
      );

      await expectLater(failing.read('a'), throwsStateError);
    });
  });

  group('Android options', () {
    test('never reset the store on a read error (ADR 0012)', () {
      for (final flavor in AppFlavor.values) {
        final options = FlutterSecureStorageAdapter.androidOptions(flavor)
            .toMap();

        expect(options['resetOnError'], 'false');
        expect(
          options['storageNamespace'],
          flavor == AppFlavor.dev ? 'fmp-dev' : 'fmp',
        );
      }
    });
  });
}
