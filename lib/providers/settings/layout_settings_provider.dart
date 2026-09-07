import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_layout.dart';
import '../../data/repositories/settings_repository.dart';
import '../database/repository_providers.dart';

/// 桌面版面狀態（側欄展開、詳情面板展開與寬度）。
///
/// 這三個值以前是 `_ExpandedLayoutState` 的 widget state，每次啟動都重置。
class LayoutSettingsState {
  const LayoutSettingsState({
    required this.railExpanded,
    required this.detailPanelExpanded,
    required this.detailPanelWidth,
  });

  /// 設定讀進來之前的暫時值，與 `Settings` 的業務預設一致。
  const LayoutSettingsState.initial()
      : railExpanded = false,
        detailPanelExpanded = false,
        detailPanelWidth = AppLayout.detailPanelDefault;

  final bool railExpanded;
  final bool detailPanelExpanded;
  final double detailPanelWidth;

  LayoutSettingsState copyWith({
    bool? railExpanded,
    bool? detailPanelExpanded,
    double? detailPanelWidth,
  }) {
    return LayoutSettingsState(
      railExpanded: railExpanded ?? this.railExpanded,
      detailPanelExpanded: detailPanelExpanded ?? this.detailPanelExpanded,
      detailPanelWidth: detailPanelWidth ?? this.detailPanelWidth,
    );
  }
}

class LayoutSettingsNotifier extends Notifier<LayoutSettingsState> {
  late SettingsRepository _repo;

  @override
  LayoutSettingsState build() {
    _repo = ref.watch(settingsRepositoryProvider);
    _load();
    return const LayoutSettingsState.initial();
  }

  Future<void> _load() async {
    final settings = await _repo.get();
    if (!ref.mounted) return;
    state = LayoutSettingsState(
      railExpanded: settings.railExpanded,
      detailPanelExpanded: settings.detailPanelExpanded,
      detailPanelWidth: settings.detailPanelWidth,
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
    NotifierProvider<LayoutSettingsNotifier, LayoutSettingsState>(
        LayoutSettingsNotifier.new);
