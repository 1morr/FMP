import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/cover_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fmp/ui/common/motion.dart';

/// 封面網址換成圖：預設是磁碟快取的 [coverImage]；測試與不聯網的實跑情境
/// 換成記憶體裡的圖。
final coverImageLoaderProvider = Provider<ImageProvider Function(String url)>(
  (_) => coverImage,
);

/// 封面（`.cover`）：圓角方塊，沒有封面、載入中或載入失敗時是 `--cell-2`
/// 的底；外緣一圈 0.5 的細線（`--cover-ring`）。圖載入後 out 160 淡入，已經在
/// 記憶體裡的直接出現（`DESIGN.md`〈狀態變化對照〉的圖片載入）。
class Cover extends ConsumerWidget {
  const Cover({
    super.key,
    required this.url,
    required this.size,
    required this.radius,
    this.crossFade = false,
  });

  final String? url;
  final double size;
  final double radius;

  /// 換成另一張封面時 out 280 交叉淡出（換歌時的迷你播放器、播放膠囊、
  /// 播放頁、詳情面板）；減少動態效果時照樣。清單裡的列不用。
  final bool crossFade;

  static const imageFadeKey = Key('cover-image-fade');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.fmpColors;
    final load = ref.watch(coverImageLoaderProvider);
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: colors.coverRing, width: .5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: ColoredBox(
            color: colors.cell2,
            child: crossFade
                ? _CrossFadeCover(
                    url: url,
                    provider: (url) => _provider(load, url, pixels),
                    image: (url) => _image(load, pixels, url: url),
                  )
                : _image(load, pixels, url: url),
          ),
        ),
      ),
    );
  }

  ImageProvider _provider(
    ImageProvider Function(String url) load,
    String url,
    int pixels,
  ) => ResizeImage(
    load(url),
    width: pixels,
    height: pixels,
    policy: ResizeImagePolicy.fit,
  );

  Widget? _image(
    ImageProvider Function(String url) load,
    int pixels, {
    required String? url,
  }) => switch (url) {
    null => null,
    final url => Image(
      image: _provider(load, url, pixels),
      fit: BoxFit.cover,
      width: size,
      height: size,
      gaplessPlayback: !crossFade,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, synchronous) => synchronous
          ? child
          : PreservedFade(
              key: imageFadeKey,
              opacity: frame == null ? 0 : 1,
              duration: FmpMotion.fast,
              child: child,
            ),
      // 有 errorBuilder 時失敗不報成 Flutter 錯誤；留著底色。
      errorBuilder: (_, _, _) => const SizedBox.expand(),
    ),
  };
}

/// 換歌時的封面：新封面解碼出第一個 frame 才 out 280 交叉淡出（之前舊封面
/// 完整留著，不先淡到底色）；已經在記憶體裡的直接換；新封面載入失敗才淡到
/// 底色。減少動態效果時照樣。
class _CrossFadeCover extends StatefulWidget {
  const _CrossFadeCover({
    required this.url,
    required this.provider,
    required this.image,
  });

  final String? url;
  final ImageProvider Function(String url) provider;
  final Widget? Function(String? url) image;

  @override
  State<_CrossFadeCover> createState() => _CrossFadeCoverState();
}

class _CrossFadeCoverState extends State<_CrossFadeCover> {
  /// 畫面上的那張；等新的那張的第一個 frame 時還是舊的。
  late String? _shown = widget.url;

  /// 每換一次網址加一；等到的結果不是最新那次的就丟掉。
  int _generation = 0;

  @override
  void didUpdateWidget(_CrossFadeCover old) {
    super.didUpdateWidget(old);
    if (widget.url != old.url) _wait(widget.url);
  }

  void _wait(String? url) {
    final generation = ++_generation;
    if (url == null) {
      _shown = null;
      return;
    }
    final provider = widget.provider(url);
    // 已經解碼在記憶體裡：直接換，接下來的 build 就畫它（key 是同步拿到的）。
    var cached = false;
    provider.obtainKey(createLocalImageConfiguration(context)).then((key) {
      cached = PaintingBinding.instance.imageCache.statusForKey(key).keepAlive;
    });
    if (cached) {
      _shown = url;
      return;
    }
    var failed = false;
    precacheImage(provider, context, onError: (_, _) => failed = true).then((
      _,
    ) {
      if (!mounted || generation != _generation) return;
      setState(() => _shown = failed ? null : url);
    });
  }

  @override
  Widget build(BuildContext context) => PreservedSwitcher(
    key: const Key('cover-cross-fade'),
    fit: StackFit.expand,
    child: KeyedSubtree(
      key: ValueKey(_shown),
      child: widget.image(_shown) ?? const SizedBox.expand(),
    ),
  );
}
