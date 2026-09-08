import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/providers/database/database_provider.dart';
import 'package:fmp/providers/account/account_provider.dart';

final sourceAuthContextProvider = Provider<SourceAuthContext>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return DefaultSourceAuthContext.fromRepositories(
    settingsRepository: SettingsRepository(db),
    accountAuthLoader: AccountServiceAuthLoader(
      bilibiliAccountService: ref.read(bilibiliAccountServiceProvider),
      youtubeAccountService: ref.read(youtubeAccountServiceProvider),
      neteaseAccountService: ref.read(neteaseAccountServiceProvider),
    ),
  );
});
