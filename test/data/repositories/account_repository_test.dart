import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:isar_community/isar.dart';

import '../../support/isar_test_harness.dart';

void main() {
  late Isar isar;
  late Directory tempDir;
  late AccountRepository repository;

  setUpAll(initializeIsarForTests);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('account_repository_test_');
    isar = await Isar.open([AccountSchema],
        directory: tempDir.path, name: 'account_repository_test');
    repository = AccountRepository(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('upsert creates a row for a platform that has none', () async {
    await repository.upsert(SourceType.bilibili,
        isLoggedIn: true, userId: 'u1', userName: 'name');

    final account = await repository.getByPlatform(SourceType.bilibili);
    expect(account, isNotNull);
    expect(account!.isLoggedIn, isTrue);
    expect(account.userId, 'u1');
    expect(account.userName, 'name');
    expect(account.lastRefreshed, isNotNull);
  });

  test('upsert leaves fields it is not given alone', () async {
    await repository.upsert(SourceType.netease,
        isLoggedIn: true, userId: 'u1', userName: 'first', isVip: true);
    await repository.upsert(SourceType.netease, userName: 'second');

    final account = await repository.getByPlatform(SourceType.netease);
    expect(account!.userName, 'second');
    expect(account.userId, 'u1', reason: 'omitted fields must be preserved');
    expect(account.isVip, isTrue);
    expect(account.isLoggedIn, isTrue);
    expect(await isar.accounts.count(), 1, reason: 'upsert must not insert');
  });

  test('platforms do not see each other', () async {
    await repository.upsert(SourceType.bilibili, userId: 'b');
    await repository.upsert(SourceType.youtube, userId: 'y');

    expect((await repository.getByPlatform(SourceType.bilibili))!.userId, 'b');
    expect((await repository.getByPlatform(SourceType.youtube))!.userId, 'y');
    expect(await repository.getByPlatform(SourceType.netease), isNull);
    expect((await repository.getAll()).length, 2);
  });

  test('getByPlatformSync matches the async read', () async {
    await repository.upsert(SourceType.youtube, userId: 'y');
    expect(repository.getByPlatformSync(SourceType.youtube)!.userId, 'y');
    expect(repository.getByPlatformSync(SourceType.netease), isNull);
  });

  test('replaceForPlatform overwrites, and null deletes', () async {
    await repository.upsert(SourceType.netease,
        userId: 'old', userName: 'old', isVip: true);

    await repository.replaceForPlatform(
      SourceType.netease,
      Account()
        ..platform = SourceType.netease
        ..userId = 'new',
    );
    final replaced = await repository.getByPlatform(SourceType.netease);
    expect(replaced!.userId, 'new');
    expect(replaced.isVip, isFalse, reason: 'replace is not a merge');

    await repository.replaceForPlatform(SourceType.netease, null);
    expect(await repository.getByPlatform(SourceType.netease), isNull);
  });

  test('watchByPlatform emits the current row and then every change', () async {
    final seen = <String?>[];
    final subscription = repository
        .watchByPlatform(SourceType.bilibili)
        .listen((account) => seen.add(account?.userId));

    await repository.upsert(SourceType.bilibili, userId: 'first');
    await repository.upsert(SourceType.bilibili, userId: 'second');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await subscription.cancel();

    expect(seen.first, isNull, reason: 'fireImmediately with no row yet');
    expect(seen.last, 'second');
  });
}
