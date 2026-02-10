import 'dart:convert';
import 'package:crypto/crypto.dart';

/// QQ音乐签名算法
class QQMusicSign {
  static const _l1 = [
    212, 45, 80, 68, 195, 163, 163, 203,
    157, 220, 254, 91, 204, 79, 104, 6
  ];

  static const _t =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';

  static const _k1 = {
    '0': 0, '1': 1, '2': 2, '3': 3, '4': 4,
    '5': 5, '6': 6, '7': 7, '8': 8, '9': 9,
    'A': 10, 'B': 11, 'C': 12, 'D': 13, 'E': 14, 'F': 15,
  };

  /// 生成签名
  static String encrypt(String param) {
    // 1. 计算 MD5
    final md5Hash = md5.convert(utf8.encode(param));
    final md5Str = md5Hash.toString().toUpperCase();

    // 2. 提取特定位置字符
    final t1 = _selectChars(md5Str, [21, 4, 9, 26, 16, 20, 27, 30]);
    final t3 = _selectChars(md5Str, [18, 11, 3, 2, 1, 7, 6, 25]);

    // 3. XOR 运算
    final ls2 = <int>[];
    for (var i = 0; i < 16; i++) {
      final x1 = _k1[md5Str[i * 2]]!;
      final x2 = _k1[md5Str[i * 2 + 1]]!;
      final x3 = (x1 * 16 ^ x2) ^ _l1[i];
      ls2.add(x3);
    }

    // 4. Base64 变换
    final ls3 = <String>[];
    for (var i = 0; i < 6; i++) {
      if (i == 5) {
        ls3.add(
          '${_t[ls2[ls2.length - 1] >> 2]}${_t[(ls2[ls2.length - 1] & 3) << 4]}',
        );
      } else {
        final x4 = ls2[i * 3] >> 2;
        final x5 = (ls2[i * 3 + 1] >> 4) ^ ((ls2[i * 3] & 3) << 4);
        final x6 = (ls2[i * 3 + 2] >> 6) ^ ((ls2[i * 3 + 1] & 15) << 2);
        final x7 = 63 & ls2[i * 3 + 2];
        ls3.add('${_t[x4]}${_t[x5]}${_t[x6]}${_t[x7]}');
      }
    }

    final t2 = ls3.join('').replaceAll(RegExp(r'[\\/+]'), '');
    return 'zzb${(t1 + t2 + t3).toLowerCase()}';
  }

  static String _selectChars(String str, List<int> indices) {
    return indices.map((i) => str[i]).join('');
  }
}
