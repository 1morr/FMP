import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/repositories.dart';
import 'database_provider.dart';

/// Track Repository Provider
final trackRepositoryProvider = Provider<TrackRepository>((ref) {
  final db = ref.watch(databaseProvider).valueOrNull;
  if (db == null) {
    throw StateError('Database not initialized');
  }
  return TrackRepository(db);
});

/// Playlist Repository Provider
final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  final db = ref.watch(databaseProvider).valueOrNull;
  if (db == null) {
    throw StateError('Database not initialized');
  }
  return PlaylistRepository(db);
});

/// Queue Repository Provider
final queueRepositoryProvider = Provider<QueueRepository>((ref) {
  final db = ref.watch(databaseProvider).valueOrNull;
  if (db == null) {
    throw StateError('Database not initialized');
  }
  return QueueRepository(db);
});

/// Settings Repository Provider
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final db = ref.watch(databaseProvider).valueOrNull;
  if (db == null) {
    throw StateError('Database not initialized');
  }
  return SettingsRepository(db);
});

/// Play History Repository Provider
final playHistoryRepositoryProvider = Provider<PlayHistoryRepository>((ref) {
  final db = ref.watch(databaseProvider).valueOrNull;
  if (db == null) {
    throw StateError('Database not initialized');
  }
  return PlayHistoryRepository(db);
});
