///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsZhTw = Translations; // ignore: unused_element

class Translations with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  Translations({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<AppLocale, Translations>? meta,
  }) : assert(
         overrides == null,
         'Set "translation_overrides: true" in order to enable this feature.',
       ),
       _meta =
           meta ??
           TranslationMetadata(
             locale: AppLocale.zhTw,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           );

  /// Metadata for the translations of <zh-TW>.
  final TranslationMetadata<AppLocale, Translations> _meta;
  @override
  TranslationMetadata<AppLocale, Translations> get $meta => _meta;

  late final Translations _root = this; // ignore: unused_field

  Translations $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => Translations(meta: meta ?? this.$meta);

  // Translations
  late final Translations$startup$zh_TW startup =
      Translations$startup$zh_TW.internal(_root);
  late final Translations$appearance$zh_TW appearance =
      Translations$appearance$zh_TW.internal(_root);
  late final Translations$errors$zh_TW errors =
      Translations$errors$zh_TW.internal(_root);
}

// Path: startup
class Translations$startup$zh_TW {
  Translations$startup$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '無法開啟資料庫'
  String get databaseError => '無法開啟資料庫';

  /// zh-TW: '此平台尚未支援'
  String get unsupportedPlatform => '此平台尚未支援';
}

// Path: appearance
class Translations$appearance$zh_TW {
  Translations$appearance$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '主題'
  String get theme => '主題';

  /// zh-TW: '跟隨系統'
  String get themeSystem => '跟隨系統';

  /// zh-TW: '淺色'
  String get themeLight => '淺色';

  /// zh-TW: '深色'
  String get themeDark => '深色';

  /// zh-TW: '語言'
  String get language => '語言';

  /// zh-TW: '跟隨系統'
  String get languageSystem => '跟隨系統';
}

// Path: errors
class Translations$errors$zh_TW {
  Translations$errors$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '網路連線失敗，請檢查網路後再試'
  String get network => '網路連線失敗，請檢查網路後再試';

  /// zh-TW: '{source} 請求太頻繁，請稍後再試'
  String rateLimited({required Object source}) => '${source} 請求太頻繁，請稍後再試';

  /// zh-TW: '需要登入 {source}'
  String authRequired({required Object source}) => '需要登入 ${source}';

  /// zh-TW: '{source} 的登入已失效，請重新登入'
  String credentialInvalid({required Object source}) =>
      '${source} 的登入已失效，請重新登入';

  /// zh-TW: '{source} 要求驗證：請登入、貼上 cookie 或稍後再試'
  String verificationRequired({required Object source}) =>
      '${source} 要求驗證：請登入、貼上 cookie 或稍後再試';

  /// zh-TW: '無法取得這個內容'
  String get unavailable => '無法取得這個內容';

  /// zh-TW: '無法取得：{reason}'
  String unavailableBecause({required Object reason}) => '無法取得：${reason}';

  /// zh-TW: '找不到內容，可能已失效'
  String get notFound => '找不到內容，可能已失效';

  /// zh-TW: '{source} 的回應格式改變，可能需要更新'
  String parseError({required Object source}) => '${source} 的回應格式改變，可能需要更新';

  /// zh-TW: '發生預期外的錯誤'
  String get unexpected => '發生預期外的錯誤';

  /// zh-TW: '音源'
  String get unknownSource => '音源';

  late final Translations$errors$unavailableReasons$zh_TW unavailableReasons =
      Translations$errors$unavailableReasons$zh_TW.internal(_root);
}

// Path: errors.unavailableReasons
class Translations$errors$unavailableReasons$zh_TW {
  Translations$errors$unavailableReasons$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '所在地區不提供'
  String get region => '所在地區不提供';

  /// zh-TW: '版權限制'
  String get copyright => '版權限制';

  /// zh-TW: '需要會員'
  String get membership => '需要會員';

  /// zh-TW: '有年齡限制'
  String get age => '有年齡限制';

  /// zh-TW: '只有試聽片段'
  String get previewOnly => '只有試聽片段';
}
