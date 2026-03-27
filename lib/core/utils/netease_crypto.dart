import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// 網易雲音樂 API 加密工具
///
/// 支持 weapi（Web API）和 eapi（Enhanced API）兩種加密模式。
/// weapi 用於 Web 端請求，eapi 用於移動端請求。
class NeteaseCrypto {
  NeteaseCrypto._();

  // ===== 常量 =====

  /// weapi AES 預設密鑰
  static const _presetKey = '0CoJUm6Qyw8W8jud';

  /// AES CBC/ECB 初始向量
  static const _iv = '0102030405060708';

  /// eapi AES 密鑰
  static const _eapiKey = 'e82ckenh8dichen8';

  /// 隨機密鑰字符集 (base62)
  static const _base62 =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// RSA 公鑰模數 (hex)
  static const _rsaModulusHex =
      '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725'
      '152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312'
      'ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424'
      'd813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';

  static final _rsaModulus = BigInt.parse(_rsaModulusHex, radix: 16);

  /// RSA 公鑰指數 (65537)
  static final _rsaExponent = BigInt.from(65537);

  /// eapi 分隔符
  static const _eapiSeparator = '-36cd479b6b5-';

  // ===== weapi 加密 =====

  /// weapi 加密
  ///
  /// 雙層 AES-128-CBC 加密 + RSA 密鑰封裝。
  /// 返回 `{params, encSecKey}` 用於 POST form body。
  static Map<String, String> weapi(Map<String, dynamic> data) {
    final text = jsonEncode(data);
    final secretKey = _generateRandomKey(16);

    // Layer 1: AES-CBC with preset key
    final layer1 = _aesCbcEncrypt(text, _presetKey, _iv);
    // Layer 2: AES-CBC with random key
    final params = _aesCbcEncrypt(layer1, secretKey, _iv);
    // RSA: encrypt reversed random key (no padding)
    final encSecKey = _rsaEncrypt(secretKey);

    return {'params': params, 'encSecKey': encSecKey};
  }

  // ===== eapi 加密 =====

  /// eapi 加密
  ///
  /// AES-128-ECB 加密，帶 MD5 完整性校驗。
  /// [url] API 路徑（如 `/api/song/enhance/player/url/v1`）
  /// [data] 請求數據
  /// 返回 hex 編碼的加密字串（大寫），用作 `params` POST 參數。
  static String eapi(String url, Map<String, dynamic> data) {
    final text = jsonEncode(data);
    final message = 'nobody${url}use${text}md5forencrypt';
    final digest = md5.convert(utf8.encode(message)).toString();
    final payload = '$url$_eapiSeparator$text$_eapiSeparator$digest';

    final key = Key.fromUtf8(_eapiKey);
    final encrypter = Encrypter(AES(key, mode: AESMode.ecb, padding: 'PKCS7'));
    final encrypted = encrypter.encryptBytes(utf8.encode(payload));
    return _bytesToHex(encrypted.bytes).toUpperCase();
  }

  // ===== eapi 解密 =====

  /// eapi 響應解密
  ///
  /// [hexEncrypted] hex 編碼的加密數據
  /// 返回解密後的 JSON 對象。
  static Map<String, dynamic> eapiDecrypt(String hexEncrypted) {
    final bytes = _hexToBytes(hexEncrypted);
    final key = Key.fromUtf8(_eapiKey);
    final encrypter = Encrypter(AES(key, mode: AESMode.ecb, padding: 'PKCS7'));
    final decrypted = encrypter.decryptBytes(Encrypted(bytes));
    return jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
  }

  // ===== 內部方法 =====

  /// AES-128-CBC 加密，返回 base64 字串
  static String _aesCbcEncrypt(String text, String keyStr, String ivStr) {
    final key = Key.fromUtf8(keyStr);
    final iv = IV.fromUtf8(ivStr);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
    return encrypter.encrypt(text, iv: iv).base64;
  }

  /// 生成隨機 base62 密鑰
  static String _generateRandomKey(int length) {
    final random = Random.secure();
    return List.generate(
      length,
      (_) => _base62[random.nextInt(_base62.length)],
    ).join();
  }

  /// RSA 加密（無 padding，原始模冪運算）
  ///
  /// 1. 反轉密鑰字串
  /// 2. 轉換為 BigInt
  /// 3. 模冪運算: input ^ e mod n
  /// 4. 輸出為 256 位 hex（左填充 0）
  static String _rsaEncrypt(String text) {
    final reversed = text.split('').reversed.join();
    final bytes = utf8.encode(reversed);
    final input = BigInt.parse(_bytesToHex(bytes), radix: 16);
    final output = input.modPow(_rsaExponent, _rsaModulus);
    return output.toRadixString(16).padLeft(256, '0');
  }

  /// 字節數組轉 hex 字串
  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// hex 字串轉字節數組
  static Uint8List _hexToBytes(String hex) {
    return Uint8List.fromList(
      List.generate(
        hex.length ~/ 2,
        (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }
}
