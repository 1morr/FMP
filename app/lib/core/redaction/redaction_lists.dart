import 'package:flutter/foundation.dart';

// 遮蔽名單（ADR 0011 §決定 3）。全 App 只有這一份；音源插件以
// `Redactor.addRules` 追加自己的名單，不另寫遮蔽邏輯。
//
// 名稱比對一律不分大小寫。鍵名採「以名稱結尾」：`token` 也涵蓋 `access_token`、
// `x-csrf-token`，寧可多遮也不漏。舊專案 `lib/core/logger.dart` 的名單是起點；
// 媒體 CDN 的部分是它缺的（docs/audit/accounts-network.md §4.1）。

/// 值整段換成 `***` 的 header。文字裡的 `Name: 值`、`Name=值` 與結構化欄位裡以
/// 它為鍵的值都算。
const builtInHeaderNames = <String>[
  'Authorization',
  'Proxy-Authorization',
  'Cookie',
  'Set-Cookie',
  'X-Api-Key',
];

/// 值換成 `***` 的鍵名：query、body、cookie 內的 `鍵=值`／`"鍵": "值"`，以及
/// 結構化欄位裡以它結尾的鍵。
const builtInKeyNames = <String>[
  // Bilibili
  'SESSDATA',
  'bili_jct',
  'DedeUserID',
  'DedeUserID__ckMd5',
  'access_key',
  // bili_jct 的值在寫入請求裡以裸 `csrf` 參數送出；`csrf` 也涵蓋網易的 `__csrf`。
  'csrf',
  // 網易雲音樂
  'MUSIC_U',
  'musicU',
  'eparams',
  // YouTube（Google 帳號 cookie）
  'SAPISID',
  'APISID',
  'SID',
  'HSID',
  'SSID',
  '__Secure-1PSID',
  '__Secure-3PSID',
  '__Secure-1PAPISID',
  '__Secure-3PAPISID',
  '__Secure-1PSIDTS',
  '__Secure-3PSIDTS',
  'LOGIN_INFO',
  // 通用
  'token',
  'apiKey',
  'api_key',
  'password',
];

/// 已知媒體 CDN：串流網址裡的簽名、使用者 IP 與 id，以及（YouTube 的）到期時間。
const builtInMediaCdns = <MediaCdn>[
  // Bilibili upos；`e` 是編碼過的簽名內容，`mid` 是使用者 id、`oi` 由 IP 算出，
  // `buvid` 是請求帶的裝置 id，`hdnts` 是 Akamai 鏡像的 token（`exp=…~hmac=…`）。
  // `deadline`（到期的 unix 秒）不遮：它是公開的時間戳、不是憑證，網址少了
  // `upsig` 照樣不能用；fixture 留著它，契約檢查才核對得了 `expiresAt`
  // （`checks.json` 的 `expiresAtPattern`，design §10）。
  MediaCdn(host: 'bilivideo.com', signedQueryParameters: _bilibiliSigned),
  MediaCdn(host: 'bilivideo.cn', signedQueryParameters: _bilibiliSigned),
  MediaCdn(host: 'akamaized.net', signedQueryParameters: _bilibiliSigned),
  MediaCdn(host: 'szbdyd.com', signedQueryParameters: _bilibiliSigned),
  // YouTube
  MediaCdn(
    host: 'googlevideo.com',
    signedQueryParameters: {
      'sig',
      'lsig',
      'signature',
      'sparams',
      'lsparams',
      'expire',
      'ip',
      'ipbits',
      'ei',
      'pot',
      'n',
    },
  ),
  // 網易雲音樂：路徑前兩段是到期時間與簽章。
  MediaCdn(
    host: 'music.126.net',
    signedQueryParameters: {'authSecret', 'vuutv'},
    signedPath: true,
  ),
];

const _bilibiliSigned = {
  'e',
  'upsig',
  'uparams',
  'trid',
  'mid',
  'oi',
  'buvid',
  'hdnts',
};

/// 一個媒體 CDN 的遮蔽規則。一個網址符合多條規則（內建與插件追加的）時，
/// `Redactor` 全部合併套用。
@immutable
final class MediaCdn {
  const MediaCdn({
    required this.host,
    this.signedQueryParameters = const {},
    this.signedPath = false,
  });

  /// 主機名稱；它本身與它的子網域都適用。
  final String host;

  /// 從 query 去除的參數名稱（大小寫視為相同）。
  final Set<String> signedQueryParameters;

  /// 路徑本身帶簽章：除了最後一段（檔名）之外的路徑段都換成 `***`。
  final bool signedPath;

  /// [candidate] 是否為 [host] 或它的子網域。
  bool matches(String candidate) {
    final lower = candidate.toLowerCase();
    final own = host.toLowerCase();
    return lower == own || lower.endsWith('.$own');
  }
}
