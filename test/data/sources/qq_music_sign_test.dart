import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/sources/playlist_import/qq_music_sign.dart';

/// QQ 音樂歌單 API 的 `sign` 是伺服器驗的，簽錯不會拋錯，只會拿到一個看起來
/// 像「歌單不存在」的回應 —— 也就是說改壞了不會有任何測試以外的訊號。
///
/// 這些向量是從**改寫前**的實作抓下來的。當時的改寫只換表達方式、不換演算法
/// （原本是某個社群實作的逐行移植），所以輸出必須逐字元不變 —— 這些向量是唯一
/// 能證明那件事的東西。
void main() {
  group('QQMusicSign.encrypt', () {
    // 每一組都是 (輸入, 改寫前的輸出)。
    const vectors = <String, String>{
      '': 'zzb98ffe087addcnuyjec90xpfdilcqea80d149dc',
      'a': 'zzb970739762owlqnsfwosh2e5pthozwc11cc9b9',
      '{"comm":{"ct":24,"cv":0}}': 'zzbe3ec2451lbno2x2gzjlayyirqeaf4e38fbc',
      '周杰倫 - 稻香': 'zzb2c76ce2f83icstqkgo5tlxx9ty0v9a47557e03',
      'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
              'abcdefghijklmnopqrstuvwxyz0123456789':
          'zzb94f0c76fbloat0x4itvdhievs0nuw5b790b07',
      '{"req_1":{"module":"music.srfDissInfo.aiDissInfo","method":'
              '"uniform_get_Dissinfo","param":{"disstid":7364061065,'
              '"onlysong":0,"tag":1,"userinfo":1,"song_begin":0,'
              '"song_num":15}}}':
          'zzb023c8da8rzx7vpafbd0bjc413yuiiw56113af1',
    };

    vectors.forEach((input, expected) {
      final label = input.isEmpty
          ? '(empty)'
          : (input.length > 32 ? '${input.substring(0, 32)}…' : input);
      test('signs $label unchanged', () {
        expect(QQMusicSign.encrypt(input), expected);
      });
    });

    test('is stable across calls', () {
      const param = '{"comm":{"ct":24,"cv":0}}';
      expect(QQMusicSign.encrypt(param), QQMusicSign.encrypt(param));
    });

    test('always carries the zzb prefix and is lower case', () {
      for (final input in vectors.keys) {
        final signature = QQMusicSign.encrypt(input);
        expect(signature, startsWith('zzb'));
        expect(signature, equals(signature.toLowerCase()));
      }
    });

    test('drops the base64 characters the server does not accept', () {
      // 中段是 16 個位元組的 base64，`+` / `/` 與補位符都要濾掉，所以簽名
      // 長度會隨輸入浮動 —— 這正是不能用固定長度斷言的原因。
      for (final input in vectors.keys) {
        expect(QQMusicSign.encrypt(input), isNot(contains('+')));
        expect(QQMusicSign.encrypt(input), isNot(contains('/')));
        expect(QQMusicSign.encrypt(input), isNot(contains('=')));
      }
    });
  });
}
