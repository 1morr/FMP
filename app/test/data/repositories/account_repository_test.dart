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
  });
}
