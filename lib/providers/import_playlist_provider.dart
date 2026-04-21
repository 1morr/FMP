import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_provider.dart';
import '../data/sources/source_provider.dart';
import '../services/import/import_service.dart';
import 'database_provider.dart';
import 'repository_providers.dart';

typedef ImportServiceFactory = FutureOr<ImportServiceFacade> Function();

class ImportPlaylistState {
  const ImportPlaylistState({
    this.isImporting = false,
    this.progress = const ImportProgress(),
    this.result,
    this.errorMessage,
    this.wasCancelled = false,
  });

  final bool isImporting;
  final ImportProgress progress;
  final ImportResult? result;
  final String? errorMessage;
  final bool wasCancelled;

  ImportPlaylistState copyWith({
    bool? isImporting,
    ImportProgress? progress,
    Object? result = _copySentinel,
    Object? errorMessage = _copySentinel,
    bool? wasCancelled,
  }) {
    return ImportPlaylistState(
      isImporting: isImporting ?? this.isImporting,
      progress: progress ?? this.progress,
      result: identical(result, _copySentinel) ? this.result : result as ImportResult?,
      errorMessage: identical(errorMessage, _copySentinel)
          ? this.errorMessage
          : errorMessage as String?,
      wasCancelled: wasCancelled ?? this.wasCancelled,
    );
  }
}

const _copySentinel = Object();

class ImportPlaylistNotifier extends StateNotifier<ImportPlaylistState> {
  ImportPlaylistNotifier(this._ref, this._createService)
      : super(const ImportPlaylistState());

  final Ref<ImportPlaylistState> _ref;
  final ImportServiceFactory _createService;

  ImportServiceFacade? _service;
  StreamSubscription<ImportProgress>? _progressSubscription;
  KeepAliveLink? _keepAliveLink;
  bool _cancelRequested = false;

  Future<ImportServiceFacade> _ensureService() async {
    if (_service != null) {
      return _service!;
    }

    final createdService = _createService();
    final service = createdService is Future<ImportServiceFacade>
        ? await createdService
        : createdService;
    _service = service;
    _progressSubscription = service.progressStream.listen((progress) {
      state = state.copyWith(progress: progress);
    });
    if (_cancelRequested) {
      service.cancelImport();
    }
    return service;
  }

  Future<ImportResult?> importFromUrl(
    String url, {
    String? customName,
    int? refreshIntervalHours,
    bool notifyOnUpdate = true,
    bool useAuth = false,
  }) async {
    _cancelRequested = false;
    _keepAliveLink ??= _ref.keepAlive();
    state = state.copyWith(
      isImporting: true,
      progress: const ImportProgress(),
      result: null,
      errorMessage: null,
      wasCancelled: false,
    );

    final service = await _ensureService();

    try {
      if (_cancelRequested) {
        state = const ImportPlaylistState(wasCancelled: true);
        return null;
      }
      final result = await service.importFromUrl(
        url,
        customName: customName,
        refreshIntervalHours: refreshIntervalHours,
        notifyOnUpdate: notifyOnUpdate,
        useAuth: useAuth,
      );
      state = state.copyWith(
        isImporting: false,
        result: result,
        errorMessage: null,
        wasCancelled: false,
      );
      return result;
    } on ImportException catch (error) {
      if (_cancelRequested) {
        state = const ImportPlaylistState(wasCancelled: true);
        return null;
      }
      state = state.copyWith(
        isImporting: false,
        errorMessage: error.toString(),
        wasCancelled: false,
      );
      rethrow;
    } catch (error) {
      if (_cancelRequested) {
        state = const ImportPlaylistState(wasCancelled: true);
        return null;
      }
      state = state.copyWith(
        isImporting: false,
        errorMessage: error.toString(),
        wasCancelled: false,
      );
      rethrow;
    } finally {
      await _service?.cleanupCancelledImport();
      _keepAliveLink?.close();
      _keepAliveLink = null;
    }
  }

  void cancelImport() {
    _cancelRequested = true;
    _service?.cancelImport();
    state = state.copyWith(wasCancelled: true);
  }

  void reset() {
    state = const ImportPlaylistState();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _service?.dispose();
    super.dispose();
  }
}

final importServiceFactoryProvider = Provider<ImportServiceFactory>((ref) {
  return () async {
    final sourceManager = ref.read(sourceManagerProvider);
    final playlistRepository = ref.read(playlistRepositoryProvider);
    final trackRepository = ref.read(trackRepositoryProvider);
    final isar = await ref.read(databaseProvider.future);

    return ImportService(
      sourceManager: sourceManager,
      playlistRepository: playlistRepository,
      trackRepository: trackRepository,
      isar: isar,
      bilibiliAccountService: ref.read(bilibiliAccountServiceProvider),
      youtubeAccountService: ref.read(youtubeAccountServiceProvider),
      neteaseAccountService: ref.read(neteaseAccountServiceProvider),
    );
  };
});

final importPlaylistProvider = StateNotifierProvider.autoDispose
    .family<ImportPlaylistNotifier, ImportPlaylistState, String>((ref, scopeId) {
  return ImportPlaylistNotifier(ref, ref.watch(importServiceFactoryProvider));
});
