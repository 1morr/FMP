import 'dart:convert';

import 'package:fmp/legacy_import/legacy_account_converter.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';

// 合成的舊憑證 JSON（舊 `*Credentials.toJson` 的形狀）。值全是明顯的假值。

String legacyBilibiliJson({
  String sessdata = 'FAKE_SESSDATA_123',
  String biliJct = 'FAKE_JCT_4567',
  String dedeUserId = '555',
  String dedeUserIdCkMd5 = 'FAKE_CKMD5_89',
  String refreshToken = 'FAKE_REFRESH_TOKEN',
}) => jsonEncode({
  'sessdata': sessdata,
  'biliJct': biliJct,
  'dedeUserId': dedeUserId,
  'dedeUserIdCkMd5': dedeUserIdCkMd5,
  'refreshToken': refreshToken,
  'savedAt': '2025-03-14T15:09:26.000',
});

String legacyNeteaseJson({
  String musicU = 'FAKE_MUSIC_U_123',
  String csrf = 'FAKE_CSRF_4567',
  String? userId = '777',
}) => jsonEncode({
  'musicU': musicU,
  'csrf': csrf,
  'userId': userId,
  'savedAt': '2025-03-14T15:09:26.000',
});

String legacyYoutubeJson({
  String sid = 'FAKE_SID_123',
  String hsid = 'FAKE_HSID_123',
  String ssid = 'FAKE_SSID_123',
  String apisid = 'FAKE_APISID_123',
  String sapisid = 'FAKE_SAPISID_123',
  String secure1Psid = 'FAKE_1PSID_123',
  String secure3Psid = 'FAKE_3PSID_123',
  String secure1Papisid = 'FAKE_1PAPISID_123',
  String secure3Papisid = 'FAKE_3PAPISID_123',
  String loginInfo = 'FAKE_LOGIN_INFO_123',
  String? datasyncId = 'FAKE_DATASYNC_123',
}) => jsonEncode({
  'sid': sid,
  'hsid': hsid,
  'ssid': ssid,
  'apisid': apisid,
  'sapisid': sapisid,
  'secure1Psid': secure1Psid,
  'secure3Psid': secure3Psid,
  'secure1Papisid': secure1Papisid,
  'secure3Papisid': secure3Papisid,
  'loginInfo': loginInfo,
  'datasyncId': datasyncId,
  'savedAt': '2025-03-14T15:09:26.000',
});

/// 讀取器的結果：以 [legacyCredentialKeys] 的鍵索引。
Map<String, LegacyCredentialRead> legacyReads({
  String? bilibili,
  String? youtube,
  String? netease,
}) => {
  legacyCredentialKeys['bilibili']!: bilibili == null
      ? const LegacyCredentialMissing()
      : LegacyCredentialFound(bilibili),
  legacyCredentialKeys['youtube']!: youtube == null
      ? const LegacyCredentialMissing()
      : LegacyCredentialFound(youtube),
  legacyCredentialKeys['netease']!: netease == null
      ? const LegacyCredentialMissing()
      : LegacyCredentialFound(netease),
};
