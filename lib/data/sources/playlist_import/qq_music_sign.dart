import 'dart:convert';

import 'package:crypto/crypto.dart';

/// QQ 音樂歌單 API 的 `sign` 參數。
///
/// 常數（XOR 金鑰、兩組取字元位置、`zzb` 前綴）與運算步驟是協定事實，取自
/// 公開的逆向工程資料；這裡的**表達**是獨立寫的：位元組直接取自 MD5 摘要而
/// 不是回頭解析十六進位字串，中段交給標準庫的 base64 而不是手寫轉換迴圈。
class QQMusicSign {
  /// 對 MD5 摘要逐位元組 XOR 的固定金鑰。
  static const _xorKey = [
    212, 45, 80, 68, 195, 163, 163, 203, //
    157, 220, 254, 91, 204, 79, 104, 6,
  ];

  /// 簽名前段取的 8 個十六進位字元位置。
  static const _headIndices = [21, 4, 9, 26, 16, 20, 27, 30];

  /// 簽名後段取的 8 個十六進位字元位置。
  static const _tailIndices = [18, 11, 3, 2, 1, 7, 6, 25];

  /// 產生 [param] 的簽名。
  static String encrypt(String param) {
    final digest = md5.convert(utf8.encode(param));
    final hex = digest.toString();

    final head = _pick(hex, _headIndices);
    final tail = _pick(hex, _tailIndices);

    final scrambled = [
      for (var i = 0; i < _xorKey.length; i++) digest.bytes[i] ^ _xorKey[i],
    ];

    // 16 個位元組編出 22 個 base64 字元加兩個補位符。伺服器只收字母與數字，
    // 所以補位符與 `+` / `/` 一併濾掉 —— 簽名長度因此會隨輸入浮動。
    final middle = base64.encode(scrambled).replaceAll(RegExp(r'[+/=]'), '');

    return 'zzb$head$middle$tail'.toLowerCase();
  }

  static String _pick(String hex, List<int> indices) =>
      indices.map((i) => hex[i]).join();
}
