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
  late final Translations$home$en home = Translations$home$en._(_root);
  @override
  late final Translations$library$en library = Translations$library$en._(_root);
  @override
  late final Translations$playlist$en playlist = Translations$playlist$en._(
    _root,
  );
  @override
  late final Translations$selection$en selection = Translations$selection$en._(
    _root,
  );
  @override
  late final Translations$offline$en offline = Translations$offline$en._(_root);
  @override
  late final Translations$settings$en settings = Translations$settings$en._(
    _root,
  );
  @override
  late final Translations$about$en about = Translations$about$en._(_root);
  @override
  late final Translations$debug$en debug = Translations$debug$en._(_root);
  @override
  late final Translations$player$en player = Translations$player$en._(_root);
  @override
  late final Translations$playerPage$en playerPage =
      Translations$playerPage$en._(_root);
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
  late final Translations$radio$en radio = Translations$radio$en._(_root);
  @override
  late final Translations$sources$en sources = Translations$sources$en._(_root);
  @override
  late final Translations$plugins$en plugins = Translations$plugins$en._(_root);
  @override
  late final Translations$onboarding$en onboarding =
      Translations$onboarding$en._(_root);
  @override
  late final Translations$accounts$en accounts = Translations$accounts$en._(
    _root,
  );
  @override
  late final Translations$errors$en errors = Translations$errors$en._(_root);
  @override
  late final Translations$errorReport$en errorReport =
      Translations$errorReport$en._(_root);
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
  String get home => 'Home';
  @override
  String get library => 'Library';
  @override
  String get backTooltip => 'Back (Esc)';
  @override
  String get search => 'Search';
  @override
  String get settings => 'Settings';
  @override
  String get searchTooltip => 'Search (Ctrl+F)';
  @override
  String get settingsTooltip => 'Settings (Ctrl+,)';
  @override
  String get radio => 'Radio';
  @override
  String get panelTitle => 'Now playing';
  @override
  String get panelEmpty => 'Nothing is playing';
  @override
  String get panelCollapseTooltip => 'Collapse the now playing panel';
  @override
  String get panelShowTooltip => 'Show the now playing panel';
  @override
  String get panelHideTooltip => 'Hide the now playing panel';
  @override
  String get panelMenuItem => 'Now playing panel';
  @override
  String get panelResizeTooltip => 'Drag or press ←/→ to resize';
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
  String get roomHint => 'Search live rooms';
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
  String get playNextInMix => 'Play next (unavailable in a Mix)';
  @override
  String get addToQueueInMix => 'Add to queue (unavailable in a Mix)';
  @override
  String get startMix => 'Start Mix';
  @override
  String get addedToNext => 'Added to play next';
  @override
  String get addedToQueue => 'Added to queue';
  @override
  String get modeTracks => 'Songs';
  @override
  String get modeRooms => 'Live rooms';
  @override
  String get filterAll => 'All';
  @override
  String get filterLive => 'Live';
  @override
  String get filterOffline => 'Offline';
  @override
  String get listen => 'Listen';
  @override
  String get addToRadio => 'Add to Radio';
  @override
  String get showParts => 'Show parts';
  @override
  String get hideParts => 'Hide parts';
  @override
  String get loadingParts => 'Loading parts';
  @override
  String get partsFailed => 'Couldn’t load the parts';
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
  String get playNextInMix => 'Play next (unavailable in a Mix)';
  @override
  String get addToQueueInMix => 'Add to queue (unavailable in a Mix)';
  @override
  String get startMix => 'Start Mix';
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

// Path: home
class Translations$home$en extends Translations$home$zh_TW {
  Translations$home$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Home';
  @override
  String get recentlyPlayed => 'Recently played';
  @override
  String get myPlaylists => 'My playlists';
  @override
  String get radio => 'Radio';
  @override
  String get viewAll => 'View all';
  @override
  String get empty => 'Nothing here yet';
  @override
  String get emptyHint =>
      'Search for songs and play them, or import a playlist';
  @override
  String get more => 'More options';
  @override
  String get play => 'Play';
  @override
  String get playNext => 'Play next';
  @override
  String get addToQueue => 'Add to queue';
  @override
  String get playNextInMix => 'Play next (unavailable in a Mix)';
  @override
  String get addToQueueInMix => 'Add to queue (unavailable in a Mix)';
  @override
  String get startMix => 'Start Mix';
  @override
  String get addedToNext => 'Added to play next';
  @override
  String get addedToQueue => 'Added to the queue';
}

// Path: library
class Translations$library$en extends Translations$library$zh_TW {
  Translations$library$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Library';
  @override
  String get history => 'History';
  @override
  String get playlists => 'Playlists';
  @override
  String get newPlaylist => 'New playlist';
  @override
  String get empty => 'No playlists yet';
  @override
  String get emptyHint =>
      'Choose "New playlist" to create one, or "Import" to bring one in.';
  @override
  String trackCount({required Object count}) => '${count} songs';
  @override
  String get trackCountOne => '1 song';
  @override
  String get local => 'Local';
  @override
  String get more => 'More options';
  @override
  String get addToQueue => 'Add all to queue';
  @override
  String get shuffleToQueue => 'Shuffle into queue';
  @override
  String get addToQueueInMix => 'Add all to queue (unavailable in a Mix)';
  @override
  String get shuffleToQueueInMix => 'Shuffle into queue (unavailable in a Mix)';
  @override
  String addedToQueue({required Object name}) => 'Added "${name}" to the queue';
  @override
  String addFailed({required Object reason}) =>
      'Couldn\'t add to the queue: ${reason}';
  @override
  String get edit => 'Edit';
  @override
  String get delete => 'Delete';
  @override
  String get deleteTitle => 'Delete the playlist?';
  @override
  String deleteBody({required Object name}) =>
      '"${name}" is deleted and cannot be restored. The songs themselves and the play history are not affected.';
  @override
  String get deleted => 'Playlist deleted';
  @override
  String deleteFailed({required Object reason}) =>
      'Couldn\'t delete the playlist: ${reason}';
  @override
  String get createTitle => 'New playlist';
  @override
  String get editTitle => 'Edit playlist';
  @override
  String get name => 'Name';
  @override
  String get nameRequired => 'Enter a name';
  @override
  String get description => 'Description (optional)';
  @override
  String get cover => 'Cover';
  @override
  String get coverDefault => 'The cover of the first song';
  @override
  String get create => 'Create';
  @override
  String get save => 'Save';
  @override
  String get cancel => 'Cancel';
  @override
  String get created => 'Playlist created';
  @override
  String get saved => 'Playlist saved';
  @override
  String createFailed({required Object reason}) =>
      'Couldn\'t create the playlist: ${reason}';
  @override
  String saveFailed({required Object reason}) =>
      'Couldn\'t save the playlist: ${reason}';
  @override
  String get reorder => 'Drag to reorder';
  @override
  String reorderFailed({required Object reason}) =>
      'Couldn\'t reorder the playlists: ${reason}';
  @override
  String get coverCustom => 'A custom image';
  @override
  String get coverChooseCustom => 'Custom';
  @override
  String get coverUseDefault => 'Use default';
  @override
  String get coverUrl => 'Image URL';
  @override
  String get coverInvalidUrl => 'Enter a URL that starts with https';
  @override
  String get coverNotFromSource =>
      'This URL doesn\'t belong to any installed source';
  @override
  String get imported => 'Imported';
  @override
  String get mix => 'Mix';
  @override
  String get mixPlay => 'Mix play';
  @override
  String mixPlayDisabled({required Object reason}) => 'Mix play (${reason})';
  @override
  String get mixSeed => 'Starts from';
  @override
  String get mixUnsupported => 'This source doesn\'t support Mix';
  @override
  String get addToPlaylist => 'Add to playlist…';
  @override
  String get addToPlaylistTitle => 'Add to playlist';
  @override
  String get noLocalPlaylists => 'No local playlists yet';
  @override
  String get add => 'Add';
  @override
  String addedToPlaylist({required Object name}) => 'Added to "${name}"';
  @override
  String addedToPlaylists({required Object count}) =>
      'Added to ${count} playlists';
  @override
  String addToPlaylistFailed({required Object reason}) =>
      'Couldn\'t add to the playlist: ${reason}';
  @override
  String get importTooltip => 'Import a playlist';
  @override
  String get importTitle => 'Import a playlist';
  @override
  String get importUrlLabel => 'Link';
  @override
  String get importAction => 'Import';
  @override
  String get importLooking => 'Looking up the link…';
  @override
  String importProgress({required Object count}) => 'Songs read: ${count}';
  @override
  String get importUnrecognized =>
      'This link isn\'t recognized by any installed source';
  @override
  String get importUnsupported =>
      'Importing this kind of link isn\'t supported yet';
  @override
  String importFailed({required Object reason}) =>
      'Couldn\'t import: ${reason}';
  @override
  String get importDone => 'Playlist imported';
  @override
  String get importPartial =>
      'Imported, but only part of the playlist could be read. Refresh to read the rest.';
  @override
  String get refresh => 'Refresh';
  @override
  String get refreshing => 'Refreshing…';
  @override
  String get refreshed => 'Playlist refreshed';
  @override
  String get refreshedPartly =>
      'Only part of the playlist could be read; no songs were removed';
  @override
  String refreshFailed({required Object reason}) =>
      'Couldn\'t refresh the playlist: ${reason}';
  @override
  String get refreshOffline => 'Offline, couldn\'t refresh the playlist';
  @override
  String get refreshNoSource => 'This source can\'t refresh playlists';
  @override
  String statusRefreshed({required Object time}) => 'Last refreshed: ${time}';
  @override
  String statusPartial({required Object time}) =>
      'Last refreshed: partial · ${time}';
  @override
  String get statusNever => 'Not refreshed yet';
  @override
  String get statusFailed => 'Refresh failed';
  @override
  String get statusGone =>
      'Source gone: the remote playlist was deleted or is no longer accessible';
  @override
  String get statusAuth => 'Sign in to refresh this playlist';
  @override
  String get retry => 'Retry';
  @override
  String get useRemote => 'Use the remote\'s';
  @override
  String get useRemoteHint => 'Takes the remote\'s value on the next refresh';
  @override
  String get refreshInterval => 'Auto refresh';
  @override
  String get refreshIntervalOff => 'Off';
  @override
  String get refreshEveryHour => 'Every hour';
  @override
  String refreshEveryHours({required Object count}) => 'Every ${count} hours';
  @override
  String get refreshEveryDay => 'Every day';
  @override
  String refreshEveryDays({required Object count}) => 'Every ${count} days';
  @override
  String get addToRemote => 'Add to remote playlist…';
  @override
  String get addToRemoteMixed =>
      'Add to remote playlist (select songs from one source)';
  @override
  String get removeFromRemote => 'Remove from the remote playlist';
  @override
  String get remoteTitle => 'Add to remote playlist';
  @override
  String get remoteLoading => 'Loading your playlists';
  @override
  String get remoteLoadFailed => 'Couldn\'t load your playlists';
  @override
  String get remoteEmpty => 'No playlists you can add to yet';
  @override
  String get remoteNew => 'New playlist on the remote';
  @override
  String get remoteNewTitle => 'New remote playlist';
  @override
  String get remoteNewName => 'Name';
  @override
  String get remoteNewAction => 'Create';
  @override
  String remoteNewFailed({required Object reason}) =>
      'Couldn\'t create the playlist: ${reason}';
  @override
  String remoteAdded({required Object count}) => 'Added to ${count} playlists';
  @override
  String get remoteAddedOne => 'Added to 1 playlist';
  @override
  String remoteAlreadyThere({required Object count}) =>
      ', ${count} already there';
  @override
  String remoteFailedCount({required Object count}) => ', ${count} failed';
  @override
  String get remoteAddNone => 'Nothing was added';
  @override
  String remoteAddError({required Object reason}) =>
      'Couldn\'t add to the remote playlist: ${reason}';
  @override
  String get remoteDetailsTitle => 'What went wrong';
  @override
  String remoteDetailCount({required Object name, required Object count}) =>
      '${name}: ${count} failed';
  @override
  String get remoteNoReason => 'No reason was given';
  @override
  String get remoteClose => 'Close';
  @override
  String get removeRemoteTitle => 'Remove from the remote playlist?';
  @override
  String removeRemoteBody({
    required Object count,
    required Object name,
    required Object source,
  }) =>
      'Remove the selected songs (${count}) from "${name}"? The playlist on ${source} changes too. This cannot be undone.';
  @override
  String get removeRemoteConfirm => 'Remove';
  @override
  String removedFromRemote({required Object count}) =>
      'Removed ${count} from the remote playlist';
  @override
  String get removeRemoteNone => 'Nothing was removed';
  @override
  String removeRemoteFailed({required Object reason}) =>
      'Couldn\'t remove from the remote playlist: ${reason}';
}

// Path: playlist
class Translations$playlist$en extends Translations$playlist$zh_TW {
  Translations$playlist$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get more => 'More options';
  @override
  String get play => 'Play';
  @override
  String get playNext => 'Play next';
  @override
  String get addToQueue => 'Add to queue';
  @override
  String get playNextInMix => 'Play next (unavailable in a Mix)';
  @override
  String get addToQueueInMix => 'Add to queue (unavailable in a Mix)';
  @override
  String get startMix => 'Start Mix';
  @override
  String get addedToNext => 'Added to play next';
  @override
  String get addedToQueue => 'Added to the queue';
  @override
  String get remove => 'Remove from playlist';
  @override
  String removeFailed({required Object reason}) =>
      'Couldn\'t remove from the playlist: ${reason}';
  @override
  String get reorder => 'Drag to reorder';
  @override
  String reorderFailed({required Object reason}) =>
      'Couldn\'t reorder the songs: ${reason}';
  @override
  String get empty => 'This playlist has no songs yet';
  @override
  String get emptyHint => 'Choose "Add to playlist…" in a song\'s menu';
  @override
  String get notFound => 'This playlist no longer exists';
  @override
  String get unavailable => 'Unavailable';
  @override
  String get removeTitle => 'Remove the selected songs?';
  @override
  String removeBody({required Object count, required Object name}) =>
      'The selected songs (${count}) will be removed from "${name}". This cannot be undone.';
  @override
  String get removeConfirm => 'Remove';
  @override
  String get cancel => 'Cancel';
  @override
  String get removed => 'Removed from the playlist';
}

// Path: selection
class Translations$selection$en extends Translations$selection$zh_TW {
  Translations$selection$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get select => 'Select';
  @override
  String count({required Object count}) => '${count} selected';
  @override
  String get cancelTooltip => 'Cancel selection (Esc)';
  @override
  String get selectAllTooltip => 'Select all (Ctrl+A)';
  @override
  String get addToQueue => 'Add to queue';
  @override
  String get addToQueueInMix => 'Add to queue (unavailable in a Mix)';
  @override
  String get addToPlaylist => 'Add to playlist…';
  @override
  String get addedToQueue => 'Added to the queue';
  @override
  String get addToRemote => 'Add to remote playlist…';
  @override
  String get addToRemoteMixed =>
      'Add to remote playlist (select songs from one source)';
  @override
  String get removeFromRemote => 'Remove from the remote playlist';
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
  String get accounts => 'Accounts';
  @override
  String get appearance => 'Appearance';
  @override
  String get network => 'Network';
  @override
  String get back => 'Back';
  @override
  String get playback => 'Playback';
  @override
  String get plugins => 'Plugins';
  @override
  String get about => 'About';
  @override
  String get debug => 'Debug';
}

// Path: about
class Translations$about$en extends Translations$about$zh_TW {
  Translations$about$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get version => 'Version';
  @override
  String versionValue({required Object version, required Object flavor}) =>
      '${version} (${flavor})';
  @override
  String tapsLeft({required Object count}) =>
      'Taps left to turn on developer mode: ${count}';
  @override
  String get developerModeOn => 'Developer mode is on';
  @override
  String get alreadyDeveloper => 'Developer mode is already on';
}

// Path: debug
class Translations$debug$en extends Translations$debug$zh_TW {
  Translations$debug$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Debug';
  @override
  String get overview => 'Overview';
  @override
  String get developerMode => 'Developer mode';
  @override
  String get developerModeHint =>
      'Turning it off hides Debug from the settings and sets the log level back to the default';
  @override
  String get logLevel => 'Log level';
  @override
  String get logLevelInfo => 'info';
  @override
  String get logLevelDebug => 'debug';
  @override
  String get logLevelDebugHint =>
      'Records more detail, and the log files grow faster';
  @override
  String logLevelDefault({required Object level}) => '${level} (default)';
  @override
  String get app => 'App';
  @override
  String get version => 'Version';
  @override
  String get flavor => 'Flavor';
  @override
  String get platform => 'Platform';
  @override
  String get dataDirectory => 'Data directory';
  @override
  String get cacheUsage => 'Cache usage';
  @override
  String cacheUsageValue({required Object size}) =>
      '${size} · manage it in Settings › Network';
  @override
  String get diagnostics => 'Diagnostics';
  @override
  String get diagnosticsHint =>
      'A summary of this app\'s version, plugins and settings, plus the log files. Account names are left out.';
  @override
  String get diagnosticsCopy => 'Copy summary';
  @override
  String get diagnosticsSave => 'Save as file';
  @override
  String get diagnosticsShare => 'Share';
  @override
  String get diagnosticsCopied => 'Summary copied';
  @override
  String get exportSaved => 'Saved';
  @override
  String exportFailed({required Object message}) =>
      'Couldn\'t create the file: ${message}';
  @override
  String get exportReminderBody =>
      'The file holds this app\'s version, plugins, settings and recent log records. Cookies, tokens and signed URLs are masked and account names are left out, but check the content once more before you send it to anyone.';
  @override
  String get logExport => 'Export log files';
  @override
  String get logExportSave => 'Save as file';
  @override
  String get logExportShare => 'Share';
  @override
  String get log => 'Log & errors';
  @override
  String get network => 'Network';
  @override
  String get cancel => 'Cancel';
  @override
  String get logSearchHint => 'Search the log';
  @override
  String get filterLevelAll => 'All levels';
  @override
  String filterLevelFrom({required Object level}) => '${level} and above';
  @override
  String get filterTagAll => 'All tags';
  @override
  String get errorsOnly => 'Errors only';
  @override
  String get includeEarlier => 'Include earlier records';
  @override
  String get earlierLoading => 'Reading the log files';
  @override
  String get earlierFailed => 'Couldn\'t read the log files';
  @override
  String logCount({required Object shown, required Object total}) =>
      '${shown} of ${total} records';
  @override
  String get logEmpty => 'No records';
  @override
  String get logNoMatch => 'No records match the filters';
  @override
  String get logCopy => 'Copy filtered';
  @override
  String logCopied({required Object count}) => 'Copied ${count} records';
  @override
  String get logCopyNothing => 'Nothing to copy';
  @override
  String get logClear => 'Clear log';
  @override
  String get logClearTitle => 'Clear the log?';
  @override
  String get logClearBody =>
      'This deletes this run\'s records and the log files on this device. It can\'t be undone.';
  @override
  String get logCleared => 'Log cleared';
  @override
  String get logClearFailed => 'Couldn\'t delete the log files';
  @override
  String get netSearchHint => 'Search requests';
  @override
  String get netSourceAll => 'All sources';
  @override
  String get netSourceApp => 'App (no plugin)';
  @override
  String get netStatusAll => 'All statuses';
  @override
  String get netStatusFailed => 'Failed';
  @override
  String get netEmpty => 'No requests recorded';
  @override
  String get netEmptyHint =>
      'Requests the app sends during this run appear here.';
  @override
  String get netNoMatch => 'No requests match the filters';
  @override
  String netCount({required Object shown, required Object total}) =>
      '${shown} of ${total} requests';
  @override
  String get netUnknown => '—';
  @override
  String get netDetailUrl => 'URL';
  @override
  String get netDetailQuery => 'Query';
  @override
  String get netDetailNoQuery => 'None';
  @override
  String get netDetailStatus => 'Status';
  @override
  String get netDetailDuration => 'Duration';
  @override
  String get netDetailSize => 'Size';
  @override
  String get netDetailSource => 'Source';
  @override
  String get netDetailClient => 'Client';
  @override
  String get netDetailCredentials => 'Credentials attached';
  @override
  String get netDetailRetry => 'Retry';
  @override
  String get netDetailError => 'Error type';
  @override
  String get netDetailNoError => 'None';
  @override
  String get netDetailRelated => 'Matching error records';
  @override
  String get netDetailNoRelated => 'None';
  @override
  String get netDetailTime => 'Time';
  @override
  String get yes => 'Yes';
  @override
  String get no => 'No';
  @override
  String netDuration({required Object ms}) => '${ms} ms';
  @override
  String get close => 'Close';
  @override
  String get logDetail => 'Details';
  @override
  String get playback => 'Playback';
  @override
  String get database => 'Database';
  @override
  String get health => 'Source health check';
  @override
  String get hcHint =>
      'Runs each installed, enabled plugin\'s check cases over the real network (cases that need a login use the stored credentials). One plugin at a time.';
  @override
  String get hcAll => 'Check all';
  @override
  String get hcCheck => 'Check';
  @override
  String get hcChecking => 'Checking…';
  @override
  String get hcNone => 'No check cases';
  @override
  String get hcDisabled => 'Disabled';
  @override
  String hcCount({required Object count}) => 'Cases: ${count}';
  @override
  String get hcUnreadable => 'Check cases cannot be read';
  @override
  String get hcPassed => 'Passed';
  @override
  String get hcFailed => 'Failed';
  @override
  String get hcSkipped => 'Skipped (not logged in)';
  @override
  String get hcSkippedMutates => 'Skipped (changes the remote)';
  @override
  String hcProblem({required Object problem}) => 'Cannot check: ${problem}';
  @override
  String get hcNotLoaded =>
      'Cannot check: the plugin is not loaded (see the log)';
  @override
  String get hcEmpty => 'No plugins installed';
  @override
  String hcCase({
    required Object capability,
    required Object outcome,
    required Object ms,
  }) => '${capability} · ${outcome} · ${ms} ms';
  @override
  String hcErrorType({required Object type}) => 'Error type: ${type}';
  @override
  String get pluginDev => 'Plugin development';
  @override
  String get pdHint =>
      'Each plugin directory in the folder (one .js, checks.json, fixtures/) is loaded as "in development" and replaces the installed plugin with the same id; press Reload after editing. The mode only decides how a case runs, each in its own isolated environment (empty storage and credentials); everywhere else in the app a plugin in development always uses the real network.';
  @override
  String get pdFolder => 'Folder';
  @override
  String get pdNoFolder => 'No folder selected';
  @override
  String get pdPick => 'Choose folder';
  @override
  String get pdRescan => 'Rescan';
  @override
  String get pdUnload => 'Unload';
  @override
  String get pdApplying => 'Loading…';
  @override
  String get pdFolderMissing => 'The folder does not exist';
  @override
  String get pdFolderEmpty =>
      'The folder has no plugin directory (a folder with one .js file)';
  @override
  String pdDuplicateId({
    required Object first,
    required Object second,
    required Object id,
  }) =>
      '${first} and ${second} have the same plugin id "${id}"; only ${first} is loaded';
  @override
  String pdTagReplaces({required Object version}) =>
      'Replaces installed ${version}';
  @override
  String get pdTagFailed => 'Failed to load';
  @override
  String pdIdChanged({required Object id}) =>
      'The plugin id changed to "${id}"; rescan the folder';
  @override
  String get pdReplay => 'Replay';
  @override
  String get pdRecord => 'Record';
  @override
  String get pdReal => 'Real';
  @override
  String get pdReload => 'Reload';
  @override
  String get pdViewLog => 'View log';
  @override
  String get pdRunAll => 'Run all';
  @override
  String get pdRun => 'Run';
  @override
  String get pdRunning => 'Running';
  @override
  String get pdRecordWarning =>
      'Recording uses the real network; the files of that capability in fixtures/ are overwritten only when the result matches checks.json (hand-edited ones are skipped). Undo a bad recording with git checkout in the plugin folder.';
  @override
  String get pdNoCases => 'No check cases';
  @override
  String pdCaseLine({
    required Object outcome,
    required Object ms,
    required Object mode,
  }) => '${outcome} · ${ms} ms · ${mode}';
  @override
  String get pdPassed => 'Passed';
  @override
  String get pdFailed => 'Failed';
  @override
  String get pdSkippedLogin => 'Skipped: needs a login, not logged in';
  @override
  String get pdSkippedEdited => 'Skipped: the fixtures were edited by hand';
  @override
  String get pdSkippedMutates => 'Skipped: changes the remote';
  @override
  String get pdNotRun => 'Not run yet';
  @override
  String pdErrorType({required Object type}) => 'Error type: ${type}';
  @override
  String pdWritten({required Object count}) => 'Wrote ${count} fixture(s)';
  @override
  String get pdNotWritten => 'No fixtures written';
  @override
  String get pdValue => 'Return value';
  @override
  String get pdTruncated => '(too long, truncated)';
  @override
  String get pdCopy => 'Copy';
  @override
  String pdReloaded({required Object name, required Object version}) =>
      'Reloaded ${name} ${version}';
  @override
  String pdReloadFailed({required Object name}) => 'Reload failed: ${name}';
  @override
  String get pbEmpty => 'Nothing is playing';
  @override
  String get pbEmptyHint =>
      'Play something or queue a track and the backend, stream and queue show up here.';
  @override
  String get pbCopy => 'Copy snapshot';
  @override
  String get pbCopied => 'Snapshot copied';
  @override
  String get pbState => 'State';
  @override
  String get pbStateIdle => 'Idle';
  @override
  String get pbStateLoading => 'Loading';
  @override
  String get pbStatePlaying => 'Playing';
  @override
  String get pbStatePaused => 'Paused';
  @override
  String get pbStateBuffering => 'Buffering';
  @override
  String get pbStateRetrying => 'Waiting to retry';
  @override
  String get pbStateWaitingNetwork => 'Waiting for network';
  @override
  String get pbStateFailed => 'Stopped';
  @override
  String get pbError => 'Error type';
  @override
  String get pbRetryAttempt => 'Retry attempt';
  @override
  String get pbNextRetry => 'Next retry';
  @override
  String get pbTrack => 'Track';
  @override
  String get pbPlugin => 'Plugin';
  @override
  String get pbBackend => 'Backend';
  @override
  String get pbOutputDevice => 'Output device';
  @override
  String get pbOutputDefault => 'System default or not applicable';
  @override
  String get pbStream => 'Stream';
  @override
  String get pbSourceNetwork => 'network';
  @override
  String get pbSourceAsset => 'bundled asset';
  @override
  String pbCandidate({required Object index, required Object count}) =>
      'candidate ${index} / ${count}';
  @override
  String get pbUnknown => '—';
  @override
  String get pbPosition => 'Position';
  @override
  String get pbQueue => 'Queue';
  @override
  String get pbQueueEmpty => 'The queue is empty';
  @override
  String pbQueueSummary({required Object total, required Object index}) =>
      '${total} tracks, current is #${index}';
  @override
  String get pbBefore => 'Before';
  @override
  String get pbAfter => 'After';
  @override
  String get pbNone => 'none';
  @override
  String get pbShuffle => 'Shuffle';
  @override
  String get pbLoop => 'Repeat';
  @override
  String get pbLoopOff => 'off';
  @override
  String get pbLoopAll => 'all';
  @override
  String get pbLoopOne => 'one';
  @override
  String get pbTemporary =>
      'Temporary play (the current index is where the queue resumes)';
  @override
  String get pbLive =>
      'Listening to a live room (returns to the queue when stopped)';
  @override
  String get pbLiveRoom => 'Live room';
  @override
  String get pbMix => 'Mix';
  @override
  String get dbTables => 'Tables';
  @override
  String dbRowCount({required Object count}) => '${count} rows';
  @override
  String get dbBack => 'Back to the table list';
  @override
  String dbPage({
    required Object page,
    required Object pages,
    required Object total,
  }) => 'Page ${page} / ${pages}, ${total} rows';
  @override
  String get dbPrevious => 'Previous page';
  @override
  String get dbNext => 'Next page';
  @override
  String get dbNoRows => 'This table is empty';
  @override
  String get dbNull => 'NULL';
  @override
  String get dbLoadFailed => 'Could not read the database';
  @override
  String get dbCheck => 'Check';
  @override
  String get dbChecking => 'Checking…';
  @override
  String get dbCheckClean => 'No problems found';
  @override
  String get dbCheckProblems => 'Problems found';
  @override
  String get dbIntegrity => 'Integrity (integrity_check)';
  @override
  String get dbForeignKeys => 'Foreign keys (foreign_key_check)';
  @override
  String get dbOk => 'OK';
  @override
  String dbViolation({
    required Object table,
    required Object rowId,
    required Object parent,
  }) => '${table} rowid ${rowId} has no matching row in ${parent}';
  @override
  String get dbOrphans => 'Orphan tracks';
  @override
  String dbOrphansValue({required Object count}) =>
      '${count} (removed automatically at startup, not damage)';
  @override
  String get dbCheckFailed => 'The check failed';
  @override
  String get reset => 'Reset data';
  @override
  String get resetBody =>
      'Clears the database (settings, playlists, queue and play history), every source\'s login credentials, the login web view data and the cache, then restarts the app. Log files, backups and downloaded files are left alone.';
  @override
  String get resetBackupNote =>
      'The database is backed up to the backups folder in the data directory first; if the backup fails nothing is cleared. Credentials are not in the backup, so you sign in again after restoring.';
  @override
  String get resetButton => 'Reset data…';
  @override
  String resetBackupFailed({required Object message}) =>
      'Could not back up the database, nothing was cleared: ${message}';
  @override
  String get resetConfirmTitle => 'Reset all data?';
  @override
  String resetConfirmBody({required Object path}) =>
      'The database was backed up to ${path}. "Clear and restart" clears the database, credentials, login web view data and cache, and cannot be undone except through that backup.';
  @override
  String get resetRestartsItself => 'The app restarts by itself afterwards.';
  @override
  String get resetRestartsManually =>
      'The app closes afterwards; open it again yourself.';
  @override
  String get resetUnderstand => 'I understand this clears all data';
  @override
  String get resetConfirm => 'Clear and restart';
  @override
  String get resetWorking => 'Clearing…';
  @override
  String resetFailed({required Object message}) =>
      'The reset did not finish: ${message}';
  @override
  String get dbBackUp => 'Back up now';
  @override
  String dbBackedUp({required Object path}) => 'Backed up to ${path}';
  @override
  String dbBackUpFailed({required Object message}) =>
      'Could not back up the database: ${message}';
  @override
  String get dbRestore => 'Restore from backup';
  @override
  String get dbRestoreTitle => 'Choose a backup to restore';
  @override
  String get dbRestoreEmpty =>
      'There are no backups. Press "Back up now"; resetting data also creates one.';
  @override
  String dbRestoreListFailed({required Object message}) =>
      'Could not read the backup list: ${message}';
  @override
  String get dbRestoreConfirmTitle => 'Restore from this backup?';
  @override
  String dbRestoreConfirmBody({required Object time}) =>
      'Backup time: ${time}. The current database is renamed and kept in the data directory (fmp.db.before-restore-…) and replaced by this backup. Backups do not contain login credentials, so you sign in again afterwards.';
  @override
  String get dbRestoreConfirm => 'Restore and restart';
  @override
  String get dbRestoreWorking => 'Restoring…';
  @override
  String dbRestoreFailed({required Object message}) =>
      'The restore did not finish: ${message}';
  @override
  String get dbCheckProblemsActions =>
      'You can restore from a backup or reset the data.';
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
  String get shuffleInMixTooltip => 'Shuffle is unavailable in a Mix';
  @override
  String get shuffleInMix => 'Shuffle (unavailable in a Mix)';
  @override
  String get loopOffTooltip => 'Repeat: off (Ctrl+R)';
  @override
  String get loopAllTooltip => 'Repeat: all (Ctrl+R)';
  @override
  String get loopOneTooltip => 'Repeat: one (Ctrl+R)';
  @override
  String get loopOffInMix => 'Repeat: off (no "all" in a Mix)';
  @override
  String get loopOneInMix => 'Repeat: one (no "all" in a Mix)';
  @override
  String get loopOffInMixTooltip => 'Repeat: off (Ctrl+R; no "all" in a Mix)';
  @override
  String get loopOneInMixTooltip => 'Repeat: one (Ctrl+R; no "all" in a Mix)';
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
  @override
  String get liveBadge => 'Live';
  @override
  String get liveEnded => 'Live ended';
  @override
  String get liveStatusFailed => 'Status check failed';
  @override
  String get liveStopped => 'Stopped';
  @override
  String get liveReconnecting => 'Reconnecting';
  @override
  String liveCannotPlay({required Object reason}) => 'Can\'t play: ${reason}';
  @override
  String liveListened({required Object time}) => 'Listened ${time}';
  @override
  String liveOnline({required Object count}) => '${count} watching';
  @override
  String get stopLive => 'Stop listening';
  @override
  String get liveHost => 'Host';
  @override
  String get liveViewers => 'Viewers';
}

// Path: playerPage
class Translations$playerPage$en extends Translations$playerPage$zh_TW {
  Translations$playerPage$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get openHint => 'Open the player';
  @override
  String get closeTooltip => 'Close the player (Esc)';
  @override
  String get showLyricsTooltip => 'Show lyrics (Ctrl+L)';
  @override
  String get showArtworkTooltip => 'Show artwork';
  @override
  String get tabLyrics => 'Lyrics';
  @override
  String get tabQueue => 'Queue';
  @override
  String get tabDetails => 'Details';
  @override
  String get noLyrics => 'No lyrics';
  @override
  String get speed => 'Playback speed';
  @override
  String speedValue({required Object speed}) => '${speed}×';
  @override
  String get detailsUploader => 'Uploader';
  @override
  String get detailsDuration => 'Duration';
  @override
  String get detailsSource => 'Source';
  @override
  String get detailsPublished => 'Published';
  @override
  String get detailsAlbum => 'Album';
  @override
  String get detailsDescription => 'Description';
  @override
  String get detailsExpand => 'Show more';
  @override
  String get detailsCollapse => 'Show less';
  @override
  String get detailsLoading => 'Loading details';
  @override
  String get detailsFailed => 'Could not load the details';
  @override
  String get detailsRetry => 'Retry';
  @override
  String get statView => 'Views';
  @override
  String get statLike => 'Likes';
  @override
  String get statFavorite => 'Favorites';
  @override
  String get statComment => 'Comments';
  @override
  String get statShare => 'Shares';
  @override
  String get statDanmaku => 'Danmaku';
  @override
  String get statCoin => 'Coins';
  @override
  String get queueTooltip => 'Queue (Ctrl+Q)';
  @override
  String queueCount({required Object count}) => '${count} in queue';
  @override
  String get queueShuffleNote =>
      'The shuffle order follows positions; dragging only swaps songs, not the order';
  @override
  String queueMixNote({required Object title}) => 'Mix: ${title}';
  @override
  String get queueStartMix => 'Start Mix';
  @override
  String get queueClear => 'Clear the queue';
  @override
  String get queueClearTitle => 'Clear the queue?';
  @override
  String get queueClearBody =>
      'Every song in the queue is removed and playback stops. Play history and settings are not affected.';
  @override
  String get queueClearConfirm => 'Clear';
  @override
  String get queueCancel => 'Cancel';
  @override
  String get queueCleared => 'Queue cleared';
  @override
  String get queueMore => 'More options';
  @override
  String get queuePlayNext => 'Play next';
  @override
  String get queueRemove => 'Remove from queue';
  @override
  String get queueReorder => 'Drag to reorder';
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
  @override
  String get autoScrollToCurrent =>
      'Scroll to the current song when it changes';
  @override
  String get autoScrollToCurrentHint =>
      'While the queue list is open, it scrolls to the song that starts playing';
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
  @override
  String get radioInterval => 'Radio status refresh';
  @override
  String get radioIntervalHint =>
      'How often stations are checked for going live; not while FMP is in the background or offline.';
  @override
  String get radioIntervalOff => 'Off';
  @override
  String radioIntervalMinutes({required Object minutes}) => '${minutes} min';
  @override
  String get chartInterval => 'Charts refresh';
  @override
  String get chartIntervalHint =>
      'How often the charts on Home are updated; not while FMP is in the background or offline.';
  @override
  String get chartIntervalOff => 'Off';
  @override
  String chartIntervalMinutes({required Object minutes}) => '${minutes} min';
  @override
  String optionDefault({required Object label}) => '${label} (default)';
}

// Path: radio
class Translations$radio$en extends Translations$radio$zh_TW {
  Translations$radio$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Radio';
  @override
  String get addFromUrl => 'Add from a URL';
  @override
  String get refresh => 'Refresh status';
  @override
  String get urlTitle => 'Add a station from a URL';
  @override
  String get urlLabel => 'Live room URL';
  @override
  String get add => 'Add';
  @override
  String get cancel => 'Cancel';
  @override
  String get added => 'Added to Radio';
  @override
  String get alreadyAdded => 'Already in your stations';
  @override
  String get unrecognizedUrl => 'This URL isn\'t recognized';
  @override
  String addFailed({required Object reason}) =>
      'Couldn\'t add the station: ${reason}';
  @override
  String get refreshed => 'Station status updated';
  @override
  String get nothingToRefresh => 'No stations to refresh';
  @override
  String refreshFailed({required Object reason}) =>
      'Couldn\'t refresh the status: ${reason}';
  @override
  String get refreshOffline =>
      'Offline, not refreshed: showing the last known status';
  @override
  String get retry => 'Retry';
  @override
  String get working => 'Working';
  @override
  String get empty => 'No stations yet';
  @override
  String get emptyHint =>
      'On the Search page, switch to "Live rooms" and choose "Add to Radio" from a result\'s menu, or add a live room by its URL.';
  @override
  String get statusLive => 'Live';
  @override
  String get statusOffline => 'Offline';
  @override
  String get statusFailed => 'Check failed';
  @override
  String get statusUnchecked => 'Not checked yet';
  @override
  String get more => 'More options';
  @override
  String get remove => 'Remove';
  @override
  String get removeTitle => 'Remove the station?';
  @override
  String removeBody({required Object title}) =>
      '"${title}" is removed from your stations.';
  @override
  String get removed => 'Station removed';
  @override
  String removeFailed({required Object reason}) =>
      'Couldn\'t remove the station: ${reason}';
  @override
  String get reorder => 'Drag to reorder';
  @override
  String reorderFailed({required Object reason}) =>
      'Couldn\'t reorder the stations: ${reason}';
  @override
  String cannotPlay({required Object reason}) => 'Can\'t play: ${reason}';
}

// Path: sources
class Translations$sources$en extends Translations$sources$zh_TW {
  Translations$sources$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get notInstalled => 'Source not installed';
  @override
  String get disabled => 'Source disabled';
}

// Path: plugins
class Translations$plugins$en extends Translations$plugins$zh_TW {
  Translations$plugins$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get tabInstalled => 'Installed';
  @override
  String get tabAvailable => 'Available';
  @override
  String get checkUpdates => 'Check for updates';
  @override
  String get updateAll => 'Update all';
  @override
  String get more => 'More options';
  @override
  String get installFromFile => 'Install from file';
  @override
  String get installFromUrl => 'Install from URL';
  @override
  String get manageIndexes => 'Manage repositories';
  @override
  String get working => 'Working';
  @override
  String get noneInstalled => 'No plugins installed';
  @override
  String get noneInstalledHint =>
      'Pick plugins to install in the Available tab.';
  @override
  String versionAuthor({required Object version, required Object author}) =>
      '${version} · ${author}';
  @override
  String get tagDisabled => 'Disabled';
  @override
  String get tagUnresponsive => 'Not responding';
  @override
  String get tagUpdate => 'Update available';
  @override
  String get tagInstalled => 'Installed';
  @override
  String get tagDev => 'In development';
  @override
  String get devManaged =>
      'A plugin in development is managed in Debug > Plugin development; unload it to enable, update or remove it.';
  @override
  String enable({required Object name}) => 'Enable ${name}';
  @override
  String get showDetails => 'Details';
  @override
  String get hideDetails => 'Hide details';
  @override
  String get capabilities => 'Capabilities';
  @override
  String get hosts => 'Sites it connects to';
  @override
  String get source => 'Source';
  @override
  String get listSeparator => ', ';
  @override
  String get sourceOfficial => 'Official repository';
  @override
  String sourceCustom({required Object url}) => 'Custom repository: ${url}';
  @override
  String get sourceLocal => 'Installed from a file or URL';
  @override
  String get customIndex => 'Custom repository';
  @override
  String updateTo({required Object version}) => 'Update to ${version}';
  @override
  String get needsAppUpdate => 'Requires a newer FMP';
  @override
  String get remove => 'Remove';
  @override
  String get install => 'Install';
  @override
  String installTitle({required Object name}) => 'Install ${name}?';
  @override
  String get installAllTitle => 'Install these plugins?';
  @override
  String updateTitle({required Object name}) => 'Update ${name}?';
  @override
  String byline({required Object author, required Object version}) =>
      'By ${author} · version ${version}';
  @override
  String get addedAccess =>
      'The new version asks for more than the installed one. It is only updated after you confirm.';
  @override
  String get addedCapabilities => 'New capabilities';
  @override
  String get addedHosts => 'New sites';
  @override
  String get loginWarning =>
      'This script will access these sites as you, with your sign-in.';
  @override
  String get unofficial =>
      'Unofficial source: FMP hasn\'t reviewed this plugin.';
  @override
  String replaces({required Object version}) =>
      'It replaces the installed version ${version}.';
  @override
  String get cancel => 'Cancel';
  @override
  String get confirmInstall => 'Install';
  @override
  String get confirmUpdate => 'Update';
  @override
  String removeTitle({required Object name}) => 'Remove ${name}?';
  @override
  String get removeBody =>
      'The plugin, its data, its sign-in and its cache are deleted. Songs stay and show "Source not installed".';
  @override
  String get confirmRemove => 'Remove';
  @override
  String installed({required Object name}) => 'Installed ${name}';
  @override
  String updated({required Object name, required Object version}) =>
      'Updated ${name} to ${version}';
  @override
  String updatedCount({required Object count}) => 'Plugins updated: ${count}';
  @override
  String removed({required Object name}) => 'Removed ${name}';
  @override
  String get upToDate => 'All plugins are up to date';
  @override
  String updatesFound({required Object count}) => 'Updates available: ${count}';
  @override
  String get checkFailed =>
      'Some repositories couldn\'t be read; there may be more updates';
  @override
  String get hashMismatch =>
      'The repository was just updated. Try again later.';
  @override
  String get manifestMismatch =>
      'The plugin file doesn\'t match the repository; nothing was installed';
  @override
  String get appUpdateRequired => 'This plugin requires a newer FMP';
  @override
  String installFailed({required Object name, required Object reason}) =>
      'Couldn\'t install ${name}: ${reason}';
  @override
  String installFileFailed({required Object reason}) =>
      'Couldn\'t install the plugin: ${reason}';
  @override
  String updateFailed({required Object name, required Object reason}) =>
      'Couldn\'t update ${name}: ${reason}';
  @override
  String removeFailed({required Object name, required Object reason}) =>
      'Couldn\'t remove ${name}: ${reason}';
  @override
  String enableFailed({required Object name, required Object reason}) =>
      'Couldn\'t enable ${name}: ${reason}';
  @override
  String disableFailed({required Object name, required Object reason}) =>
      'Couldn\'t disable ${name}: ${reason}';
  @override
  String get indexLoadFailed => 'Couldn\'t read this repository';
  @override
  String get indexNeedsAppUpdate => 'This repository requires a newer FMP';
  @override
  String get indexEmpty => 'This repository has no plugins';
  @override
  String get allFailed => 'Couldn\'t read the plugin repositories';
  @override
  String get retry => 'Retry';
  @override
  String get urlLabel => 'Plugin file URL (https)';
  @override
  String get urlInvalid => 'Enter a URL that starts with https';
  @override
  String get download => 'Download';
  @override
  String get indexesTitle => 'Plugin repositories';
  @override
  String get addIndex => 'Add repository';
  @override
  String get indexUrlLabel => 'index.json URL (https)';
  @override
  String get indexWarning =>
      'Unofficial source: FMP hasn\'t reviewed the plugins in this list.';
  @override
  String get add => 'Add';
  @override
  String get removeIndex => 'Remove this repository';
  @override
  String get indexAdded => 'Repository added';
  @override
  String get indexRemoved => 'Repository removed';
  @override
  String get indexExists => 'This repository is already listed';
  @override
  String get close => 'Close';
  @override
  late final Translations$plugins$capabilityNames$en capabilityNames =
      Translations$plugins$capabilityNames$en._(_root);
}

// Path: onboarding
class Translations$onboarding$en extends Translations$onboarding$zh_TW {
  Translations$onboarding$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Install plugins to start searching';
  @override
  String get body =>
      'Plugins connect FMP to music sources. Pick the ones you want; you can change this any time in Settings > Plugins.';
  @override
  String get later => 'Later';
  @override
  String get goToPlugins => 'Go to plugins';
  @override
  String get loading => 'Loading plugins';
  @override
  String installedCount({required Object count}) =>
      'Plugins installed: ${count}';
  @override
  String get failedTitle => 'Some plugins weren\'t installed';
}

// Path: accounts
class Translations$accounts$en extends Translations$accounts$zh_TW {
  Translations$accounts$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'No sources to sign in to';
  @override
  String get noneHint =>
      'Install a plugin that supports sign-in, then sign in here.';
  @override
  String get goToPlugins => 'Go to plugins';
  @override
  String get loadFailed => 'Couldn\'t read the accounts';
  @override
  String get working => 'Working';
  @override
  String get notLoggedIn => 'Not signed in';
  @override
  String get statusActive => 'Active';
  @override
  String get statusInvalidated => 'Expired';
  @override
  String get statusUnreadable => 'Temporarily unreadable, retrying soon';
  @override
  String get browseAsLoggedIn => 'Browse and play while signed in';
  @override
  String get automationRisk =>
      'Many requests while signed in may be treated as automated (unconfirmed)';
  @override
  String get loginQr => 'Sign in with QR code';
  @override
  String get loginWebView => 'Sign in on the web';
  @override
  String get loginCookie => 'Paste cookies';
  @override
  String get relogin => 'Sign in again';
  @override
  String get signIn => 'Sign in';
  @override
  String invalidatedPrompt({required Object name}) =>
      'The sign-in to ${name} is no longer valid';
  @override
  String lastRefresh({required Object time, required Object result}) =>
      'Last refreshed: ${time}, ${result}';
  @override
  String get refreshRefreshed => 'credentials renewed';
  @override
  String get refreshUnchanged => 'no change needed';
  @override
  String get refreshFailed => 'failed';
  @override
  String get logout => 'Sign out';
  @override
  String noMethod({required Object name}) =>
      'Signing in to ${name} isn\'t available on this platform yet';
  @override
  String logoutTitle({required Object name}) => 'Sign out of ${name}?';
  @override
  String get logoutBody =>
      'FMP deletes its sign-in data for this source. The "Browse and play while signed in" setting stays.';
  @override
  String get confirmLogout => 'Sign out';
  @override
  String get cancel => 'Cancel';
  @override
  String loggedIn({required Object name}) => 'Signed in to ${name}';
  @override
  String loggedOut({required Object name}) => 'Signed out of ${name}';
  @override
  String loginFailed({required Object name, required Object reason}) =>
      'Couldn\'t sign in to ${name}: ${reason}';
  @override
  String logoutFailed({required Object name, required Object reason}) =>
      'Couldn\'t sign out of ${name}: ${reason}';
  @override
  String settingFailed({required Object reason}) =>
      'Couldn\'t save the setting: ${reason}';
  @override
  String qrTitle({required Object name}) => 'Sign in to ${name} with a QR code';
  @override
  String get qrImage => 'Sign-in QR code';
  @override
  String get qrStarting => 'Creating the QR code';
  @override
  String get qrWaiting => 'Scan the QR code with the app on your phone';
  @override
  String get qrScanned => 'Scanned. Confirm on your phone';
  @override
  String get qrExpired => 'The QR code has expired';
  @override
  String get verifying => 'Checking the sign-in';
  @override
  String get qrRegenerate => 'New QR code';
  @override
  String get retry => 'Retry';
  @override
  String get close => 'Close';
  @override
  String webTitle({required Object name}) => 'Sign in to ${name}';
  @override
  String get webLoading => 'Opening the sign-in page';
  @override
  String get webStuckTitle => 'The sign-in didn\'t finish';
  @override
  String get webStuckBody =>
      'The page stopped while redirecting. Retry opens the sign-in page again; you usually won\'t need to enter your password again.';
  @override
  String get webStuckRestart =>
      'It still didn\'t finish. Close FMP, open it again and choose "Sign in on the web" once more; the sign-in on the web is kept.';
  @override
  String get webFailed => 'Couldn\'t open the sign-in page';
  @override
  String cookieTitle({required Object name}) => 'Paste cookies for ${name}';
  @override
  String get cookieLabel => 'Cookies';
  @override
  String get cookieHint => 'name=value; name2=value2';
  @override
  String get cookieHelpTitle => 'How to get them';
  @override
  String get cookieStep1 =>
      'Sign in to the website in a browser on your computer.';
  @override
  String get cookieStep2 =>
      'Press F12 to open the developer tools, reload the page in the Network tab and pick a request to that website.';
  @override
  String get cookieStep3 =>
      'Find "Cookie" in the request headers, copy the whole value and paste it above.';
  @override
  String get cookieFile =>
      'You can also paste a cookies.txt file (Netscape format) exported by a browser extension.';
  @override
  String get cookieWarning =>
      'Cookies are your sign-in. Don\'t share them. FMP keeps them only on this device.';
  @override
  String get cookieEmpty =>
      'No cookies found. Paste name=value pairs or the contents of a cookies.txt file.';
  @override
  String cookieRejected({required Object name}) =>
      '${name} didn\'t accept these cookies. Copy them again from a page where you\'re signed in.';
  @override
  String loginRejected({required Object name}) =>
      '${name} didn\'t accept the sign-in. Try again.';
  @override
  String get playlists => 'Playlists';
  @override
  String playlistsTitle({required Object name}) => '${name} playlists';
  @override
  String get playlistsEmpty => 'This account has no playlists yet';
  @override
  String get playlistsFailed => 'Couldn\'t read the playlists';
  @override
  String get playlistWritable => 'Writable';
  @override
  String get playlistImported => 'Imported';
  @override
  String playlistSelect({required Object name}) => 'Select "${name}"';
  @override
  String importSelected({required Object count}) =>
      'Import selected (${count})';
  @override
  String importingProgress({required Object done, required Object total}) =>
      'Importing ${done}/${total}';
  @override
  String playlistImportFailed({required Object reason}) =>
      'Import failed: ${reason}';
  @override
  String get playlistUnsupported => 'This source can\'t import playlists yet';
  @override
  String importedCount({required Object count}) =>
      'Playlists imported: ${count}';
  @override
  String importedWithFailures({
    required Object count,
    required Object failed,
  }) => 'Playlists imported: ${count}, failed: ${failed}';
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

// Path: errorReport
class Translations$errorReport$en extends Translations$errorReport$zh_TW {
  Translations$errorReport$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Error details';
  @override
  String get actionDetail => 'Details';
  @override
  String get actionReport => 'Report';
  @override
  String get copy => 'Copy';
  @override
  String get copied => 'Copied';
  @override
  String get reportOnGitHub => 'Report on GitHub';
  @override
  String get reportCopied =>
      'Report copied. Paste it into the "Error report" field on GitHub.';
  @override
  String get openFailed =>
      'Could not open the browser. Open the address below yourself.';
  @override
  String get manualHint =>
      'Open this address in a browser and paste the copied report.';
  @override
  String get reminderTitle => 'Check before you submit';
  @override
  String get reminderBody =>
      'The FMP repository on GitHub is public, so anyone can read the report. Cookies, tokens and signed URLs are masked, but check the content once more before you submit.';
  @override
  String get reminderDontAsk => 'Don\'t remind me again';
  @override
  String get reminderContinue => 'Continue';
  @override
  String get cancel => 'Cancel';
  @override
  String get time => 'Time';
  @override
  String get type => 'Error type';
  @override
  String get reason => 'Reason';
  @override
  String get source => 'Source';
  @override
  String get action => 'Action';
  @override
  String get module => 'Module';
  @override
  String get request => 'Request';
  @override
  String get status => 'Status';
  @override
  String get duration => 'Duration';
  @override
  String get requestError => 'Request error';
  @override
  String get noRequest => 'No matching request record';
  @override
  String get app => 'App';
  @override
  String get system => 'System';
  @override
  String get cause => 'Cause';
  @override
  String get stackTrace => 'Stack trace';
}

// Path: plugins.capabilityNames
class Translations$plugins$capabilityNames$en
    extends Translations$plugins$capabilityNames$zh_TW {
  Translations$plugins$capabilityNames$en._(TranslationsEn root)
    : this._root = root,
      super.internal(root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get search => 'Search';
  @override
  String get resolveStream => 'Playback';
  @override
  String get trackDetail => 'Track details';
  @override
  String get multiPart => 'Multi-part videos';
  @override
  String get importPlaylist => 'Playlist import';
  @override
  String get libraryRead => 'Read your library';
  @override
  String get libraryWrite => 'Change your library';
  @override
  String get charts => 'Charts';
  @override
  String get live => 'Live streams';
  @override
  String get mix => 'Mix';
  @override
  String get lyrics => 'Lyrics';
  @override
  String get login => 'Sign-in';
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
