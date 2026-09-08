import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:fmp/providers/account/source_auth_context_provider.dart';
import 'package:fmp/providers/database/database_provider.dart';

final streamResolutionServiceProvider = Provider<StreamResolutionService>((
  ref,
) {
  final db = ref.watch(databaseProvider).requireValue;

  final service = DefaultStreamResolutionService(
    trackRepository: TrackRepository(db),
    settingsRepository: SettingsRepository(db),
    sourceManager: ref.watch(sourceManagerProvider),
    sourceAuthContext: ref.watch(sourceAuthContextProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
