/// InnerTube API 共用工具方法與設定值
class InnerTubeUtils {
  InnerTubeUtils._();

  /// InnerTube WEB 用戶端的 API 基礎 URL。
  static const String apiBase = 'https://www.youtube.com/youtubei/v1';

  /// InnerTube WEB 用戶端的公開 API key。
  ///
  /// 這**不是**外洩的私密金鑰：它是 youtube.com 前端自己硬編碼在
  /// `ytcfg.INNERTUBE_API_KEY` 裡的公開 WEB client key，pytube、NewPipe、
  /// YouTube.js 等專案也都原樣照抄同一組值。它不綁定任何 Google Cloud
  /// 專案、不計費，且對所有使用者都相同，因此不需要（也無法）保密。
  static const String apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  /// InnerTube 用戶端名稱。
  static const String clientName = 'WEB';

  /// InnerTube 用戶端版本，需與 youtube.com 前端保持同步。
  static const String clientVersion = '2.20260128.05.00';

  /// 從 InnerTube Text 對象中提取文本（支持 simpleText 和 runs）
  static String? extractText(dynamic textObj) {
    if (textObj == null) return null;
    if (textObj is String) return textObj;
    if (textObj is Map) {
      final simple = textObj['simpleText'] as String?;
      if (simple != null) return simple;
      final runs = textObj['runs'] as List?;
      if (runs != null && runs.isNotEmpty) {
        return runs.map((r) => r['text'] ?? '').join();
      }
    }
    return null;
  }

  /// 遞歸搜索指定 renderer key
  static Map<String, dynamic>? findRenderer(
    dynamic data,
    String key, [
    int depth = 0,
  ]) {
    if (depth > 10) return null;
    if (data is Map<String, dynamic>) {
      if (data.containsKey(key) && data[key] is Map<String, dynamic>) {
        return data[key] as Map<String, dynamic>;
      }
      for (final value in data.values) {
        final result = findRenderer(value, key, depth + 1);
        if (result != null) return result;
      }
    } else if (data is List) {
      for (final item in data) {
        final result = findRenderer(item, key, depth + 1);
        if (result != null) return result;
      }
    }
    return null;
  }

  /// 遞歸搜索指定字段名的字符串值
  static String? findStringField(
    dynamic data,
    String fieldName, [
    int depth = 0,
  ]) {
    if (depth > 10) return null;
    if (data is Map<String, dynamic>) {
      if (data.containsKey(fieldName)) {
        final value = data[fieldName];
        final text = extractText(value);
        if (text != null && text.isNotEmpty) return text;
      }
      for (final value in data.values) {
        final result = findStringField(value, fieldName, depth + 1);
        if (result != null) return result;
      }
    } else if (data is List) {
      for (final item in data) {
        final result = findStringField(item, fieldName, depth + 1);
        if (result != null) return result;
      }
    }
    return null;
  }
}
