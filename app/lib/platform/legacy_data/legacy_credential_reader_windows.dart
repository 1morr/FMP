import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';

const _tag = 'legacy-credentials';

/// 舊版 `flutter_secure_storage_windows` 的檔名：整份鍵值 JSON 以 DPAPI 加密成單一檔案。
const legacySecureStorageFileName = 'flutter_secure_storage.dat';

/// 解開 DPAPI 加密的位元組；失敗拋例外。
typedef DpapiUnprotect = Uint8List Function(Uint8List encrypted);

/// Windows：讀 `<目錄>/flutter_secure_storage.dat`（M5 design §0.1、§4.3）。
///
/// 檔案位元組 → `CryptUnprotectData`（無 entropy）→ UTF-8 → JSON map → 取鍵。**只讀**：
/// 套件的 `load` 解不開時會刪整個檔案，所以不經套件。檔案不在是全部「沒有」；解不開、
/// 不是 JSON 物件是全部「讀不出」；值不是字串的鍵當「沒有」（套件的 `load` 同樣濾掉）。
final class WindowsLegacyCredentialReader implements LegacyCredentialReader {
  WindowsLegacyCredentialReader({
    required this._directory,
    this._unprotect = dpapiUnprotect,
    this._log,
  });

  final Directory _directory;
  final DpapiUnprotect _unprotect;
  final Log? _log;

  @override
  Future<Map<String, LegacyCredentialRead>> read(List<String> keys) async {
    final result = await _readAll(keys);
    for (final MapEntry(:key, :value) in result.entries) {
      _log?.info(
        'Read a legacy credential',
        tag: _tag,
        fields: {'key': key, 'result': value.label},
      );
    }
    return result;
  }

  Future<Map<String, LegacyCredentialRead>> _readAll(List<String> keys) async {
    Map<String, LegacyCredentialRead> all(LegacyCredentialRead value) => {
      for (final key in keys) key: value,
    };
    final file = File('${_directory.path}/$legacySecureStorageFileName');
    final Uint8List bytes;
    try {
      if (!file.existsSync()) return all(const LegacyCredentialMissing());
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return all(const LegacyCredentialUnreadable());
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(_unprotect(bytes)));
    } on Object {
      // 解密失敗、不是 UTF-8、不是 JSON：訊息可能含內容片段，不記。
      return all(const LegacyCredentialUnreadable());
    }
    if (decoded is! Map<String, Object?>) {
      return all(const LegacyCredentialUnreadable());
    }
    return {
      for (final key in keys)
        key: switch (decoded[key]) {
          final String value => LegacyCredentialFound(value),
          _ => const LegacyCredentialMissing(),
        },
    };
  }
}

/// `CryptUnprotectData`（無 entropy）；結果的緩衝區以 `LocalFree` 釋放。失敗拋
/// [WindowsException]。
Uint8List dpapiUnprotect(Uint8List encrypted) => using((alloc) {
  final input = alloc<Uint8>(encrypted.length);
  input.asTypedList(encrypted.length).setAll(0, encrypted);
  final inputBlob = alloc<CRYPT_INTEGER_BLOB>()
    ..ref.cbData = encrypted.length
    ..ref.pbData = input;
  final outputBlob = alloc<CRYPT_INTEGER_BLOB>();
  final Win32Result(value: ok, error: error) = CryptUnprotectData(
    inputBlob,
    null,
    null,
    null,
    0,
    outputBlob,
  );
  if (!ok) {
    throw WindowsException(
      error.toHRESULT(),
      message: 'Failure on CryptUnprotectData()',
    );
  }
  final data = outputBlob.ref.pbData;
  if (data.address == NULL) {
    throw WindowsException(
      ERROR_OUTOFMEMORY.toHRESULT(),
      message: 'Failure on CryptUnprotectData()',
    );
  }
  try {
    // 複製出來：緩衝區在 finally 釋放。
    return Uint8List.fromList(data.asTypedList(outputBlob.ref.cbData));
  } finally {
    LocalFree(HLOCAL(data.cast()));
  }
});
