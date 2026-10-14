import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:fmp/domain/appearance.dart';

var _initialized = false;

/// 日期（年月日），依介面語言寫成 `2024年5月17日`、`May 17, 2024`（CLDR 的 `yMMMd`），
/// 顯示在本機時區。
String formatDate(LocaleSetting locale, DateTime date) {
  if (!_initialized) {
    // 以內建資料初始化，同步完成；回傳的 Future 沒有東西可等。
    initializeDateFormatting();
    _initialized = true;
  }
  return DateFormat.yMMMd(switch (locale) {
    LocaleSetting.zhTw => 'zh_TW',
    LocaleSetting.zhCn => 'zh_CN',
    LocaleSetting.en => 'en',
  }).format(date.toLocal());
}
