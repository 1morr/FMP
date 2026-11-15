import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';

/// 外殼導覽到得了的地方（brief〈介面〉）：四個分頁加上獨立的搜尋。
enum Destination {
  home('/home', FmpIcons.home),
  library('/library', FmpIcons.library),
  queue('/queue', FmpIcons.queue),
  settings('/settings', FmpIcons.settings),
  search('/search', FmpIcons.search);

  const Destination(this.path, this.icon);

  final String path;
  final FmpIcons icon;

  /// 導覽膠囊的四項，照稿的順序。
  static const tabs = [home, library, queue, settings];

  /// 路徑對到的地方；對不到時是首頁。
  static Destination of(String path) =>
      values.firstWhere((d) => d.path == path, orElse: () => home);

  String label(Translations t) => switch (this) {
    home => t.shell.nav.home,
    library => t.shell.nav.library,
    queue => t.shell.nav.queue,
    settings => t.shell.nav.settings,
    search => t.shell.nav.search,
  };
}
