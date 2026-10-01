///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

import 'package:intl/intl.dart';
import 'package:slang/generated.dart';

import 'strings.g.dart';

// Path: <root>
class TranslationsZhCn extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsZhCn({
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
             locale: AppLocale.zhCn,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <zh-CN>.
  final TranslationMetadata<AppLocale, Translations> _meta;
  @override
  TranslationMetadata<AppLocale, Translations> get $meta => _meta;

  late final TranslationsZhCn _root = this; // ignore: unused_field

  @override
  TranslationsZhCn $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsZhCn(meta: meta ?? this.$meta);

  // Translations
  @override
  late final Translations$startup$zh_CN startup =
      Translations$startup$zh_CN.internal(_root);
  @override
  late final Translations$shell$zh_CN shell = Translations$shell$zh_CN.internal(
    _root,
  );
  @override
  late final Translations$search$zh_CN search =
      Translations$search$zh_CN.internal(_root);
  @override
  late final Translations$offline$zh_CN offline =
      Translations$offline$zh_CN.internal(_root);
  @override
  late final Translations$settings$zh_CN settings =
      Translations$settings$zh_CN.internal(_root);
  @override
  late final Translations$player$zh_CN player =
      Translations$player$zh_CN.internal(_root);
  @override
  late final Translations$appearance$zh_CN appearance =
      Translations$appearance$zh_CN.internal(_root);
  @override
  late final Translations$errors$zh_CN errors =
      Translations$errors$zh_CN.internal(_root);
}

// Path: startup
class Translations$startup$zh_CN extends Translations$startup$zh_TW {
  Translations$startup$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get databaseError => '无法打开数据库';
  @override
  String get unsupportedPlatform => '暂不支持此平台';
}

// Path: shell
class Translations$shell$zh_CN extends Translations$shell$zh_TW {
  Translations$shell$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get search => '搜索';
  @override
  String get settings => '设置';
  @override
  String get searchTooltip => '搜索（Ctrl+F）';
  @override
  String get settingsTooltip => '设置（Ctrl+,）';
}

// Path: search
class Translations$search$zh_CN extends Translations$search$zh_TW {
  Translations$search$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get hint => '搜索歌曲';
  @override
  String get clear => '清除';
  @override
  String get loadingSources => '正在加载音源';
  @override
  String get noSources => '没有可以搜索的音源';
  @override
  String get noSourcesHint => '安装支持搜索的插件后，就能在这里搜索';
  @override
  String get prompt => '输入关键词开始搜索';
  @override
  String get loading => '正在搜索';
  @override
  String noResults({required Object keyword}) => '找不到“${keyword}”的结果';
  @override
  String get failed => '搜索失败';
  @override
  String get retry => '重试';
  @override
  String get loadMore => '加载更多';
}

// Path: offline
class Translations$offline$zh_CN extends Translations$offline$zh_TW {
  Translations$offline$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get noInterface => '没有网络连接';
  @override
  String get unreachable => '无法连接网络';
  @override
  String get noInterfaceHint => '连接网络后重试';
  @override
  String get unreachableHint => '请检查网络连接后重试';
}

// Path: settings
class Translations$settings$zh_CN extends Translations$settings$zh_TW {
  Translations$settings$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '设置';
  @override
  String get appearance => '外观';
}

// Path: player
class Translations$player$zh_CN extends Translations$player$zh_TW {
  Translations$player$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get play => '播放';
  @override
  String get pause => '暂停';
  @override
  String get previous => '上一首';
  @override
  String get next => '下一首';
  @override
  String get playTooltip => '播放（空格键）';
  @override
  String get pauseTooltip => '暂停（空格键）';
  @override
  String get previousTooltip => '上一首（Ctrl+←）';
  @override
  String get nextTooltip => '下一首（Ctrl+→）';
  @override
  String get progress => '播放进度';
  @override
  String get loading => '正在加载';
}

// Path: appearance
class Translations$appearance$zh_CN extends Translations$appearance$zh_TW {
  Translations$appearance$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get theme => '主题';
  @override
  String get themeSystem => '跟随系统';
  @override
  String get themeLight => '浅色';
  @override
  String get themeDark => '深色';
  @override
  String get language => '语言';
  @override
  String get languageSystem => '跟随系统';
}

// Path: errors
class Translations$errors$zh_CN extends Translations$errors$zh_TW {
  Translations$errors$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get network => '网络连接失败，请检查网络后重试';
  @override
  String rateLimited({required Object source}) => '${source} 请求过于频繁，请稍后再试';
  @override
  String authRequired({required Object source}) => '需要登录 ${source}';
  @override
  String credentialInvalid({required Object source}) =>
      '${source} 的登录已失效，请重新登录';
  @override
  String verificationRequired({required Object source}) =>
      '${source} 要求验证：请登录、粘贴 Cookie 或稍后再试';
  @override
  String get unavailable => '无法获取此内容';
  @override
  String unavailableBecause({required Object reason}) => '无法获取：${reason}';
  @override
  String get notFound => '找不到内容，可能已失效';
  @override
  String parseError({required Object source}) => '${source} 的响应格式已变化，可能需要更新';
  @override
  String get unexpected => '发生意外错误';
  @override
  String get unknownSource => '音源';
  @override
  late final Translations$errors$unavailableReasons$zh_CN unavailableReasons =
      Translations$errors$unavailableReasons$zh_CN.internal(_root);
}

// Path: errors.unavailableReasons
class Translations$errors$unavailableReasons$zh_CN
    extends Translations$errors$unavailableReasons$zh_TW {
  Translations$errors$unavailableReasons$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get region => '所在地区不可用';
  @override
  String get copyright => '版权限制';
  @override
  String get membership => '需要会员';
  @override
  String get age => '有年龄限制';
  @override
  String get previewOnly => '仅可试听片段';
}
