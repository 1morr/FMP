import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/settings/home_ranking_settings_provider.dart';

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
                  onReorderItem: (oldIndex, newIndex) => _onReorder(
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

    return ListTile(
      leading: _HomeRankingSourceLeading(
        index: index,
        icon: icon,
        isEnabled: isEnabled,
      ),
      title: Text(
        displayName,
        style: TextStyle(color: isEnabled ? null : disabledColor),
      ),
      subtitle: Text(
        isEnabled
            ? t.settings.homeRankingSettings.enabled
            : t.settings.homeRankingSettings.disabled,
        style: TextStyle(
          color: isEnabled ? colorScheme.primary : disabledColor,
          fontSize: 12,
        ),
      ),
      trailing: Switch(
        value: isEnabled,
        onChanged: onToggle,
      ),
    );
  }
}

class _HomeRankingSourceLeading extends StatelessWidget {
  final int index;
  final IconData icon;
  final bool isEnabled;

  const _HomeRankingSourceLeading({
    required this.index,
    required this.icon,
    required this.isEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const disabledAlpha = 0.38;

    return SizedBox(
      width: 56,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Icon(
                icon,
                size: 20,
                color: isEnabled
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withValues(alpha: disabledAlpha),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
