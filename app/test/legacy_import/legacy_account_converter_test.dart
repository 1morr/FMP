import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/legacy_import/legacy_account_converter.dart';
import 'package:fmp/legacy_import/legacy_converter.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';
import 'package:fmp/legacy_import/skip_reason.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';

import 'legacy_credential_fixtures.dart';
import 'legacy_snapshot_builders.dart';

// 帳號與憑證的轉換（M5 design §5.8、§9）：純 Dart，假憑證進、帳號列與憑證出。

final _now = DateTime.utc(2026, 10, 23, 12);

LegacyConversion convertWith(
  Map<String, LegacyCredentialRead> reads, {
  List<LegacyAccount> accounts = const [],
  LegacySnapshot? snapshot,
}) => const LegacyConverter().convert(
  snapshot ?? legacySnapshot(accounts: accounts),
  source: LegacyImportSource.database,
  now: _now,
  credentials: reads,
);

void main() {
  group('cookie names (checked against the official plugins)', () {
    test('bilibili: four cookies and the refresh token in extra', () {
      final result = convertWith(
        legacyReads(bilibili: legacyBilibiliJson()),
        accounts: [legacyAccount(platform: 'bilibili', userId: '555')],
      );
      expect(
        result.credentials['bilibili'],
        const LoginCredentials(
          cookies: {
            'SESSDATA': 'FAKE_SESSDATA_123',
            'bili_jct': 'FAKE_JCT_4567',
            'DedeUserID': '555',
            'DedeUserID__ckMd5': 'FAKE_CKMD5_89',
          },
          extra: {'refresh_token': 'FAKE_REFRESH_TOKEN'},
        ),
      );
    });

    test('netease: MUSIC_U and __csrf', () {
      final result = convertWith(legacyReads(netease: legacyNeteaseJson()));
      expect(
        result.credentials['netease'],
        const LoginCredentials(
          cookies: {'MUSIC_U': 'FAKE_MUSIC_U_123', '__csrf': 'FAKE_CSRF_4567'},
        ),
      );
    });

    test('youtube: ten cookies', () {
      final result = convertWith(legacyReads(youtube: legacyYoutubeJson()));
      expect(
        result.credentials['youtube'],
        const LoginCredentials(
          cookies: {
            'SID': 'FAKE_SID_123',
            'HSID': 'FAKE_HSID_123',
            'SSID': 'FAKE_SSID_123',
            'APISID': 'FAKE_APISID_123',
            'SAPISID': 'FAKE_SAPISID_123',
            '__Secure-1PSID': 'FAKE_1PSID_123',
            '__Secure-3PSID': 'FAKE_3PSID_123',
            '__Secure-1PAPISID': 'FAKE_1PAPISID_123',
            '__Secure-3PAPISID': 'FAKE_3PAPISID_123',
            'LOGIN_INFO': 'FAKE_LOGIN_INFO_123',
          },
        ),
      );
    });

    test('empty strings are not written as cookies or extra', () {
      final result = convertWith(
        legacyReads(
          bilibili: legacyBilibiliJson(dedeUserIdCkMd5: '', refreshToken: ''),
          netease: legacyNeteaseJson(csrf: ''),
          youtube: legacyYoutubeJson(sid: '', loginInfo: ''),
        ),
      );
      final bilibili = result.credentials['bilibili']!;
      expect(bilibili.cookies.keys, {'SESSDATA', 'bili_jct', 'DedeUserID'});
      expect(bilibili.extra, isEmpty);
      expect(result.credentials['netease']!.cookies.keys, {'MUSIC_U'});
      final youtube = result.credentials['youtube']!.cookies.keys;
      expect(youtube, isNot(contains('SID')));
      expect(youtube, isNot(contains('LOGIN_INFO')));
      expect(youtube, contains('SAPISID'));
    });
  });

  group('accounts', () {
    test('rows are built from the old account row', () {
      final result = convertWith(
        legacyReads(bilibili: legacyBilibiliJson()),
        accounts: [
          legacyAccount(
            platform: 'bilibili',
            userId: '555',
            userName: 'Synthetic User',
            avatarUrl: 'https://example.test/face.jpg',
            loginAt: DateTime.utc(2025, 3, 1),
            lastRefreshed: DateTime.utc(2025, 3, 2),
          ),
        ],
      );
      expect(
        result.bundle.accounts.single,
        Account(
          pluginId: 'bilibili',
          userId: '555',
          displayName: 'Synthetic User',
          avatarJson: '[{"url":"https://example.test/face.jpg"}]',
          status: AccountStatus.active,
          loggedInAt: DateTime.utc(2025, 3, 1),
          lastRefreshAt: DateTime.utc(2025, 3, 2),
        ),
      );
      expect(result.bundle.record.summary.reloginPlatforms, isEmpty);
    });

    test('defaults: the user id as name, the import time as login time', () {
      final result = convertWith(
        legacyReads(netease: legacyNeteaseJson()),
        accounts: [legacyAccount(platform: 'netease', userId: '777')],
      );
      final account = result.bundle.accounts.single;
      expect(account.displayName, '777');
      expect(account.avatarJson, isNull);
      expect(account.loggedInAt, _now);
      expect(account.lastRefreshAt, isNull);
      expect(account.lastRefreshResult, isNull);
    });

    test('the user id falls back to the one inside the credentials', () {
      final result = convertWith(
        legacyReads(
          bilibili: legacyBilibiliJson(dedeUserId: '555'),
          netease: legacyNeteaseJson(userId: '777'),
          youtube: legacyYoutubeJson(datasyncId: 'FAKE_DATASYNC_123'),
        ),
        // 帳號列在，但 userId 是空的（舊版沒補上）。
        accounts: [legacyAccount(platform: 'bilibili', userId: '  ')],
      );
      expect(
        {for (final a in result.bundle.accounts) a.pluginId: a.userId},
        {'bilibili': '555', 'youtube': 'FAKE_DATASYNC_123', 'netease': '777'},
      );
    });

    test('the old row wins over the id inside the credentials', () {
      final result = convertWith(
        legacyReads(netease: legacyNeteaseJson(userId: '777')),
        accounts: [legacyAccount(platform: 'netease', userId: '888')],
      );
      expect(result.bundle.accounts.single.userId, '888');
    });

    test('no id anywhere: skipped, and the platform needs a new login', () {
      final result = convertWith(
        legacyReads(
          netease: legacyNeteaseJson(userId: null),
          youtube: legacyYoutubeJson(datasyncId: null),
        ),
      );
      expect(result.bundle.accounts, isEmpty);
      expect(result.credentials, isEmpty);
      expect(result.bundle.record.summary.reloginPlatforms, [
        'youtube',
        'netease',
      ]);
      final summary = result.bundle.record.summary.collections['accounts']!;
      expect(summary.read, 2);
      expect(summary.written, 0);
      expect(summary.skipped, {'accountWithoutId': 2});
    });

    test('credentials without an old account row are still imported', () {
      final result = convertWith(
        legacyReads(bilibili: legacyBilibiliJson(dedeUserId: '555')),
      );
      expect(result.bundle.accounts.single.userId, '555');
      expect(result.credentials.keys, ['bilibili']);
    });
  });

  group('unusable credentials need a new login', () {
    test('unreadable', () {
      final result = convertWith(
        {
          legacyCredentialKeys['bilibili']!: const LegacyCredentialUnreadable(),
          legacyCredentialKeys['netease']!: const LegacyCredentialMissing(),
        },
        accounts: [legacyAccount(platform: 'bilibili', userId: '555')],
      );
      expect(result.bundle.accounts, isEmpty);
      expect(result.credentials, isEmpty);
      expect(result.bundle.record.summary.reloginPlatforms, ['bilibili']);
    });

    test('a required cookie is missing or empty', () {
      for (final (platform, json) in [
        ('bilibili', legacyBilibiliJson(sessdata: '')),
        ('bilibili', legacyBilibiliJson(biliJct: '')),
        ('bilibili', legacyBilibiliJson(dedeUserId: '')),
        ('netease', legacyNeteaseJson(musicU: '')),
        ('youtube', legacyYoutubeJson(sapisid: '')),
        ('youtube', legacyYoutubeJson(secure1Psid: '')),
        ('youtube', legacyYoutubeJson(secure3Psid: '')),
      ]) {
        final result = convertWith(
          legacyReads(
            bilibili: platform == 'bilibili' ? json : null,
            netease: platform == 'netease' ? json : null,
            youtube: platform == 'youtube' ? json : null,
          ),
        );
        expect(result.bundle.accounts, isEmpty, reason: platform);
        expect(result.bundle.record.summary.reloginPlatforms, [
          platform,
        ], reason: platform);
      }
    });

    test('not JSON, not an object, or wrong field types', () {
      for (final text in [
        'not json',
        '[]',
        '"text"',
        jsonEncode({'musicU': 5}),
      ]) {
        final result = convertWith(legacyReads(netease: text));
        expect(result.bundle.accounts, isEmpty, reason: text);
        expect(result.bundle.record.summary.reloginPlatforms, [
          'netease',
        ], reason: text);
      }
    });

    test('logged in on the old app but the credentials are gone', () {
      final result = convertWith(
        legacyReads(),
        accounts: [
          legacyAccount(platform: 'netease', userId: '777'),
          legacyAccount(platform: 'bilibili', userId: '555'),
        ],
      );
      expect(result.bundle.accounts, isEmpty);
      expect(result.credentials, isEmpty);
      // 依平台順序（bilibili、youtube、netease），不是帳號列的順序。
      expect(result.bundle.record.summary.reloginPlatforms, [
        'bilibili',
        'netease',
      ]);
      final summary = result.bundle.record.summary.collections['accounts']!;
      expect((summary.read, summary.written), (0, 0));
    });

    test('a key absent from the reads counts as missing', () {
      final result = convertWith(
        const {},
        accounts: [legacyAccount(platform: 'youtube', userId: 'UC1')],
      );
      expect(result.bundle.record.summary.reloginPlatforms, ['youtube']);
    });

    test('logged out on the old app and no credentials: nothing', () {
      final result = convertWith(
        legacyReads(),
        accounts: [
          legacyAccount(platform: 'bilibili', userId: '555', isLoggedIn: false),
        ],
      );
      expect(result.bundle.accounts, isEmpty);
      expect(result.bundle.record.summary.reloginPlatforms, isEmpty);
    });

    test('not logged in on the old app: nothing to report', () {
      final result = convertWith(legacyReads());
      expect(result.bundle.accounts, isEmpty);
      expect(result.bundle.record.summary.reloginPlatforms, isEmpty);
      final summary = result.bundle.record.summary.collections['accounts']!;
      expect((summary.read, summary.written), (0, 0));
    });
  });

  group('playlist_remote.writable needs an imported account', () {
    LegacySnapshot snapshot({
      String? ownerUserId = '555',
      List<LegacyAccount> accounts = const [],
    }) => legacySnapshot(
      tracks: [legacyTrack(id: 1, sourceId: 'BVa')],
      accounts: accounts,
      playlists: [
        legacyPlaylist(
          id: 1,
          sourceUrl: 'https://space.bilibili.com/1/favlist?fid=4026748432',
          ownerUserId: ownerUserId,
          trackIds: [1],
        ),
      ],
    );

    bool? writable(
      Map<String, LegacyCredentialRead> reads, {
      String? ownerUserId = '555',
      List<LegacyAccount> accounts = const [],
    }) => convertWith(
      reads,
      snapshot: snapshot(ownerUserId: ownerUserId, accounts: accounts),
    ).bundle.playlists.single.remote?.writable;

    final account = legacyAccount(platform: 'bilibili', userId: '555');

    test('same user id as the imported account', () {
      expect(
        writable(
          legacyReads(bilibili: legacyBilibiliJson()),
          accounts: [account],
        ),
        isTrue,
      );
    });

    test('a different owner, or no owner', () {
      final reads = legacyReads(bilibili: legacyBilibiliJson());
      expect(writable(reads, ownerUserId: '999', accounts: [account]), isFalse);
      expect(writable(reads, ownerUserId: null, accounts: [account]), isFalse);
    });

    test('the old account row alone is not enough', () {
      expect(writable(legacyReads(), accounts: [account]), isFalse);
      expect(
        writable(
          {
            legacyCredentialKeys['bilibili']!:
                const LegacyCredentialUnreadable(),
          },
          accounts: [account],
        ),
        isFalse,
      );
      expect(
        writable(
          legacyReads(bilibili: legacyBilibiliJson(sessdata: '')),
          accounts: [account],
        ),
        isFalse,
      );
    });

    test('another platform\'s account does not count', () {
      expect(
        writable(
          legacyReads(netease: legacyNeteaseJson(userId: '555')),
          accounts: [legacyAccount(platform: 'netease', userId: '555')],
        ),
        isFalse,
      );
    });

    test('convert without credentials never marks a playlist writable', () {
      final bundle = const LegacyConverter()
          .convert(
            snapshot(accounts: [account]),
            source: LegacyImportSource.database,
            now: _now,
          )
          .bundle;
      expect(bundle.playlists.single.remote!.writable, isFalse);
      expect(bundle.accounts, isEmpty);
      expect(bundle.record.summary.reloginPlatforms, isEmpty);
      expect(bundle.record.summary.collections, isNot(contains('accounts')));
    });
  });

  group('secrets stay out of the summary', () {
    test('no credential value in the summary, bundle text or results', () {
      final result = convertWith(
        legacyReads(
          bilibili: legacyBilibiliJson(),
          netease: legacyNeteaseJson(musicU: ''),
          youtube: legacyYoutubeJson(),
        ),
        accounts: [legacyAccount(platform: 'bilibili', userId: '555')],
      );
      final text = [
        result.bundle.record.summary.encode(),
        result.bundle.accounts.toString(),
        result.credentials.toString(),
        result.bundle.accounts.map((a) => a.avatarJson).join(),
      ].join('\n');
      expect(text, isNot(contains('FAKE_')));
      expect(SkipReason.accountWithoutId.isSkip, isTrue);
    });
  });
}
