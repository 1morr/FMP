import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader_windows.dart';
import 'package:integration_test/integration_test.dart';
import 'package:win32/win32.dart';

// 舊憑證的 Windows 讀取器用真的 DPAPI 往返（M5 design §9）：以 `CryptProtectData` 加密合成的
// JSON（假 cookie）寫到暫存目錄，`WindowsLegacyCredentialReader` 的預設解密讀回相同的值；
// 壞掉的位元組是「讀不出」，檔案不被動。只碰暫存目錄，不碰 %APPDATA% 的真實檔案。
//
//   flutter test integration_test/legacy_credentials_test.dart -d windows

/// 同 `flutter_secure_storage_windows` 的寫法：`CryptProtectData`、無 entropy。
Uint8List _protect(Uint8List plain) => using((alloc) {
  final input = alloc<Uint8>(plain.length);
  input.asTypedList(plain.length).setAll(0, plain);
  final inputBlob = alloc<CRYPT_INTEGER_BLOB>()
    ..ref.cbData = plain.length
    ..ref.pbData = input;
  final outputBlob = alloc<CRYPT_INTEGER_BLOB>();
  final Win32Result(value: ok, error: error) = CryptProtectData(
    inputBlob,
    null,
    null,
    null,
    0,
    outputBlob,
  );
  if (!ok) {
    throw WindowsException(error.toHRESULT(), message: 'CryptProtectData');
  }
  final data = outputBlob.ref.pbData;
  try {
    return Uint8List.fromList(data.asTypedList(outputBlob.ref.cbData));
  } finally {
    LocalFree(HLOCAL(data.cast()));
  }
});

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const keys = [
    'account_bilibili_credentials',
    'account_youtube_credentials',
    'account_netease_credentials',
  ];

  testWidgets('reads what CryptProtectData wrote, without touching the file', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('fmp-legacy-dpapi-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/$legacySecureStorageFileName');
    final json = jsonEncode({
      'account_bilibili_credentials': '{"sessdata":"FAKE_SESSDATA_123"}',
      'account_netease_credentials': '{"musicU":"FAKE_MUSIC_U_123"}',
      'fmp.credentials.bilibili': 'FAKE_NEW_VALUE',
    });
    file.writeAsBytesSync(_protect(Uint8List.fromList(utf8.encode(json))));
    final bytes = file.readAsBytesSync();
    final modified = file.lastModifiedSync();

    final result = await WindowsLegacyCredentialReader(directory: directory)
        .read(keys);

    expect(result, {
      'account_bilibili_credentials': const LegacyCredentialFound(
        '{"sessdata":"FAKE_SESSDATA_123"}',
      ),
      'account_youtube_credentials': const LegacyCredentialMissing(),
      'account_netease_credentials': const LegacyCredentialFound(
        '{"musicU":"FAKE_MUSIC_U_123"}',
      ),
    });
    expect(file.readAsBytesSync(), bytes);
    expect(file.lastModifiedSync(), modified);
  });

  testWidgets('bytes DPAPI cannot open are unreadable and stay on disk', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('fmp-legacy-dpapi-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/$legacySecureStorageFileName')
      ..writeAsBytesSync(Uint8List.fromList(List.generate(64, (i) => i)));
    final modified = file.lastModifiedSync();

    final result = await WindowsLegacyCredentialReader(directory: directory)
        .read(keys);

    expect(result.keys, keys);
    expect(result.values, everyElement(const LegacyCredentialUnreadable()));
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), List.generate(64, (i) => i));
    expect(file.lastModifiedSync(), modified);
  });

  testWidgets('no file: every key is missing', (tester) async {
    final directory = Directory.systemTemp.createTempSync('fmp-legacy-dpapi-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final result = await WindowsLegacyCredentialReader(directory: directory)
        .read(keys);
    expect(result.values, everyElement(const LegacyCredentialMissing()));
  });
}
