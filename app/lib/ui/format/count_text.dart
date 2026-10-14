import 'package:intl/intl.dart';

import 'package:fmp/domain/appearance.dart';

/// 人數之類的大數字：CLDR 的縮寫（ADR 0024 §決定 6），依介面語言寫成 `4600萬`、`4600万`、
/// `46M`。
String formatCount(LocaleSetting locale, int count) => NumberFormat.compact(
  locale: switch (locale) {
    LocaleSetting.zhTw => 'zh_TW',
    LocaleSetting.zhCn => 'zh_CN',
    LocaleSetting.en => 'en',
  },
).format(count);
