import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/settings.dart';
import '../database/repository_providers.dart';

typedef LoadHomeRankingSettings = Future<Settings> Function();
typedef UpdateHomeRankingSettings = Future<Settings> Function(
  void Function(Settings settings) mutate,
);

class HomeRankingSettingsState {
  final List<String> sourceOrder;
  final Set<String> disabledSources;
  final bool isLoading;

  HomeRankingSettingsState({
    List<String>? sourceOrder,
    Set<String> disabledSources = const <String>{},
    this.isLoading = true,
  })  : sourceOrder = List.unmodifiable(sourceOrder ?? homeRankingSourceIds),
        disabledSources = Set.unmodifiable(disabledSources);

  List<String> get enabledSourceOrder => List.unmodifiable(
        sourceOrder.where((source) => !disabledSources.contains(source)),
      );

  HomeRankingSettingsState copyWith({
    List<String>? sourceOrder,
    Set<String>? disabledSources,
    bool? isLoading,
  }) {
    return HomeRankingSettingsState(
      sourceOrder: sourceOrder ?? this.sourceOrder,
      disabledSources: disabledSources ?? this.disabledSources,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class HomeRankingSettingsNotifier
    extends StateNotifier<HomeRankingSettingsState> {
  final LoadHomeRankingSettings _loadSettingsFromStore;
  final UpdateHomeRankingSettings _updateSettings;
  Settings? _settings;
  Future<void> _sourceOrderMutation = Future<void>.value();
  Future<void> _disabledSourcesMutation = Future<void>.value();
  List<String> _persistedSourceOrder = homeRankingSourceIds;
  Set<String> _persistedDisabledSources = const <String>{};
  int _sourceOrderGeneration = 0;
  int _disabledSourcesGeneration = 0;

  HomeRankingSettingsNotifier({
    required LoadHomeRankingSettings loadSettings,
    required UpdateHomeRankingSettings updateSettings,
  })  : _loadSettingsFromStore = loadSettings,
        _updateSettings = updateSettings,
        super(HomeRankingSettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _loadSettingsFromStore();
    _settings = settings;
    _persistedSourceOrder = settings.homeRankingSourcePriorityList;
    _persistedDisabledSources = settings.disabledHomeRankingSourcesSet;
    state = HomeRankingSettingsState(
      sourceOrder: _persistedSourceOrder,
      disabledSources: _persistedDisabledSources,
      isLoading: false,
    );
  }

  Future<void> setSourceOrder(List<String> order) {
    if (_settings == null) return Future<void>.value();

    final normalized = normalizeHomeRankingSourcePriority(order.join(','));
    if (listEquals(normalized, state.sourceOrder)) {
      return Future<void>.value();
    }
    final generation = ++_sourceOrderGeneration;
    state = state.copyWith(sourceOrder: normalized);

    _sourceOrderMutation = _sourceOrderMutation.then(
      (_) => _persistSourceOrder(normalized, generation),
    );
    return _sourceOrderMutation;
  }

  Future<void> _persistSourceOrder(
    List<String> normalized,
    int generation,
  ) async {
    try {
      _settings = await _updateSettings(
        (settings) => settings.homeRankingSourcePriorityList = normalized,
      );
      _persistedSourceOrder = _settings!.homeRankingSourcePriorityList;
      if (_sourceOrderGeneration == generation) {
        state = state.copyWith(sourceOrder: _persistedSourceOrder);
      }
    } catch (_) {
      if (_sourceOrderGeneration == generation) {
        state = state.copyWith(sourceOrder: _persistedSourceOrder);
      }
    }
  }

  Future<void> toggleSource(String source, bool enabled) {
    if (_settings == null || !homeRankingSourceIds.contains(source)) {
      return Future<void>.value();
    }

    final disabled = _applySourceToggle(
      state.disabledSources,
      source,
      enabled,
    );

    if (disabled.length >= homeRankingSourceIds.length) {
      return Future<void>.value();
    }

    if (setEquals(disabled, state.disabledSources)) {
      return Future<void>.value();
    }

    final generation = ++_disabledSourcesGeneration;
    state = state.copyWith(disabledSources: disabled);

    _disabledSourcesMutation = _disabledSourcesMutation.then(
      (_) => _persistSourceToggle(source, enabled, generation),
    );
    return _disabledSourcesMutation;
  }

  Set<String> _applySourceToggle(
    Set<String> current,
    String source,
    bool enabled,
  ) {
    final disabled = Set<String>.from(current);
    if (enabled) {
      disabled.remove(source);
    } else {
      disabled.add(source);
    }
    return disabled;
  }

  Future<void> _persistSourceToggle(
    String source,
    bool enabled,
    int generation,
  ) async {
    try {
      _settings = await _updateSettings(
        (settings) {
          final disabled = _applySourceToggle(
            settings.disabledHomeRankingSourcesSet,
            source,
            enabled,
          );
          if (disabled.length < homeRankingSourceIds.length) {
            settings.disabledHomeRankingSourcesSet = disabled;
          }
        },
      );
      _persistedDisabledSources = _settings!.disabledHomeRankingSourcesSet;
      if (_disabledSourcesGeneration == generation) {
        state = state.copyWith(disabledSources: _persistedDisabledSources);
      }
    } catch (_) {
      if (_disabledSourcesGeneration == generation) {
        state = state.copyWith(
          disabledSources: _persistedDisabledSources,
        );
      }
    }
  }
}

final homeRankingSettingsProvider = StateNotifierProvider<
    HomeRankingSettingsNotifier, HomeRankingSettingsState>((ref) {
  final repository = ref.watch(settingsRepositoryProvider);
  return HomeRankingSettingsNotifier(
    loadSettings: repository.get,
    updateSettings: repository.update,
  );
});

final enabledHomeRankingSourceOrderProvider = Provider<List<String>>((ref) {
  return ref.watch(homeRankingSettingsProvider).enabledSourceOrder;
});
