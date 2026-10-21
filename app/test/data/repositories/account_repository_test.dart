import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/account.dart';

import '../../support/memory_database.dart';

Account account(
  String pluginId, {
  AccountStatus status = AccountStatus.active,
  String name = 'Someone',
}) => Account(
  pluginId: pluginId,
  userId: 'u-$pluginId',
  displayName: name,
  avatarJson: '[{"url":"https://a.test/a.png"}]',
  status: status,
  loggedInAt: DateTime.utc(2026, 10, 9, 8, 30, 15, 250),
  lastRefreshAt: DateTime.utc(2026, 10, 9, 9),
  lastRefreshResult: RefreshResult.unchanged,
);

void main() {
  group('AccountRepository', () {
    test('upserts, lists in plugin order and overwrites on re-login', () async {
      final repository = AccountRepository(memoryDatabase());

      await repository.upsert(account('b'));
      await repository.upsert(account('a'));
      await repository.upsert(account('a', name: 'Renamed'));

      expect(await repository.list(), [
        account('a', name: 'Renamed'),
        account('b'),
      ]);
    });

    test('keeps optional fields empty', () async {
      final repository = AccountRepository(memoryDatabase());
      final bare = Account(
        pluginId: 'a',
        userId: 'u',
        displayName: 'n',
        status: AccountStatus.invalidated,
        loggedInAt: DateTime.utc(2026),
      );

      await repository.upsert(bare);

      expect(await repository.list(), [bare]);
    });

    test('removes one account and ignores a missing one', () async {
      final repository = AccountRepository(memoryDatabase());
      await repository.upsert(account('a'));
      await repository.upsert(account('b'));

      await repository.remove('a');
      await repository.remove('missing');

      expect(await repository.list(), [account('b')]);
    });

    test(
      'stored format: enums are the fixed strings, times epoch ms',
      () async {
        final database = memoryDatabase();
        await AccountRepository(database).upsert(account('a'));

        final row = await database
            .customSelect('SELECT * FROM accounts')
            .getSingle();
        expect(row.data['status'], 'active');
        expect(row.data['last_refresh_result'], 'unchanged');
        expect(row.data['logged_in_at'], 1791534615250);
      },
    );
  });

  group('SourceSettingsRepository', () {
    test('has no value until one is set and can be cleared', () async {
      final repository = SourceSettingsRepository(memoryDatabase());
      expect(await repository.browseAsLoggedIn('a'), isNull);

      await repository.setBrowseAsLoggedIn('a', value: false);
      expect(await repository.browseAsLoggedIn('a'), isFalse);

      await repository.setBrowseAsLoggedIn('a', value: true);
      expect(await repository.browseAsLoggedIn('a'), isTrue);

      await repository.setBrowseAsLoggedIn('a', value: null);
      expect(await repository.browseAsLoggedIn('a'), isNull);
    });

    test('remove deletes only that plugin', () async {
      final repository = SourceSettingsRepository(memoryDatabase());
      await repository.setBrowseAsLoggedIn('a', value: false);
      await repository.setBrowseAsLoggedIn('b', value: false);

      await repository.remove('a');
      await repository.remove('missing');

      expect(await repository.browseAsLoggedIn('a'), isNull);
      expect(await repository.browseAsLoggedIn('b'), isFalse);
    });

    // 匹配目標（M4 design §8.3）：兩欄各自寫，彼此與 browse_as_logged_in 都不互相清掉。
    test('match target and rank are written on their own', () async {
      final repository = SourceSettingsRepository(memoryDatabase());
      await repository.setBrowseAsLoggedIn('a', value: true);
      expect(await repository.watchMatchTargets().first, const [
        MatchTargetSetting(pluginId: 'a'),
      ]);

      await repository.setMatchTarget('a', target: false);
      await repository.setMatchRanks(['b', 'a']);

      expect(await repository.watchMatchTargets().first, const [
        MatchTargetSetting(pluginId: 'a', target: false, rank: 1),
        MatchTargetSetting(pluginId: 'b', rank: 0),
      ]);
      expect(await repository.browseAsLoggedIn('a'), isTrue);

      await repository.setMatchTarget('a', target: true);
      await repository.setBrowseAsLoggedIn('a', value: null);
      expect(await repository.watchMatchTargets().first, const [
        MatchTargetSetting(pluginId: 'a', target: true, rank: 1),
        MatchTargetSetting(pluginId: 'b', rank: 0),
      ]);
    });

    test('the match columns are stored as 0/1 and the rank', () async {
      final database = memoryDatabase();
      final repository = SourceSettingsRepository(database);
      await repository.setMatchTarget('a', target: false);
      await repository.setMatchRanks(['a']);

      final row = await database
          .customSelect(
            'SELECT match_target, match_rank FROM source_settings '
            "WHERE plugin_id = 'a'",
          )
          .getSingle();
      expect(row.data, {'match_target': 0, 'match_rank': 0});
    });

    test('remove deletes the match columns with the row', () async {
      final repository = SourceSettingsRepository(memoryDatabase());
      await repository.setMatchTarget('a', target: false);
      await repository.setMatchRanks(['a', 'b']);

      await repository.remove('a');

      expect(await repository.watchMatchTargets().first, const [
        MatchTargetSetting(pluginId: 'b', rank: 1),
      ]);
    });
  });
}
