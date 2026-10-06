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
  late final Translations$shell$zh_TW shell = Translations$shell$zh_TW.internal(
    _root,
  );
  late final Translations$search$zh_TW search =
      Translations$search$zh_TW.internal(_root);
  late final Translations$offline$zh_TW offline =
      Translations$offline$zh_TW.internal(_root);
  late final Translations$settings$zh_TW settings =
      Translations$settings$zh_TW.internal(_root);
  late final Translations$player$zh_TW player =
      Translations$player$zh_TW.internal(_root);
  late final Translations$appearance$zh_TW appearance =
      Translations$appearance$zh_TW.internal(_root);
  late final Translations$playback$zh_TW playback =
      Translations$playback$zh_TW.internal(_root);
  late final Translations$network$zh_TW network =
      Translations$network$zh_TW.internal(_root);
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

// Path: shell
class Translations$shell$zh_TW {
  Translations$shell$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '搜尋'
  String get search => '搜尋';

  /// zh-TW: '設定'
  String get settings => '設定';

  /// zh-TW: '搜尋（Ctrl+F）'
  String get searchTooltip => '搜尋（Ctrl+F）';

  /// zh-TW: '設定（Ctrl+,）'
  String get settingsTooltip => '設定（Ctrl+,）';
}

// Path: search
class Translations$search$zh_TW {
  Translations$search$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '搜尋歌曲'
  String get hint => '搜尋歌曲';

  /// zh-TW: '清除'
  String get clear => '清除';

  /// zh-TW: '正在載入音源'
  String get loadingSources => '正在載入音源';

  /// zh-TW: '沒有可以搜尋的音源'
  String get noSources => '沒有可以搜尋的音源';

  /// zh-TW: '安裝支援搜尋的插件後，就能在這裡搜尋'
  String get noSourcesHint => '安裝支援搜尋的插件後，就能在這裡搜尋';

  /// zh-TW: '輸入關鍵字開始搜尋'
  String get prompt => '輸入關鍵字開始搜尋';

  /// zh-TW: '搜尋中'
  String get loading => '搜尋中';

  /// zh-TW: '找不到「{keyword}」的結果'
  String noResults({required Object keyword}) => '找不到「${keyword}」的結果';

  /// zh-TW: '搜尋失敗'
  String get failed => '搜尋失敗';

  /// zh-TW: '重試'
  String get retry => '重試';

  /// zh-TW: '載入更多'
  String get loadMore => '載入更多';

  /// zh-TW: '更多選項'
  String get more => '更多選項';

  /// zh-TW: '播放'
  String get play => '播放';

  /// zh-TW: '下一首播放'
  String get playNext => '下一首播放';

  /// zh-TW: '加入佇列'
  String get addToQueue => '加入佇列';

  /// zh-TW: '已加入下一首播放'
  String get addedToNext => '已加入下一首播放';

  /// zh-TW: '已加入佇列'
  String get addedToQueue => '已加入佇列';
}

// Path: offline
class Translations$offline$zh_TW {
  Translations$offline$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '沒有網路連線'
  String get noInterface => '沒有網路連線';

  /// zh-TW: '無法連上網路'
  String get unreachable => '無法連上網路';

  /// zh-TW: '連上網路後再試一次'
  String get noInterfaceHint => '連上網路後再試一次';

  /// zh-TW: '請檢查網路連線後再試一次'
  String get unreachableHint => '請檢查網路連線後再試一次';
}

// Path: settings
class Translations$settings$zh_TW {
  Translations$settings$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '設定'
  String get title => '設定';

  /// zh-TW: '外觀'
  String get appearance => '外觀';

  /// zh-TW: '網路'
  String get network => '網路';

  /// zh-TW: '返回'
  String get back => '返回';

  /// zh-TW: '播放'
  String get playback => '播放';
}

// Path: player
class Translations$player$zh_TW {
  Translations$player$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '播放'
  String get play => '播放';

  /// zh-TW: '暫停'
  String get pause => '暫停';

  /// zh-TW: '上一首'
  String get previous => '上一首';

  /// zh-TW: '下一首'
  String get next => '下一首';

  /// zh-TW: '播放（空白鍵）'
  String get playTooltip => '播放（空白鍵）';

  /// zh-TW: '暫停（空白鍵）'
  String get pauseTooltip => '暫停（空白鍵）';

  /// zh-TW: '上一首（Ctrl+←）'
  String get previousTooltip => '上一首（Ctrl+←）';

  /// zh-TW: '下一首（Ctrl+→）'
  String get nextTooltip => '下一首（Ctrl+→）';

  /// zh-TW: '播放進度'
  String get progress => '播放進度';

  /// zh-TW: '載入中'
  String get loading => '載入中';

  /// zh-TW: '隨機播放'
  String get shuffle => '隨機播放';

  /// zh-TW: '循環：關閉'
  String get loopOff => '循環：關閉';

  /// zh-TW: '循環：全部'
  String get loopAll => '循環：全部';

  /// zh-TW: '循環：單曲'
  String get loopOne => '循環：單曲';

  /// zh-TW: '更多'
  String get more => '更多';

  /// zh-TW: '佇列已滿（最多 {count} 首），沒有加入'
  String queueFull({required Object count}) => '佇列已滿（最多 ${count} 首），沒有加入';

  /// zh-TW: '重試中'
  String get retrying => '重試中';

  /// zh-TW: '等待網路連線'
  String get waitingForNetwork => '等待網路連線';

  /// zh-TW: '試聽'
  String get preview => '試聽';

  /// zh-TW: '已跳過「{title}」：{reason}'
  String trackSkipped({required Object title, required Object reason}) =>
      '已跳過「${title}」：${reason}';

  /// zh-TW: '無法播放「{title}」：{reason}'
  String cannotPlay({required Object title, required Object reason}) =>
      '無法播放「${title}」：${reason}';

  /// zh-TW: '連續 {count} 首無法播放，已停止播放'
  String stoppedAfterFailures({required Object count}) =>
      '連續 ${count} 首無法播放，已停止播放';

  /// zh-TW: '「{title}」只有試聽片段'
  String previewPlaying({required Object title}) => '「${title}」只有試聽片段';
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

// Path: playback
class Translations$playback$zh_TW {
  Translations$playback$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '記住播放位置'
  String get rememberPosition => '記住播放位置';

  /// zh-TW: '臨時播放結束回到佇列時，從原本的位置繼續'
  String get rememberPositionHint => '臨時播放結束回到佇列時，從原本的位置繼續';

  /// zh-TW: '臨時播放回佇列倒退'
  String get tempPlayRewind => '臨時播放回佇列倒退';

  /// zh-TW: '回到原本的位置時稍微往回一點，方便接上'
  String get tempPlayRewindHint => '回到原本的位置時稍微往回一點，方便接上';

  /// zh-TW: '不倒退'
  String get rewindNone => '不倒退';

  /// zh-TW: '{seconds} 秒'
  String rewindSeconds({required Object seconds}) => '${seconds} 秒';

  /// zh-TW: '{label}（預設）'
  String rewindDefault({required Object label}) => '${label}（預設）';

  /// zh-TW: '跳過試聽片段'
  String get skipPreviewClips => '跳過試聽片段';

  /// zh-TW: '只有試聽片段的歌曲直接跳過；關閉時照播並標示「試聽」'
  String get skipPreviewClipsHint => '只有試聽片段的歌曲直接跳過；關閉時照播並標示「試聽」';
}

// Path: network
class Translations$network$zh_TW {
  Translations$network$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '快取上限'
  String get cacheLimit => '快取上限';

  /// zh-TW: '{size}（預設）'
  String cacheLimitDefault({required Object size}) => '${size}（預設）';

  /// zh-TW: '快取用量'
  String get usage => '快取用量';

  /// zh-TW: '封面'
  String get artwork => '封面';

  /// zh-TW: '清除快取'
  String get clear => '清除快取';

  /// zh-TW: '清除快取？'
  String get clearTitle => '清除快取？';

  /// zh-TW: '已快取的封面會被刪除，需要時再重新下載。設定與資料不受影響。'
  String get clearBody => '已快取的封面會被刪除，需要時再重新下載。設定與資料不受影響。';

  /// zh-TW: '取消'
  String get cancel => '取消';

  /// zh-TW: '已清除快取'
  String get cleared => '已清除快取';
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
