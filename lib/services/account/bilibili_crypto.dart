import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Bilibili Cookie 刷新所需的 RSA-OAEP 加密工具
class BilibiliCrypto {
  static RSAPublicKey? _cachedPublicKey;

  /// 生成 correspondPath
  ///
  /// 使用 RSA-OAEP (SHA-256) 加密 "refresh_{timestamp}" 並返回 hex 編碼結果。
  /// [timestamp] 為當前毫秒時間戳。
  static String generateCorrespondPath(int timestamp) {
    final plaintext = 'refresh_$timestamp';
    final publicKey = _cachedPublicKey ??= _parsePublicKey();

    final encryptor = OAEPEncoding.withSHA256(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

    final input = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = encryptor.process(input);

    return encrypted.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 從 base64 DER 編碼的 SubjectPublicKeyInfo 中解析 RSA 公鑰
  static RSAPublicKey _parsePublicKey() {
    const base64Key =
        'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDLgd2OAkcGVtoE3ThUREbio0Eg'
        'Uc/prcajMKXvkCKFCWhJYJcLkcM2DKKcSeFpD/j6Boy538YXnR6VhcuUJOhH2x71'
        'nzPjfdTcqMz7djHum0qSZA0AyCBDABUqCrfNgCiJ00Ra7GmRj+YCK1NJEuewlb40'
        'JNrRuoEUXpabUzGB8QIDAQAB';

    final bytes = base64Decode(base64Key);
    var offset = 0;

    // 外層 SEQUENCE (SubjectPublicKeyInfo)
    offset = _skipTag(bytes, offset, 0x30);

    // AlgorithmIdentifier SEQUENCE — 跳過
    final algLen = _readTagLength(bytes, offset, 0x30);
    offset = algLen.contentOffset + algLen.length;

    // BIT STRING (subjectPublicKey)
    offset = _skipTag(bytes, offset, 0x03);
    offset++; // 跳過 unused bits byte (0x00)

    // 內層 SEQUENCE (RSAPublicKey PKCS#1)
    offset = _skipTag(bytes, offset, 0x30);

    // modulus INTEGER
    final modResult = _readInteger(bytes, offset);
    offset = modResult.nextOffset;

    // exponent INTEGER
    final expResult = _readInteger(bytes, offset);

    return RSAPublicKey(modResult.value, expResult.value);
  }

  // ===== DER 解析輔助方法 =====

  /// 跳過 tag byte 並讀取 length，返回 content 起始 offset
  static int _skipTag(Uint8List bytes, int offset, int expectedTag) {
    if (offset >= bytes.length) {
      throw FormatException('Unexpected end of DER data at offset $offset');
    }
    if (bytes[offset] != expectedTag) {
      throw FormatException(
          'Expected tag 0x${expectedTag.toRadixString(16)} at offset $offset, got 0x${bytes[offset].toRadixString(16)}');
    }
    offset++;
    if (offset >= bytes.length) {
      throw FormatException('Unexpected end of DER data after tag at offset $offset');
    }
    // 讀取 length
    if (bytes[offset] & 0x80 != 0) {
      final numLenBytes = bytes[offset] & 0x7f;
      if (numLenBytes > 4) {
        throw FormatException('DER length too large: $numLenBytes bytes');
      }
      if (offset + 1 + numLenBytes > bytes.length) {
        throw FormatException('DER length bytes exceed data size at offset $offset');
      }
      offset += 1 + numLenBytes;
    } else {
      offset++;
    }
    return offset;
  }

  /// 讀取 tag + length，返回 content offset 和 length
  static ({int contentOffset, int length}) _readTagLength(
      Uint8List bytes, int offset, int expectedTag) {
    if (offset >= bytes.length) {
      throw FormatException('Unexpected end of DER data at offset $offset');
    }
    if (bytes[offset] != expectedTag) {
      throw FormatException(
          'Expected tag 0x${expectedTag.toRadixString(16)} at offset $offset');
    }
    offset++;
    if (offset >= bytes.length) {
      throw FormatException('Unexpected end of DER data after tag at offset $offset');
    }
    int length;
    if (bytes[offset] & 0x80 != 0) {
      final numLenBytes = bytes[offset] & 0x7f;
      if (numLenBytes > 4) {
        throw FormatException('DER length too large: $numLenBytes bytes');
      }
      offset++;
      if (offset + numLenBytes > bytes.length) {
        throw FormatException('DER length bytes exceed data size at offset $offset');
      }
      length = 0;
      for (var i = 0; i < numLenBytes; i++) {
        length = (length << 8) | bytes[offset++];
      }
    } else {
      length = bytes[offset++];
    }
    if (length > bytes.length - offset) {
      throw FormatException('DER content length $length exceeds remaining data at offset $offset');
    }
    return (contentOffset: offset, length: length);
  }

  /// 讀取 DER INTEGER，返回 BigInt 值和下一個元素的 offset
  static ({BigInt value, int nextOffset}) _readInteger(
      Uint8List bytes, int offset) {
    final result = _readTagLength(bytes, offset, 0x02);
    final valueBytes =
        bytes.sublist(result.contentOffset, result.contentOffset + result.length);

    var value = BigInt.zero;
    for (final byte in valueBytes) {
      value = (value << 8) | BigInt.from(byte);
    }

    return (value: value, nextOffset: result.contentOffset + result.length);
  }
}
