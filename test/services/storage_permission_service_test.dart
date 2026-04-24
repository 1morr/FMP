import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/storage_permission_service.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('StoragePermissionService SDK branching', () {
    tearDown(StoragePermissionService.resetDebugOverrides);

    test('non-Android platforms are treated as already permitted', () async {
      StoragePermissionService.debugIsAndroidOverride = false;

      expect(await StoragePermissionService.hasStoragePermission(), isTrue);
    });

    test('Android 10 and lower checks storage permission', () async {
      var storageChecked = false;
      var manageChecked = false;
      StoragePermissionService.debugIsAndroidOverride = true;
      StoragePermissionService.debugAndroidSdkProvider = () async => 29;
      StoragePermissionService.debugStorageGranted = () async {
        storageChecked = true;
        return true;
      };
      StoragePermissionService.debugManageExternalStorageGranted = () async {
        manageChecked = true;
        return false;
      };

      expect(await StoragePermissionService.hasStoragePermission(), isTrue);
      expect(storageChecked, isTrue);
      expect(manageChecked, isFalse);
    });

    test('Android 11 and higher checks manage external storage permission',
        () async {
      var storageChecked = false;
      var manageChecked = false;
      StoragePermissionService.debugIsAndroidOverride = true;
      StoragePermissionService.debugAndroidSdkProvider = () async => 30;
      StoragePermissionService.debugStorageGranted = () async {
        storageChecked = true;
        return false;
      };
      StoragePermissionService.debugManageExternalStorageGranted = () async {
        manageChecked = true;
        return true;
      };

      expect(await StoragePermissionService.hasStoragePermission(), isTrue);
      expect(manageChecked, isTrue);
      expect(storageChecked, isFalse);
    });

    testWidgets('Android 10 denied request returns false from storage permission branch', (tester) async {
      StoragePermissionService.debugIsAndroidOverride = true;
      StoragePermissionService.debugAndroidSdkProvider = () async => 29;
      StoragePermissionService.debugRequestStorage = () async => PermissionStatus.denied;
      StoragePermissionService.debugRequestManageExternalStorage = () async {
        throw StateError('manageExternalStorage should not be requested');
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final allowed = await StoragePermissionService.requestStoragePermission(context);
                expect(allowed, isFalse);
              },
              child: const Text('request'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('request'));
      await tester.pump();
    });
  });
}
