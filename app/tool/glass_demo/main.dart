// 玻璃元件的示範畫面：四平台實跑、截三級的圖用，不是產品的一部分。
// 建置：`flutter build <平台> -t tool/glass_demo/main.dart`（docs/development.md〈平台〉）。
//
// 背景是黑色直條紋的彩色列表，折射看條紋在玻璃邊緣有沒有被彎曲。左上三個
// 按鈕切 App 的「玻璃效果」（完整、輕量、關閉），畫面上所有玻璃一起換。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(const ProviderScope(child: GlassDemoApp()));

class GlassDemoApp extends StatelessWidget {
  const GlassDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final density = Density.current;
    return MaterialApp(
      title: 'FMP glass demo',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: buildTheme(brightness: Brightness.light, density: density),
      darkTheme: buildTheme(brightness: Brightness.dark, density: density),
      home: const GlassDemoPage(),
    );
  }
}

class GlassDemoPage extends ConsumerWidget {
  const GlassDemoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(glassEffectProvider);
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _StripedList()),
          Positioned(
            left: 16,
            top: 48,
            child: Row(
              children: [
                for (final (tier, label) in const [
                  (GlassTier.refract, 'Full'),
                  (GlassTier.standard, 'Lite'),
                  (GlassTier.minimal, 'Off'),
                ]) ...[
                  _TierButton(
                    label: label,
                    selected: current == tier,
                    onTap: () =>
                        ref.read(glassEffectProvider.notifier).set(tier),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 112,
            child: Text(
              'glass: ${current.name}',
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),
          const Positioned(left: 16, top: 150, child: _Cover()),
          const Positioned(left: 16, right: 16, top: 360, child: _Toast()),
          const Positioned(left: 16, right: 16, bottom: 32, child: _Dock()),
        ],
      ),
    );
  }
}

class _TierButton extends StatelessWidget {
  const _TierButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Glass(
        child: Container(
          width: 84,
          height: 44,
          alignment: Alignment.center,
          color: selected ? context.fmpColors.glassPress : null,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 封面上的 clear 玻璃：播放鈕與音源膠囊，底下有暗層。
class _Cover extends StatelessWidget {
  const _Cover();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB347), Color(0xFFE0457B), Color(0xFF5E4BFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color.fromRGBO(0, 0, 0, .25),
      ),
      padding: const EdgeInsets.all(12),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Glass(
            variant: GlassVariant.clear,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text('clear · source'),
            ),
          ),
          Spacer(),
          Glass(
            variant: GlassVariant.clear,
            child: SizedBox.square(
              dimension: 48,
              child: Icon(Icons.play_arrow_rounded, size: 30),
            ),
          ),
        ],
      ),
    );
  }
}

/// 承載文字的 thick 玻璃（提示）。
class _Toast extends StatelessWidget {
  const _Toast();

  @override
  Widget build(BuildContext context) {
    return Glass(
      variant: GlassVariant.thick,
      radius: 26,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.check_circle_rounded, size: 20),
            const SizedBox(width: 10),
            Text('thick · added to queue', style: context.fmpText.sub),
          ],
        ),
      ),
    );
  }
}

/// 手機 dock：迷你播放器、導覽膠囊與搜尋圓鈕，regular 玻璃。
class _Dock extends StatelessWidget {
  const _Dock();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Glass(
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                const SizedBox(width: 20),
                const Expanded(
                  child: Text(
                    'regular · mini player',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.pause_rounded),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.skip_next_rounded),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Expanded(
              child: Glass(
                child: SizedBox(
                  height: 62,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Icon(Icons.home_rounded),
                      Icon(Icons.library_music_rounded),
                      Icon(Icons.queue_music_rounded),
                      Icon(Icons.settings_rounded),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: 10),
            Glass(
              child: SizedBox.square(
                dimension: 62,
                child: Icon(Icons.search_rounded),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 彩色列、黑色直條紋，和 `scripts/experiments/glass/` 的 probe 同一種背景。
class _StripedList extends StatelessWidget {
  const _StripedList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 400,
      itemExtent: 64,
      itemBuilder: (context, i) => CustomPaint(
        painter: _StripePainter(
          HSVColor.fromAHSV(1, (i * 23) % 360, .75, .95).toColor(),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, top: 20),
          child: Text(
            'Track $i',
            style: const TextStyle(
              color: Color(0xFF000000),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final bar = Paint()..color = const Color(0xFF000000);
    for (var x = 24.0; x < size.width; x += 48) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 6, size.height), bar);
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.color != color;
}
