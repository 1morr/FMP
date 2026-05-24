import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/settings.dart';
import 'repository_providers.dart';

typedef LoadHomeRankingSettings = Future<Settings> Function();
typedef UpdateHomeRankingSettings = Future<Settings> Function(
  void Function(Settings settings) mutate,
);

class HomeRankingSettingsState {
  final List<String> sourceOrder;
  final Set<String> disabledSources;
  final bool isLoading;

  HomeRankingSettingsState({
    List<String> sourceOrder = homeRankingSourceIds,
    Set<String> disabledSources = const <String>{},
    this.isLoading = true,
  })  : sourceOrder = List.unmodifiable(sourceOrder),
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
    state = HomeRankingSettingsState(
      sourceOrder: settings.homeRankingSourcePriorityList,
      disabledSources: settings.disabledHomeRankingSourcesSet,
      isLoading: false,
    );
  }

  Future<void> setSourceOrder(List<String> order) {
    if (_settings == null) return Future<void>.value();

    final normalized = normalizeHomeRankingSourcePriority(order.join(','));
    _sourceOrderMutation = _sourceOrderMutation.then(
      (_) => _setSourceOrder(normalized),
    );
    return _sourceOrderMutation;
  }

  Future<void> _setSourceOrder(List<String> normalized) async {
    final previousOrder = state.sourceOrder;
    state = state.copyWith(sourceOrder: normalized);

    try {
      _settings = await _updateSettings(
        (settings) => settings.homeRankingSourcePriorityList = normalized,
      );
    } catch (_) {
      state = state.copyWith(sourceOrder: previousOrder);
    }
  }

  Future<void> toggleSource(String source, bool enabled) {
    if (_settings == null || !homeRankingSourceIds.contains(source)) {
      return Future<void>.value();
    }

    _disabledSourcesMutation = _disabledSourcesMutation.then(
      (_) => _toggleSource(source, enabled),
    );
    return _disabledSourcesMutation;
  }

  Future<void> _toggleSource(String source, bool enabled) async {
    final disabled = Set<String>.from(state.disabledSources);
    if (enabled) {
      disabled.remove(source);
    } else {
      disabled.add(source);
    }

    if (disabled.length >= homeRankingSourceIds.length) {
      return;
    }

    final previousDisabled = state.disabledSources;
    state = state.copyWith(disabledSources: disabled);

    try {
      _settings = await _updateSettings(
        (settings) => settings.disabledHomeRankingSourcesSet = disabled,
      );
    } catch (_) {
      state = state.copyWith(disabledSources: previousDisabled);
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
