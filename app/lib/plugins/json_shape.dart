/// 插件交換的 JSON 物件的欄位表：欄位名稱 → 是否必填。
///
/// manifest 與 DTO 都以它解碼：表外的鍵、必填卻缺少或為 `null` 的欄位都拋
/// [FormatException]。嚴格是刻意的：插件作者（常是 AI）拼錯欄位名時立刻失敗，
/// 不會默默少一個值。`lib/plugins/types/fmp-plugin.d.ts` 裡同名的 interface
/// 必須與表一致（`test/plugins/type_definitions_test.dart` 比對）。
typedef JsonShape = Map<String, bool>;

/// 依 [JsonShape] 讀一個 JSON 物件。錯誤訊息帶 [path]（例如
/// `items[2].artwork`），只進 log。
final class JsonFields {
  JsonFields(Object? json, JsonShape shape, {required this.path})
    : _json = _object(json, path) {
    for (final key in _json.keys) {
      if (!shape.containsKey(key)) {
        throw FormatException('$path: unknown field "$key"');
      }
    }
    for (final MapEntry(:key, value: required) in shape.entries) {
      if (required && _json[key] == null) {
        throw FormatException('$path: missing required field "$key"');
      }
    }
  }

  final Map<String, Object?> _json;
  final String path;

  static Map<String, Object?> _object(Object? json, String path) {
    if (json is Map<String, Object?>) return json;
    throw FormatException('$path: expected an object');
  }

  /// 欄位有值（不是缺少，也不是 `null`）。
  bool has(String key) => _json[key] != null;

  /// 原始值，給形狀由呼叫端自己檢查的欄位（例如 manifest 的 `login`）。
  Object? raw(String key) => _json[key];

  String string(String key) => _require(key, optionalString(key));

  String? optionalString(String key) => switch (_json[key]) {
    null => null,
    final String value => value,
    _ => throw FormatException('$path.$key: expected a string'),
  };

  /// 去掉前後空白後不得為空。
  String nonEmptyString(String key) {
    final value = string(key);
    if (value.trim().isEmpty) {
      throw FormatException('$path.$key: must not be empty');
    }
    return value;
  }

  int integer(String key, {int min = 0}) =>
      _require(key, optionalInteger(key, min: min));

  /// JSON 的整數。`2.5` 這類小數不算；[min] 以下拋錯。
  int? optionalInteger(String key, {int min = 0}) {
    final value = switch (_json[key]) {
      null => null,
      final int value => value,
      _ => throw FormatException('$path.$key: expected an integer'),
    };
    if (value != null && value < min) {
      throw FormatException('$path.$key: must be at least $min');
    }
    return value;
  }

  bool? optionalBool(String key) => switch (_json[key]) {
    null => null,
    final bool value => value,
    _ => throw FormatException('$path.$key: expected a boolean'),
  };

  List<Object?> list(String key) => _require(key, optionalList(key));

  List<Object?>? optionalList(String key) => switch (_json[key]) {
    null => null,
    final List<Object?> value => value,
    _ => throw FormatException('$path.$key: expected an array'),
  };

  List<String> stringList(String key) => [
    for (final (index, item) in list(key).indexed)
      if (item is String)
        item
      else
        throw FormatException('$path.$key[$index]: expected a string'),
  ];

  List<String>? optionalStringList(String key) =>
      has(key) ? stringList(key) : null;

  Map<String, Object?>? optionalObject(String key) =>
      has(key) ? _object(_json[key], '$path.$key') : null;

  /// 值全是字串的物件（例如 headers）。
  Map<String, String>? optionalStringMap(String key) {
    final object = optionalObject(key);
    if (object == null) return null;
    return {
      for (final MapEntry(key: name, :value) in object.entries)
        name: value is String
            ? value
            : throw FormatException('$path.$key.$name: expected a string'),
    };
  }

  T _require<T>(String key, T? value) =>
      value ?? (throw FormatException('$path: missing required field "$key"'));
}
