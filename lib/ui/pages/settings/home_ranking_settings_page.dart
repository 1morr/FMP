import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/home_ranking_settings_provider.dart';

/// Home recent trending ranking source settings page.
class HomeRankingSettingsPage extends ConsumerWidget {
  const HomeRankingSettingsPage({super.key});

  String _sourceDisplayName(String source) {
    return switch (source) {
      'bilibili' => t.importPlatform.bilibili,
      'youtube' => t.importPlatform.youtube,
      'netease' => t.importPlatform.netease,
      _ => source,
    };
  }

  IconData _sourceIcon(String source) {
    return switch (source) {
      'bilibili' => SimpleIcons.bilibili,
      'youtube' => SimpleIcons.youtube,
      'netease' => SimpleIcons.neteasecloudmusic,
      _ => Icons.source_outlined,
    };
  }

  void _onReorder(
    WidgetRef ref,
    List<String> currentOrder,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) newIndex--;
    final order = List<String>.from(currentOrder);
    final item = order.removeAt(oldIndex);
    order.insert(newIndex, item);
    ref.read(homeRankingSettingsProvider.notifier).setSourceOrder(order);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(homeRankingSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settings.homeRankingSettings.title),
      ),
      body: settings.isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      t.settings.homeRankingSettings.hint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ),
                ),
                SliverReorderableList(
                  itemCount: settings.sourceOrder.length,
                  onReorder: (oldIndex, newIndex) => _onReorder(
                    ref,
                    settings.sourceOrder,
                    oldIndex,
                    newIndex,
                  ),
                  proxyDecorator: (child, index, animation) {
                    final elevation = Tween<double>(begin: 0, end: 4)
                        .animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        ))
                        .value;
                    return Material(
                      elevation: elevation,
                      borderRadius: AppRadius.borderRadiusLg,
                      child: child,
                    );
                  },
                  itemBuilder: (context, index) {
                    final source = settings.sourceOrder[index];
                    final isEnabled =
                        !settings.disabledSources.contains(source);
                    final enabledCount = settings.enabledSourceOrder.length;
                    final canToggleOff = !isEnabled || enabledCount > 1;

                    return _HomeRankingSourceTile(
                      key: ValueKey(source),
                      index: index,
                      displayName: _sourceDisplayName(source),
                      icon: _sourceIcon(source),
                      isEnabled: isEnabled,
                      onToggle: canToggleOff
                          ? (enabled) => ref
                              .read(homeRankingSettingsProvider.notifier)
                              .toggleSource(source, enabled)
                          : null,
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _HomeRankingSourceTile extends StatelessWidget {
  final int index;
  final String displayName;
  final IconData icon;
  final bool isEnabled;
  final ValueChanged<bool>? onToggle;

  const _HomeRankingSourceTile({
    super.key,
    required this.index,
    required this.displayName,
    required this.icon,
    required this.isEnabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const disabledAlpha = 0.38;
    final disabledColor =
        colorScheme.onSurface.withValues(alpha: disabledAlpha);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle == null ? null : () => onToggle!(!isEnabled),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.drag_handle,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(
                  icon,
                  size: 20,
                  color: isEnabled ? colorScheme.onSurface : disabledColor,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(color: isEnabled ? null : disabledColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEnabled
                          ? t.settings.homeRankingSettings.enabled
                          : t.settings.homeRankingSettings.disabled,
                      style: TextStyle(
                        color: isEnabled ? colorScheme.primary : disabledColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Switch(
                value: isEnabled,
                onChanged: onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
