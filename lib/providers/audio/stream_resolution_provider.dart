import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/source_provider.dart';
import '../../services/audio/stream_resolution_service.dart';
import '../account/source_auth_context_provider.dart';
import '../database/database_provider.dart';

final streamResolutionServiceProvider =
    Provider<StreamResolutionService>((ref) {
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
