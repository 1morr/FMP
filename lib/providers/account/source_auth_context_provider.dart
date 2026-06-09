import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../services/account/source_auth_context.dart';
import '../database/database_provider.dart';
import 'account_provider.dart';

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
