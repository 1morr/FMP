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
  late final Translations$history$en history = Translations$history$en._(_root);
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
  late final Translations$playback$en playback = Translations$playback$en._(
    _root,
  );
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
  @override
  String get history => 'History';
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
  @override
  String get more => 'More options';
  @override
  String get play => 'Play';
  @override
  String get playNext => 'Play next';
  @override
  String get addToQueue => 'Add to queue';
  @override
  String get addedToNext => 'Added to play next';
  @override
  String get addedToQueue => 'Added to queue';
}

// Path: history
class Translations$history$en extends Translations$history$zh_TW {
  Translations$history$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Play history';
  @override
  String get empty => 'No play history yet';
  @override
  String get emptyHint => 'Songs you have listened to show up here by date';
  @override
  String get today => 'Today';
  @override
  String get yesterday => 'Yesterday';
  @override
  String subtitle({required Object artist, required Object time}) =>
      '${artist} · ${time}';
  @override
  String get more => 'More options';
  @override
  String get play => 'Play';
  @override
  String get playNext => 'Play next';
  @override
  String get addToQueue => 'Add to queue';
  @override
  String get addedToNext => 'Added to play next';
  @override
  String get addedToQueue => 'Added to the queue';
  @override
  String get remove => 'Remove from history';
  @override
  String get clearAll => 'Clear all history';
  @override
  String get clearTitle => 'Clear all play history?';
  @override
  String get clearBody =>
      'Every play record is deleted and cannot be restored. The queue and settings are not affected.';
  @override
  String get cancel => 'Cancel';
  @override
  String get confirm => 'Clear';
  @override
  String get cleared => 'Play history cleared';
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
  @override
  String get playback => 'Playback';
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
  @override
  String get shuffle => 'Shuffle';
  @override
  String get loopOff => 'Repeat: off';
  @override
  String get loopAll => 'Repeat: all';
  @override
  String get loopOne => 'Repeat: one';
  @override
  String get more => 'More';
  @override
  String queueFull({required Object count}) =>
      'The queue is full (${count} songs at most); nothing was added';
  @override
  String get retrying => 'Retrying';
  @override
  String get waitingForNetwork => 'Waiting for the network';
  @override
  String get preview => 'Preview';
  @override
  String trackSkipped({required Object title, required Object reason}) =>
      'Skipped "${title}": ${reason}';
  @override
  String cannotPlay({required Object title, required Object reason}) =>
      'Can\'t play "${title}": ${reason}';
  @override
  String stoppedAfterFailures({required Object count}) =>
      '${count} songs in a row could not be played; playback stopped';
  @override
  String previewPlaying({required Object title}) =>
      'Only a preview of "${title}" is available';
  @override
  String get outputDeviceFailed =>
      'The audio output device is unavailable; playback paused';
  @override
  String get outputDeviceFellBack =>
      'The audio output device is unavailable; switched to the system default';
  @override
  String get shuffleTooltip => 'Shuffle (Ctrl+S)';
  @override
  String get loopOffTooltip => 'Repeat: off (Ctrl+R)';
  @override
  String get loopAllTooltip => 'Repeat: all (Ctrl+R)';
  @override
  String get loopOneTooltip => 'Repeat: one (Ctrl+R)';
  @override
  String get volume => 'Volume';
  @override
  String get volumeTooltip => 'Volume (Ctrl+↑/↓)';
  @override
  String get mute => 'Mute';
  @override
  String get unmute => 'Unmute';
  @override
  String get outputDevice => 'Output device';
  @override
  String get systemDefault => 'System default';
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

// Path: playback
class Translations$playback$en extends Translations$playback$zh_TW {
  Translations$playback$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get audioQuality => 'Audio quality';
  @override
  String get audioQualityHint => 'Applies to all sources';
  @override
  String get qualityHigh => 'High';
  @override
  String get qualityMedium => 'Medium';
  @override
  String get qualityLow => 'Low';
  @override
  String get formatPriority => 'Format preference';
  @override
  String get formatPriorityHint =>
      'Which format to pick when a source offers both';
  @override
  String get formatOpusFirst => 'Opus first';
  @override
  String get formatAacFirst => 'AAC first';
  @override
  String get rememberPosition => 'Remember playback position';
  @override
  String get rememberPositionHint =>
      'After a temporary play or reopening the app, the queue goes on from where it was';
  @override
  String get tempPlayRewind => 'Rewind when returning to the queue';
  @override
  String get tempPlayRewindHint =>
      'Go back a little from where the queue was, so it is easier to pick up';
  @override
  String get rewindNone => 'No rewind';
  @override
  String rewindSeconds({required Object seconds}) => '${seconds} s';
  @override
  String optionDefault({required Object label}) => '${label} (default)';
  @override
  String get skipPreviewClips => 'Skip preview clips';
  @override
  String get skipPreviewClipsHint =>
      'Skip songs that only have a preview clip; when off, play the preview and mark it';
  @override
  String get restartRewind => 'Rewind when restarting';
  @override
  String get restartRewindHint =>
      'After reopening the app, resume a little before where you left off';
  @override
  String get playHistoryLimit => 'Play history to keep';
  @override
  String get playHistoryLimitHint =>
      'Older records are deleted automatically; lowering the number deletes them right away';
  @override
  String playHistoryLimitOption({required Object count}) => '${count} entries';
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
