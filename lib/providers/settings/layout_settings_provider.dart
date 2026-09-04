import 'package:flutter_riverpod/legacy.dart';

import '../../data/repositories/settings_repository.dart';
import '../database/repository_providers.dart';

/// 桌面版面狀態（側欄展開、詳情面板展開與寬度）。
///
/// 這三個值以前是 `_DesktopLayoutState` 的 widget state，每次啟動都重置。
class LayoutSettingsState {
  const LayoutSettingsState({
    required this.railExpanded,
    required this.detailPanelExpanded,
    required this.detailPanelWidth,
    required this.isLoaded,
  });

  const LayoutSettingsState.initial()
      : railExpanded = false,
        detailPanelExpanded = true,
        detailPanelWidth = 380,
        isLoaded = false;

  final bool railExpanded;
  final bool detailPanelExpanded;
  final double detailPanelWidth;

  /// 設定讀進來之前不要覆寫使用者正在操作的版面。
  final bool isLoaded;

  LayoutSettingsState copyWith({
    bool? railExpanded,
    bool? detailPanelExpanded,
    double? detailPanelWidth,
    bool? isLoaded,
  }) {
    return LayoutSettingsState(
      railExpanded: railExpanded ?? this.railExpanded,
      detailPanelExpanded: detailPanelExpanded ?? this.detailPanelExpanded,
      detailPanelWidth: detailPanelWidth ?? this.detailPanelWidth,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class LayoutSettingsNotifier extends StateNotifier<LayoutSettingsState> {
  LayoutSettingsNotifier(this._repo)
      : super(const LayoutSettingsState.initial()) {
    _load();
  }

  final SettingsRepository _repo;

  Future<void> _load() async {
    final settings = await _repo.get();
    if (!mounted) return;
    state = LayoutSettingsState(
      railExpanded: settings.railExpanded,
      detailPanelExpanded: settings.detailPanelExpanded,
      detailPanelWidth: settings.detailPanelWidth,
      isLoaded: true,
    );
  }

  Future<void> setRailExpanded(bool value) async {
    state = state.copyWith(railExpanded: value);
    await _repo.update((s) => s.railExpanded = value);
  }

  Future<void> setDetailPanelExpanded(bool value) async {
    state = state.copyWith(detailPanelExpanded: value);
    await _repo.update((s) => s.detailPanelExpanded = value);
  }

  /// 拖曳期間只更新記憶體中的狀態；放開時才寫入資料庫。
  void previewDetailPanelWidth(double value) {
    state = state.copyWith(detailPanelWidth: value);
  }

  Future<void> commitDetailPanelWidth(double value) async {
    state = state.copyWith(detailPanelWidth: value);
    await _repo.update((s) => s.detailPanelWidth = value);
  }
}

final layoutSettingsProvider =
    StateNotifierProvider<LayoutSettingsNotifier, LayoutSettingsState>((ref) {
  return LayoutSettingsNotifier(ref.watch(settingsRepositoryProvider));
});
