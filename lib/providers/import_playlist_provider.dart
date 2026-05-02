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
      result: identical(result, _copySentinel)
          ? this.result
          : result as ImportResult?,
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
  int _operationId = 0;
  int? _activeOperationId;

  bool _isActiveOperation(int operationId) {
    return mounted && _activeOperationId == operationId;
  }

  Future<ImportServiceFacade> _createServiceForOperation(
      int operationId) async {
    final createdService = _createService();
    final service = createdService is Future<ImportServiceFacade>
        ? await createdService
        : createdService;

    if (!_isActiveOperation(operationId)) {
      service.cancelImport();
      return service;
    }

    final previousSubscription = _progressSubscription;
    if (previousSubscription != null) {
      await previousSubscription.cancel();
      if (!_isActiveOperation(operationId)) {
        service.cancelImport();
        return service;
      }
    }

    _service = service;
    _progressSubscription = service.progressStream.listen((progress) {
      if (_isActiveOperation(operationId)) {
        state = state.copyWith(progress: progress);
      }
    });
    return service;
  }

  Future<ImportResult?> importFromUrl(
    String url, {
    String? customName,
    int? refreshIntervalHours,
    bool notifyOnUpdate = true,
    bool useAuth = false,
  }) async {
    final operationId = ++_operationId;
    _activeOperationId = operationId;
    _service?.cancelImport();
    _progressSubscription?.cancel();
    _progressSubscription = null;
    _keepAliveLink ??= _ref.keepAlive();
    state = state.copyWith(
      isImporting: true,
      progress: const ImportProgress(),
      result: null,
      errorMessage: null,
      wasCancelled: false,
    );

    final service = await _createServiceForOperation(operationId);

    try {
      if (!_isActiveOperation(operationId)) {
        return null;
      }
      final result = await service.importFromUrl(
        url,
        customName: customName,
        refreshIntervalHours: refreshIntervalHours,
        notifyOnUpdate: notifyOnUpdate,
        useAuth: useAuth,
      );
      if (!_isActiveOperation(operationId)) {
        return result;
      }
      state = state.copyWith(
        isImporting: false,
        result: result,
        errorMessage: null,
        wasCancelled: false,
      );
      _activeOperationId = null;
      return result;
    } on ImportException catch (error) {
      if (!_isActiveOperation(operationId)) {
        return null;
      }
      state = state.copyWith(
        isImporting: false,
        errorMessage: error.toString(),
        wasCancelled: false,
      );
      _activeOperationId = null;
      rethrow;
    } catch (error) {
      if (!_isActiveOperation(operationId)) {
        return null;
      }
      state = state.copyWith(
        isImporting: false,
        errorMessage: error.toString(),
        wasCancelled: false,
      );
      _activeOperationId = null;
      rethrow;
    } finally {
      await service.cleanupCancelledImport();
      service.dispose();
      if (identical(_service, service)) {
        _service = null;
      }
      if (_activeOperationId == null && mounted) {
        _keepAliveLink?.close();
        _keepAliveLink = null;
      }
    }
  }

  void cancelImport() {
    _operationId++;
    _activeOperationId = null;
    _service?.cancelImport();
    state = state.copyWith(wasCancelled: true);
  }

  void reset() {
    _operationId++;
    _activeOperationId = null;
    _service?.cancelImport();
    state = const ImportPlaylistState();
  }

  @override
  void dispose() {
    _operationId++;
    _activeOperationId = null;
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
    .family<ImportPlaylistNotifier, ImportPlaylistState, String>(
        (ref, scopeId) {
  return ImportPlaylistNotifier(ref, ref.watch(importServiceFactoryProvider));
});
