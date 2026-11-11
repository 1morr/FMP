import 'package:flutter/material.dart';
import 'package:fmp/app/i18n/strings.g.dart';

/// M0 的佔位畫面；照設計稿的畫面從 M1 開始。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.app.name, style: textTheme.displayMedium),
            const SizedBox(height: 8),
            Text(t.placeholder.subtitle, style: textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
