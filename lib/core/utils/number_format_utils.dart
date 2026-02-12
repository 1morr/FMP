import '../../i18n/strings.g.dart';

/// 根据当前语言环境格式化数字
///
/// - zh-CN/zh-TW: 万 (10,000) / 亿 (100,000,000)
/// - en: K (1,000) / M (1,000,000) / B (1,000,000,000)
String formatCount(int count) {
  final locale = LocaleSettings.currentLocale;

  if (locale == AppLocale.en) {
    return _formatEnglish(count);
  } else {
    return _formatChinese(count, locale);
  }
}

String _formatEnglish(int count) {
  if (count >= 1000000000) {
    return '${(count / 1000000000).toStringAsFixed(1)}B';
  } else if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(1)}M';
  } else if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}K';
  }
  return count.toString();
}

String _formatChinese(int count, AppLocale locale) {
  final yi = locale == AppLocale.zhTw ? '億' : '亿';
  final wan = locale == AppLocale.zhTw ? '萬' : '万';

  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)}$yi';
  } else if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(1)}$wan';
  }
  return count.toString();
}
