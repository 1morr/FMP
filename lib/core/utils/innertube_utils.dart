/// InnerTube API 共用工具方法
class InnerTubeUtils {
  InnerTubeUtils._();

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
