import 'package:flutter/material.dart';

class SwitchExpansionTile extends StatelessWidget {
  final String title;
  final bool expanded;
  final bool enabled;
  final ValueChanged<bool> onExpanded;
  final ValueChanged<bool> onEnabledChanged;
  final List<Widget> children;

  const SwitchExpansionTile({
    super.key,
    required this.title,
    required this.expanded,
    required this.enabled,
    required this.onExpanded,
    required this.onEnabledChanged,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey(expanded),
          tilePadding: const EdgeInsets.only(left: 10, right: 6),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          visualDensity: VisualDensity.compact,
          initiallyExpanded: expanded,
          onExpansionChanged: onExpanded,
          title: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 0.78,
                child: Switch(
                  value: enabled,
                  onChanged: onEnabledChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 160),
                child: const Icon(Icons.expand_more, size: 20),
              ),
            ],
          ),
          children: children,
        ),
      ),
    );
  }
}
