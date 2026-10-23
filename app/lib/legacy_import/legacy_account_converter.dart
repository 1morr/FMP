import 'dart:convert';

import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';
import 'package:fmp/legacy_import/legacy_source_ids.dart';
import 'package:fmp/legacy_import/legacy_track_catalog.dart';
import 'package:fmp/legacy_import/skip_reason.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';

/// 舊版 secure storage 裡三個帳號憑證的鍵（M5 design §4.3）。字面值只寫在這裡，傳給
/// `LegacyCredentialReader`。`lyrics_ai_api_key` 留給 M7，M5 不讀。
const legacyCredentialKeys = {
  legacyBilibili: 'account_bilibili_credentials',
  legacyYoutube: 'account_youtube_credentials',
  legacyNetease: 'account_netease_credentials',
};

/// 帳號與憑證的轉換結果（M5 design §5.8）。
///
/// [accounts] 與 [credentials] 成對：同一個插件 id 一定兩邊都有。憑證只在記憶體，不進
/// 匯入包，由呼叫端換上資料庫之後以 `CredentialStore.writeImported` 寫入。
final class ConvertedAccounts {
  const ConvertedAccounts({
    required this.accounts,
    required this.credentials,
    required this.reloginPlatforms,
  });

  final List<Account> accounts;

  /// 插件 id → 憑證。
  final Map<String, LoginCredentials> credentials;

  /// 要使用者重新登入的平台（插件 id）：憑證讀不出、缺必要 cookie、找不到使用者 id，或舊帳號列
  /// 是登入狀態但憑證不見了。
  final List<String> reloginPlatforms;
}

/// 一個平台的舊憑證 JSON → 新形狀。
class _Shape {
  const _Shape({
    required this.cookies,
    required this.requiredCookies,
    this.extra = const {},
    this.userIdField,
  });

  /// 舊欄位 → 新 cookie 名稱（名稱已對照官方插件的登入程式碼，PR 4）。
  final Map<String, String> cookies;
  final Set<String> requiredCookies;

  /// 舊欄位 → `extra` 的鍵。
  final Map<String, String> extra;

  /// 舊帳號列沒有 `userId` 時，從憑證 JSON 的這個欄位取。
  final String? userIdField;
}

const _shapes = {
  // bilibili/src/plugin.js 的 CREDENTIAL_COOKIES、REQUIRED_COOKIES 與 extra.refresh_token。
  legacyBilibili: _Shape(
    cookies: {
      'sessdata': 'SESSDATA',
      'biliJct': 'bili_jct',
      'dedeUserId': 'DedeUserID',
      'dedeUserIdCkMd5': 'DedeUserID__ckMd5',
    },
    requiredCookies: {'SESSDATA', 'bili_jct', 'DedeUserID'},
    extra: {'refreshToken': 'refresh_token'},
    userIdField: 'dedeUserId',
  ),
  // youtube/src/login.js 的 REQUIRED_COOKIES。
  legacyYoutube: _Shape(
    cookies: {
      'sid': 'SID',
      'hsid': 'HSID',
      'ssid': 'SSID',
      'apisid': 'APISID',
      'sapisid': 'SAPISID',
      'secure1Psid': '__Secure-1PSID',
      'secure3Psid': '__Secure-3PSID',
      'secure1Papisid': '__Secure-1PAPISID',
      'secure3Papisid': '__Secure-3PAPISID',
      'loginInfo': 'LOGIN_INFO',
    },
    requiredCookies: {'SAPISID', '__Secure-1PSID', '__Secure-3PSID'},
    userIdField: 'datasyncId',
  ),
  // netease/src/login.js：MUSIC_U 必要、__csrf 有就放。
  legacyNetease: _Shape(
    cookies: {'musicU': 'MUSIC_U', 'csrf': '__csrf'},
    requiredCookies: {'MUSIC_U'},
    userIdField: 'userId',
  ),
};

/// 平台的處理順序（也是 [ConvertedAccounts.reloginPlatforms] 的順序）。
const _platforms = [legacyBilibili, legacyYoutube, legacyNetease];

/// 舊帳號列＋讀取器的結果 → 新帳號列與憑證（M5 design §5.8）。純函數，沒有 I/O。
///
/// [reads] 以 [legacyCredentialKeys] 的鍵索引。[tally]（`accounts`）計「憑證可用的平台」：
/// 讀到 = 寫入 + 略過（找不到使用者 id）。舊版沒有憑證（沒登入過、登出過、工作階段過期後
/// 憑證已刪）的平台什麼都不記，除非舊帳號列仍是 `isLoggedIn`（憑證不見了）；那種與讀不出、
/// 缺必要 cookie 的一樣只進 [ConvertedAccounts.reloginPlatforms]。
ConvertedAccounts convertAccounts({
  required List<LegacyAccount> rows,
  required Map<String, LegacyCredentialRead> reads,
  required DateTime now,
  required Tally tally,
}) {
  final accounts = <Account>[];
  final credentials = <String, LoginCredentials>{};
  final relogin = <String>[];
  for (final platform in _platforms) {
    final row = rows.where((r) => r.platform == platform).firstOrNull;
    final read = reads[legacyCredentialKeys[platform]];
    final String raw;
    switch (read) {
      case null || LegacyCredentialMissing():
        // 舊帳號列說還登入著、憑證卻不見了：不提的話使用者會不知不覺變成未登入。
        if (row?.isLoggedIn ?? false) relogin.add(platform);
        continue;
      case LegacyCredentialUnreadable():
        relogin.add(platform);
        continue;
      case LegacyCredentialFound(:final value):
        raw = value;
    }
    final parsed = _parse(_shapes[platform]!, raw);
    if (parsed == null) {
      relogin.add(platform);
      continue;
    }
    tally.read++;
    final userId = blankToNull(row?.userId) ?? parsed.userId;
    if (userId == null) {
      tally.skip(SkipReason.accountWithoutId);
      // 帳號列沒有 id，憑證單獨留著會在下次載入時被對齊刪掉：同樣要重新登入。
      relogin.add(platform);
      continue;
    }
    tally.written++;
    accounts.add(
      Account(
        pluginId: platform,
        userId: userId,
        displayName: blankToNull(row?.userName) ?? userId,
        avatarJson: TracksRepository.encodeArtwork(
          artworkOf(blankToNull(row?.avatarUrl)),
        ),
        status: AccountStatus.active,
        loggedInAt: (row?.loginAt ?? now).toUtc(),
        lastRefreshAt: row?.lastRefreshed?.toUtc(),
      ),
    );
    credentials[platform] = parsed.credentials;
  }
  return ConvertedAccounts(
    accounts: accounts,
    credentials: credentials,
    reloginPlatforms: relogin,
  );
}

({LoginCredentials credentials, String? userId})? _parse(
  _Shape shape,
  String raw,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final json = decoded;
  String? field(String name) {
    final value = json[name];
    return value is String && value.isNotEmpty ? value : null;
  }

  final cookies = {
    for (final MapEntry(:key, :value) in shape.cookies.entries)
      if (field(key) case final String text) value: text,
  };
  if (!cookies.keys.toSet().containsAll(shape.requiredCookies)) return null;
  final extra = {
    for (final MapEntry(:key, :value) in shape.extra.entries)
      if (field(key) case final String text) value: text,
  };
  final idField = shape.userIdField;
  return (
    credentials: LoginCredentials(cookies: cookies, extra: extra),
    userId: idField == null ? null : blankToNull(field(idField)),
  );
}
