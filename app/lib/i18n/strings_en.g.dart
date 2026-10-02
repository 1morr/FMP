///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

import 'package:intl/intl.dart';
import 'package:slang/generated.dart';

import 'strings.g.dart';

// Path: <root>
class TranslationsEn extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsEn({
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
             locale: AppLocale.en,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <en>.
  final TranslationMetadata<AppLocale, Translations> _meta;
  @override
  TranslationMetadata<AppLocale, Translations> get $meta => _meta;

  late final TranslationsEn _root = this; // ignore: unused_field

  @override
  TranslationsEn $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsEn(meta: meta ?? this.$meta);

  // Translations
  @override
  late final Translations$startup$en startup = Translations$startup$en._(_root);
  @override
  late final Translations$shell$en shell = Translations$shell$en._(_root);
  @override
  late final Translations$search$en search = Translations$search$en._(_root);
  @override
  late final Translations$offline$en offline = Translations$offline$en._(_root);
  @override
  late final Translations$settings$en settings = Translations$settings$en._(
    _root,
  );
  @override
  late final Translations$player$en player = Translations$player$en._(_root);
  @override
  late final Translations$appearance$en appearance =
      Translations$appearance$en._(_root);
  @override
  late final Translations$network$en network = Translations$network$en._(_root);
  @override
  late final Translations$errors$en errors = Translations$errors$en._(_root);
}

// Path: startup
class Translations$startup$en extends Translations$startup$zh_TW {
  Translations$startup$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get databaseError => 'Can\'t open the database';
  @override
  String get unsupportedPlatform => 'This platform isn\'t supported yet';
}

// Path: shell
class Translations$shell$en extends Translations$shell$zh_TW {
  Translations$shell$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get search => 'Search';
  @override
  String get settings => 'Settings';
  @override
  String get searchTooltip => 'Search (Ctrl+F)';
  @override
  String get settingsTooltip => 'Settings (Ctrl+,)';
}

// Path: search
class Translations$search$en extends Translations$search$zh_TW {
  Translations$search$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'Search songs';
  @override
  String get clear => 'Clear';
  @override
  String get loadingSources => 'Loading sources';
  @override
  String get noSources => 'No sources to search';
  @override
  String get noSourcesHint =>
      'Install a plugin that supports search to search here.';
  @override
  String get prompt => 'Type a keyword to search';
  @override
  String get loading => 'Searching';
  @override
  String noResults({required Object keyword}) => 'No results for “${keyword}”';
  @override
  String get failed => 'Search failed';
  @override
  String get retry => 'Retry';
  @override
  String get loadMore => 'Load more';
}

// Path: offline
class Translations$offline$en extends Translations$offline$zh_TW {
  Translations$offline$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get noInterface => 'No network connection';
  @override
  String get unreachable => 'Can\'t reach the network';
  @override
  String get noInterfaceHint => 'Connect to a network and try again.';
  @override
  String get unreachableHint => 'Check your connection and try again.';
}

// Path: settings
class Translations$settings$en extends Translations$settings$zh_TW {
  Translations$settings$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Settings';
  @override
  String get appearance => 'Appearance';
  @override
  String get network => 'Network';
  @override
  String get back => 'Back';
}

// Path: player
class Translations$player$en extends Translations$player$zh_TW {
  Translations$player$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get play => 'Play';
  @override
  String get pause => 'Pause';
  @override
  String get previous => 'Previous';
  @override
  String get next => 'Next';
  @override
  String get playTooltip => 'Play (Space)';
  @override
  String get pauseTooltip => 'Pause (Space)';
  @override
  String get previousTooltip => 'Previous (Ctrl+←)';
  @override
  String get nextTooltip => 'Next (Ctrl+→)';
  @override
  String get progress => 'Playback position';
  @override
  String get loading => 'Loading';
}

// Path: appearance
class Translations$appearance$en extends Translations$appearance$zh_TW {
  Translations$appearance$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get theme => 'Theme';
  @override
  String get themeSystem => 'System';
  @override
  String get themeLight => 'Light';
  @override
  String get themeDark => 'Dark';
  @override
  String get language => 'Language';
  @override
  String get languageSystem => 'System default';
}

// Path: network
class Translations$network$en extends Translations$network$zh_TW {
  Translations$network$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get cacheLimit => 'Cache limit';
  @override
  String cacheLimitDefault({required Object size}) => '${size} (default)';
  @override
  String get usage => 'Cache usage';
  @override
  String get artwork => 'Artwork';
  @override
  String get clear => 'Clear cache';
  @override
  String get clearTitle => 'Clear the cache?';
  @override
  String get clearBody =>
      'Cached artwork is deleted and downloaded again when needed. Your settings and data aren\'t affected.';
  @override
  String get cancel => 'Cancel';
  @override
  String get cleared => 'Cache cleared';
}

// Path: errors
class Translations$errors$en extends Translations$errors$zh_TW {
  Translations$errors$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get network =>
      'Network connection failed. Check your connection and try again.';
  @override
  String rateLimited({required Object source}) =>
      'Too many requests to ${source}. Try again later.';
  @override
  String authRequired({required Object source}) =>
      'Sign in to ${source} to continue.';
  @override
  String credentialInvalid({required Object source}) =>
      'Your sign-in to ${source} has expired. Sign in again.';
  @override
  String verificationRequired({required Object source}) =>
      'Verification required by ${source}. Sign in, paste a cookie, or try again later.';
  @override
  String get unavailable => 'This isn\'t available.';
  @override
  String unavailableBecause({required Object reason}) =>
      'Not available: ${reason}';
  @override
  String get notFound => 'Not found. It may have been removed.';
  @override
  String parseError({required Object source}) =>
      'The response format of ${source} changed. An update may be needed.';
  @override
  String get unexpected => 'Something went wrong.';
  @override
  String get unknownSource => 'the source';
  @override
  late final Translations$errors$unavailableReasons$en unavailableReasons =
      Translations$errors$unavailableReasons$en._(_root);
}

// Path: errors.unavailableReasons
class Translations$errors$unavailableReasons$en
    extends Translations$errors$unavailableReasons$zh_TW {
  Translations$errors$unavailableReasons$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get region => 'not offered in your region';
  @override
  String get copyright => 'copyright restriction';
  @override
  String get membership => 'membership required';
  @override
  String get age => 'age restricted';
  @override
  String get previewOnly => 'preview only';
}
