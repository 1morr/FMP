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
  late final Translations$history$zh_TW history =
      Translations$history$zh_TW.internal(_root);
  late final Translations$offline$zh_TW offline =
      Translations$offline$zh_TW.internal(_root);
  late final Translations$settings$zh_TW settings =
      Translations$settings$zh_TW.internal(_root);
  late final Translations$player$zh_TW player =
      Translations$player$zh_TW.internal(_root);
  late final Translations$playerPage$zh_TW playerPage =
      Translations$playerPage$zh_TW.internal(_root);
  late final Translations$appearance$zh_TW appearance =
      Translations$appearance$zh_TW.internal(_root);
  late final Translations$playback$zh_TW playback =
      Translations$playback$zh_TW.internal(_root);
  late final Translations$network$zh_TW network =
      Translations$network$zh_TW.internal(_root);
  late final Translations$sources$zh_TW sources =
      Translations$sources$zh_TW.internal(_root);
  late final Translations$plugins$zh_TW plugins =
      Translations$plugins$zh_TW.internal(_root);
  late final Translations$onboarding$zh_TW onboarding =
      Translations$onboarding$zh_TW.internal(_root);
  late final Translations$accounts$zh_TW accounts =
      Translations$accounts$zh_TW.internal(_root);
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

  /// zh-TW: '歷史'
  String get history => '歷史';

  /// zh-TW: '正在播放'
  String get panelTitle => '正在播放';

  /// zh-TW: '沒有正在播放的歌'
  String get panelEmpty => '沒有正在播放的歌';

  /// zh-TW: '收起正在播放面板'
  String get panelCollapseTooltip => '收起正在播放面板';

  /// zh-TW: '顯示正在播放面板'
  String get panelShowTooltip => '顯示正在播放面板';

  /// zh-TW: '隱藏正在播放面板'
  String get panelHideTooltip => '隱藏正在播放面板';

  /// zh-TW: '正在播放面板'
  String get panelMenuItem => '正在播放面板';

  /// zh-TW: '拖曳或按 ←／→ 調整寬度'
  String get panelResizeTooltip => '拖曳或按 ←／→ 調整寬度';
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

// Path: history
class Translations$history$zh_TW {
  Translations$history$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '播放歷史'
  String get title => '播放歷史';

  /// zh-TW: '還沒有播放紀錄'
  String get empty => '還沒有播放紀錄';

  /// zh-TW: '聽過的歌會依日期出現在這裡'
  String get emptyHint => '聽過的歌會依日期出現在這裡';

  /// zh-TW: '今天'
  String get today => '今天';

  /// zh-TW: '昨天'
  String get yesterday => '昨天';

  /// zh-TW: '{artist} · {time}'
  String subtitle({required Object artist, required Object time}) =>
      '${artist} · ${time}';

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

  /// zh-TW: '從歷史移除'
  String get remove => '從歷史移除';

  /// zh-TW: '清除全部歷史'
  String get clearAll => '清除全部歷史';

  /// zh-TW: '清除全部播放歷史？'
  String get clearTitle => '清除全部播放歷史？';

  /// zh-TW: '所有播放紀錄都會被刪除，無法復原。佇列與設定不受影響。'
  String get clearBody => '所有播放紀錄都會被刪除，無法復原。佇列與設定不受影響。';

  /// zh-TW: '取消'
  String get cancel => '取消';

  /// zh-TW: '清除'
  String get confirm => '清除';

  /// zh-TW: '已清除播放歷史'
  String get cleared => '已清除播放歷史';
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

  /// zh-TW: '帳號'
  String get accounts => '帳號';

  /// zh-TW: '外觀'
  String get appearance => '外觀';

  /// zh-TW: '網路'
  String get network => '網路';

  /// zh-TW: '返回'
  String get back => '返回';

  /// zh-TW: '播放'
  String get playback => '播放';

  /// zh-TW: '插件'
  String get plugins => '插件';
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

  /// zh-TW: '音訊輸出裝置無法使用，已暫停播放'
  String get outputDeviceFailed => '音訊輸出裝置無法使用，已暫停播放';

  /// zh-TW: '音訊輸出裝置無法使用，已改用系統預設'
  String get outputDeviceFellBack => '音訊輸出裝置無法使用，已改用系統預設';

  /// zh-TW: '隨機播放（Ctrl+S）'
  String get shuffleTooltip => '隨機播放（Ctrl+S）';

  /// zh-TW: '循環：關閉（Ctrl+R）'
  String get loopOffTooltip => '循環：關閉（Ctrl+R）';

  /// zh-TW: '循環：全部（Ctrl+R）'
  String get loopAllTooltip => '循環：全部（Ctrl+R）';

  /// zh-TW: '循環：單曲（Ctrl+R）'
  String get loopOneTooltip => '循環：單曲（Ctrl+R）';

  /// zh-TW: '音量'
  String get volume => '音量';

  /// zh-TW: '音量（Ctrl+↑／↓）'
  String get volumeTooltip => '音量（Ctrl+↑／↓）';

  /// zh-TW: '靜音'
  String get mute => '靜音';

  /// zh-TW: '取消靜音'
  String get unmute => '取消靜音';

  /// zh-TW: '輸出裝置'
  String get outputDevice => '輸出裝置';

  /// zh-TW: '系統預設'
  String get systemDefault => '系統預設';
}

// Path: playerPage
class Translations$playerPage$zh_TW {
  Translations$playerPage$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '開啟播放頁'
  String get openHint => '開啟播放頁';

  /// zh-TW: '關閉播放頁（Esc）'
  String get closeTooltip => '關閉播放頁（Esc）';

  /// zh-TW: '顯示歌詞（Ctrl+L）'
  String get showLyricsTooltip => '顯示歌詞（Ctrl+L）';

  /// zh-TW: '顯示封面'
  String get showArtworkTooltip => '顯示封面';

  /// zh-TW: '歌詞'
  String get tabLyrics => '歌詞';

  /// zh-TW: '佇列'
  String get tabQueue => '佇列';

  /// zh-TW: '詳細'
  String get tabDetails => '詳細';

  /// zh-TW: '沒有歌詞'
  String get noLyrics => '沒有歌詞';

  /// zh-TW: '播放速度'
  String get speed => '播放速度';

  /// zh-TW: '{speed}×'
  String speedValue({required Object speed}) => '${speed}×';

  /// zh-TW: '上傳者'
  String get detailsUploader => '上傳者';

  /// zh-TW: '時長'
  String get detailsDuration => '時長';

  /// zh-TW: '音源'
  String get detailsSource => '音源';

  /// zh-TW: '佇列（Ctrl+Q）'
  String get queueTooltip => '佇列（Ctrl+Q）';

  /// zh-TW: '共 {count} 首'
  String queueCount({required Object count}) => '共 ${count} 首';

  /// zh-TW: '隨機順序跟著位置；拖曳只換歌，不改順序'
  String get queueShuffleNote => '隨機順序跟著位置；拖曳只換歌，不改順序';

  /// zh-TW: '清空佇列'
  String get queueClear => '清空佇列';

  /// zh-TW: '清空佇列？'
  String get queueClearTitle => '清空佇列？';

  /// zh-TW: '佇列裡的歌都會移除並停止播放。播放歷史與設定不受影響。'
  String get queueClearBody => '佇列裡的歌都會移除並停止播放。播放歷史與設定不受影響。';

  /// zh-TW: '清空'
  String get queueClearConfirm => '清空';

  /// zh-TW: '取消'
  String get queueCancel => '取消';

  /// zh-TW: '已清空佇列'
  String get queueCleared => '已清空佇列';

  /// zh-TW: '更多選項'
  String get queueMore => '更多選項';

  /// zh-TW: '下一首播放'
  String get queuePlayNext => '下一首播放';

  /// zh-TW: '從佇列移除'
  String get queueRemove => '從佇列移除';

  /// zh-TW: '拖曳以重新排列'
  String get queueReorder => '拖曳以重新排列';
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

  /// zh-TW: '音質'
  String get audioQuality => '音質';

  /// zh-TW: '適用於所有音源'
  String get audioQualityHint => '適用於所有音源';

  /// zh-TW: '高'
  String get qualityHigh => '高';

  /// zh-TW: '中'
  String get qualityMedium => '中';

  /// zh-TW: '低'
  String get qualityLow => '低';

  /// zh-TW: '格式偏好'
  String get formatPriority => '格式偏好';

  /// zh-TW: '音源同時提供兩種格式時先選哪一種'
  String get formatPriorityHint => '音源同時提供兩種格式時先選哪一種';

  /// zh-TW: 'Opus 優先'
  String get formatOpusFirst => 'Opus 優先';

  /// zh-TW: 'AAC 優先'
  String get formatAacFirst => 'AAC 優先';

  /// zh-TW: '記住播放位置'
  String get rememberPosition => '記住播放位置';

  /// zh-TW: '臨時播放結束回到佇列或重開 App 時，從原本的位置繼續'
  String get rememberPositionHint => '臨時播放結束回到佇列或重開 App 時，從原本的位置繼續';

  /// zh-TW: '臨時播放回佇列倒退'
  String get tempPlayRewind => '臨時播放回佇列倒退';

  /// zh-TW: '回到原本的位置時稍微往回一點，方便接上'
  String get tempPlayRewindHint => '回到原本的位置時稍微往回一點，方便接上';

  /// zh-TW: '不倒退'
  String get rewindNone => '不倒退';

  /// zh-TW: '{seconds} 秒'
  String rewindSeconds({required Object seconds}) => '${seconds} 秒';

  /// zh-TW: '{label}（預設）'
  String optionDefault({required Object label}) => '${label}（預設）';

  /// zh-TW: '跳過試聽片段'
  String get skipPreviewClips => '跳過試聽片段';

  /// zh-TW: '只有試聽片段的歌曲直接跳過；關閉時照播並標示「試聽」'
  String get skipPreviewClipsHint => '只有試聽片段的歌曲直接跳過；關閉時照播並標示「試聽」';

  /// zh-TW: '重啟後恢復倒退'
  String get restartRewind => '重啟後恢復倒退';

  /// zh-TW: '重新開啟 App 後按播放，從上次的位置稍微往回一點，方便接上'
  String get restartRewindHint => '重新開啟 App 後按播放，從上次的位置稍微往回一點，方便接上';

  /// zh-TW: '播放歷史保留筆數'
  String get playHistoryLimit => '播放歷史保留筆數';

  /// zh-TW: '超過的舊紀錄會自動刪除；調小時馬上刪除'
  String get playHistoryLimitHint => '超過的舊紀錄會自動刪除；調小時馬上刪除';

  /// zh-TW: '{count} 筆'
  String playHistoryLimitOption({required Object count}) => '${count} 筆';

  /// zh-TW: '切歌時捲到目前歌曲'
  String get autoScrollToCurrent => '切歌時捲到目前歌曲';

  /// zh-TW: '佇列清單開著時，換歌後自動捲到正在播放的那一首'
  String get autoScrollToCurrentHint => '佇列清單開著時，換歌後自動捲到正在播放的那一首';
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

// Path: sources
class Translations$sources$zh_TW {
  Translations$sources$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '音源未安裝'
  String get notInstalled => '音源未安裝';

  /// zh-TW: '音源已停用'
  String get disabled => '音源已停用';
}

// Path: plugins
class Translations$plugins$zh_TW {
  Translations$plugins$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '已安裝'
  String get tabInstalled => '已安裝';

  /// zh-TW: '可安裝'
  String get tabAvailable => '可安裝';

  /// zh-TW: '檢查更新'
  String get checkUpdates => '檢查更新';

  /// zh-TW: '全部更新'
  String get updateAll => '全部更新';

  /// zh-TW: '更多選項'
  String get more => '更多選項';

  /// zh-TW: '從檔案安裝'
  String get installFromFile => '從檔案安裝';

  /// zh-TW: '從網址安裝'
  String get installFromUrl => '從網址安裝';

  /// zh-TW: '管理插件庫'
  String get manageIndexes => '管理插件庫';

  /// zh-TW: '處理中'
  String get working => '處理中';

  /// zh-TW: '還沒有安裝插件'
  String get noneInstalled => '還沒有安裝插件';

  /// zh-TW: '到「可安裝」分頁挑選要安裝的插件'
  String get noneInstalledHint => '到「可安裝」分頁挑選要安裝的插件';

  /// zh-TW: '{version} · {author}'
  String versionAuthor({required Object version, required Object author}) =>
      '${version} · ${author}';

  /// zh-TW: '已停用'
  String get tagDisabled => '已停用';

  /// zh-TW: '沒有回應'
  String get tagUnresponsive => '沒有回應';

  /// zh-TW: '有更新'
  String get tagUpdate => '有更新';

  /// zh-TW: '已安裝'
  String get tagInstalled => '已安裝';

  /// zh-TW: '啟用「{name}」'
  String enable({required Object name}) => '啟用「${name}」';

  /// zh-TW: '詳細資料'
  String get showDetails => '詳細資料';

  /// zh-TW: '收起詳細資料'
  String get hideDetails => '收起詳細資料';

  /// zh-TW: '能力'
  String get capabilities => '能力';

  /// zh-TW: '會連的網域'
  String get hosts => '會連的網域';

  /// zh-TW: '來源'
  String get source => '來源';

  /// zh-TW: '、'
  String get listSeparator => '、';

  /// zh-TW: '官方插件庫'
  String get sourceOfficial => '官方插件庫';

  /// zh-TW: '自訂插件庫：{url}'
  String sourceCustom({required Object url}) => '自訂插件庫：${url}';

  /// zh-TW: '從檔案或網址安裝'
  String get sourceLocal => '從檔案或網址安裝';

  /// zh-TW: '自訂插件庫'
  String get customIndex => '自訂插件庫';

  /// zh-TW: '更新到 {version}'
  String updateTo({required Object version}) => '更新到 ${version}';

  /// zh-TW: '需要更新 FMP'
  String get needsAppUpdate => '需要更新 FMP';

  /// zh-TW: '移除'
  String get remove => '移除';

  /// zh-TW: '安裝'
  String get install => '安裝';

  /// zh-TW: '安裝「{name}」？'
  String installTitle({required Object name}) => '安裝「${name}」？';

  /// zh-TW: '安裝這些插件？'
  String get installAllTitle => '安裝這些插件？';

  /// zh-TW: '更新「{name}」？'
  String updateTitle({required Object name}) => '更新「${name}」？';

  /// zh-TW: '作者 {author} · 版本 {version}'
  String byline({required Object author, required Object version}) =>
      '作者 ${author} · 版本 ${version}';

  /// zh-TW: '新版本比目前的版本多了下列能力或網域，確認後才會更新。'
  String get addedAccess => '新版本比目前的版本多了下列能力或網域，確認後才會更新。';

  /// zh-TW: '新增的能力'
  String get addedCapabilities => '新增的能力';

  /// zh-TW: '新增的網域'
  String get addedHosts => '新增的網域';

  /// zh-TW: '此腳本會以你的登入身分存取這些網站。'
  String get loginWarning => '此腳本會以你的登入身分存取這些網站。';

  /// zh-TW: '非官方來源：這個插件沒有經過 FMP 審查。'
  String get unofficial => '非官方來源：這個插件沒有經過 FMP 審查。';

  /// zh-TW: '會取代已安裝的版本 {version}。'
  String replaces({required Object version}) => '會取代已安裝的版本 ${version}。';

  /// zh-TW: '取消'
  String get cancel => '取消';

  /// zh-TW: '安裝'
  String get confirmInstall => '安裝';

  /// zh-TW: '更新'
  String get confirmUpdate => '更新';

  /// zh-TW: '移除「{name}」？'
  String removeTitle({required Object name}) => '移除「${name}」？';

  /// zh-TW: '插件與它的資料、登入、快取都會刪除。曲目會保留，顯示「音源未安裝」。'
  String get removeBody => '插件與它的資料、登入、快取都會刪除。曲目會保留，顯示「音源未安裝」。';

  /// zh-TW: '移除'
  String get confirmRemove => '移除';

  /// zh-TW: '已安裝「{name}」'
  String installed({required Object name}) => '已安裝「${name}」';

  /// zh-TW: '已將「{name}」更新到 {version}'
  String updated({required Object name, required Object version}) =>
      '已將「${name}」更新到 ${version}';

  /// zh-TW: '已更新 {count} 個插件'
  String updatedCount({required Object count}) => '已更新 ${count} 個插件';

  /// zh-TW: '已移除「{name}」'
  String removed({required Object name}) => '已移除「${name}」';

  /// zh-TW: '插件都是最新版本'
  String get upToDate => '插件都是最新版本';

  /// zh-TW: '有 {count} 個插件可以更新'
  String updatesFound({required Object count}) => '有 ${count} 個插件可以更新';

  /// zh-TW: '有插件庫讀不到，可能還有更新沒找到'
  String get checkFailed => '有插件庫讀不到，可能還有更新沒找到';

  /// zh-TW: '插件庫剛更新，請稍後再試'
  String get hashMismatch => '插件庫剛更新，請稍後再試';

  /// zh-TW: '插件檔與插件庫的資料不一致，沒有安裝'
  String get manifestMismatch => '插件檔與插件庫的資料不一致，沒有安裝';

  /// zh-TW: '需要更新 FMP 才能安裝這個插件'
  String get appUpdateRequired => '需要更新 FMP 才能安裝這個插件';

  /// zh-TW: '無法安裝「{name}」：{reason}'
  String installFailed({required Object name, required Object reason}) =>
      '無法安裝「${name}」：${reason}';

  /// zh-TW: '無法安裝插件：{reason}'
  String installFileFailed({required Object reason}) => '無法安裝插件：${reason}';

  /// zh-TW: '無法更新「{name}」：{reason}'
  String updateFailed({required Object name, required Object reason}) =>
      '無法更新「${name}」：${reason}';

  /// zh-TW: '無法移除「{name}」：{reason}'
  String removeFailed({required Object name, required Object reason}) =>
      '無法移除「${name}」：${reason}';

  /// zh-TW: '無法啟用「{name}」：{reason}'
  String enableFailed({required Object name, required Object reason}) =>
      '無法啟用「${name}」：${reason}';

  /// zh-TW: '無法停用「{name}」：{reason}'
  String disableFailed({required Object name, required Object reason}) =>
      '無法停用「${name}」：${reason}';

  /// zh-TW: '無法讀取這個插件庫'
  String get indexLoadFailed => '無法讀取這個插件庫';

  /// zh-TW: '需要更新 FMP 才能讀取這個插件庫'
  String get indexNeedsAppUpdate => '需要更新 FMP 才能讀取這個插件庫';

  /// zh-TW: '這個插件庫沒有插件'
  String get indexEmpty => '這個插件庫沒有插件';

  /// zh-TW: '無法讀取插件庫'
  String get allFailed => '無法讀取插件庫';

  /// zh-TW: '重試'
  String get retry => '重試';

  /// zh-TW: '插件檔的網址（https）'
  String get urlLabel => '插件檔的網址（https）';

  /// zh-TW: '請輸入 https 開頭的網址'
  String get urlInvalid => '請輸入 https 開頭的網址';

  /// zh-TW: '下載'
  String get download => '下載';

  /// zh-TW: '插件庫'
  String get indexesTitle => '插件庫';

  /// zh-TW: '加入插件庫'
  String get addIndex => '加入插件庫';

  /// zh-TW: 'index.json 的網址（https）'
  String get indexUrlLabel => 'index.json 的網址（https）';

  /// zh-TW: '非官方來源：這個清單的插件沒有經過 FMP 審查。'
  String get indexWarning => '非官方來源：這個清單的插件沒有經過 FMP 審查。';

  /// zh-TW: '加入'
  String get add => '加入';

  /// zh-TW: '移除這個插件庫'
  String get removeIndex => '移除這個插件庫';

  /// zh-TW: '已加入插件庫'
  String get indexAdded => '已加入插件庫';

  /// zh-TW: '已移除插件庫'
  String get indexRemoved => '已移除插件庫';

  /// zh-TW: '這個插件庫已在清單上'
  String get indexExists => '這個插件庫已在清單上';

  /// zh-TW: '關閉'
  String get close => '關閉';

  late final Translations$plugins$capabilityNames$zh_TW capabilityNames =
      Translations$plugins$capabilityNames$zh_TW.internal(_root);
}

// Path: onboarding
class Translations$onboarding$zh_TW {
  Translations$onboarding$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '安裝插件才能開始搜尋'
  String get title => '安裝插件才能開始搜尋';

  /// zh-TW: '插件讓 FMP 連到各個音樂來源。勾選想用的；之後隨時可以到「設定 > 插件」調整。'
  String get body => '插件讓 FMP 連到各個音樂來源。勾選想用的；之後隨時可以到「設定 > 插件」調整。';

  /// zh-TW: '稍後再說'
  String get later => '稍後再說';

  /// zh-TW: '前往插件頁'
  String get goToPlugins => '前往插件頁';

  /// zh-TW: '正在載入插件'
  String get loading => '正在載入插件';

  /// zh-TW: '已安裝的插件：{count}'
  String installedCount({required Object count}) => '已安裝的插件：${count}';

  /// zh-TW: '有些插件沒有裝成功'
  String get failedTitle => '有些插件沒有裝成功';
}

// Path: accounts
class Translations$accounts$zh_TW {
  Translations$accounts$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '沒有可以登入的音源'
  String get none => '沒有可以登入的音源';

  /// zh-TW: '安裝支援登入的插件之後，就能在這裡登入。'
  String get noneHint => '安裝支援登入的插件之後，就能在這裡登入。';

  /// zh-TW: '前往插件頁'
  String get goToPlugins => '前往插件頁';

  /// zh-TW: '無法讀取帳號'
  String get loadFailed => '無法讀取帳號';

  /// zh-TW: '處理中'
  String get working => '處理中';

  /// zh-TW: '未登入'
  String get notLoggedIn => '未登入';

  /// zh-TW: '正常'
  String get statusActive => '正常';

  /// zh-TW: '已失效'
  String get statusInvalidated => '已失效';

  /// zh-TW: '暫時無法讀取，稍後重試'
  String get statusUnreadable => '暫時無法讀取，稍後重試';

  /// zh-TW: '以登入身分瀏覽與播放'
  String get browseAsLoggedIn => '以登入身分瀏覽與播放';

  /// zh-TW: '以登入身分大量請求可能被視為自動化行為（推測）'
  String get automationRisk => '以登入身分大量請求可能被視為自動化行為（推測）';

  /// zh-TW: 'QR 登入'
  String get loginQr => 'QR 登入';

  /// zh-TW: '網頁登入'
  String get loginWebView => '網頁登入';

  /// zh-TW: '貼上 cookie'
  String get loginCookie => '貼上 cookie';

  /// zh-TW: '重新登入'
  String get relogin => '重新登入';

  /// zh-TW: '登出'
  String get logout => '登出';

  /// zh-TW: '這個平台還不能登入「{name}」'
  String noMethod({required Object name}) => '這個平台還不能登入「${name}」';

  /// zh-TW: '登出「{name}」？'
  String logoutTitle({required Object name}) => '登出「${name}」？';

  /// zh-TW: 'FMP 裡這個音源的登入資料會刪除。「以登入身分瀏覽與播放」的設定會保留。'
  String get logoutBody => 'FMP 裡這個音源的登入資料會刪除。「以登入身分瀏覽與播放」的設定會保留。';

  /// zh-TW: '登出'
  String get confirmLogout => '登出';

  /// zh-TW: '取消'
  String get cancel => '取消';

  /// zh-TW: '已登入「{name}」'
  String loggedIn({required Object name}) => '已登入「${name}」';

  /// zh-TW: '已登出「{name}」'
  String loggedOut({required Object name}) => '已登出「${name}」';

  /// zh-TW: '無法登入「{name}」：{reason}'
  String loginFailed({required Object name, required Object reason}) =>
      '無法登入「${name}」：${reason}';

  /// zh-TW: '無法登出「{name}」：{reason}'
  String logoutFailed({required Object name, required Object reason}) =>
      '無法登出「${name}」：${reason}';

  /// zh-TW: '無法儲存設定：{reason}'
  String settingFailed({required Object reason}) => '無法儲存設定：${reason}';

  /// zh-TW: '以 QR 碼登入「{name}」'
  String qrTitle({required Object name}) => '以 QR 碼登入「${name}」';

  /// zh-TW: '登入用的 QR 碼'
  String get qrImage => '登入用的 QR 碼';

  /// zh-TW: '正在產生 QR 碼'
  String get qrStarting => '正在產生 QR 碼';

  /// zh-TW: '用手機上的 App 掃描 QR 碼'
  String get qrWaiting => '用手機上的 App 掃描 QR 碼';

  /// zh-TW: '已掃描，請在手機上確認'
  String get qrScanned => '已掃描，請在手機上確認';

  /// zh-TW: 'QR 碼已過期'
  String get qrExpired => 'QR 碼已過期';

  /// zh-TW: '正在確認登入'
  String get qrVerifying => '正在確認登入';

  /// zh-TW: '重新產生'
  String get qrRegenerate => '重新產生';

  /// zh-TW: '重試'
  String get retry => '重試';
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

// Path: plugins.capabilityNames
class Translations$plugins$capabilityNames$zh_TW {
  Translations$plugins$capabilityNames$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '搜尋'
  String get search => '搜尋';

  /// zh-TW: '播放'
  String get resolveStream => '播放';

  /// zh-TW: '曲目詳細資料'
  String get trackDetail => '曲目詳細資料';

  /// zh-TW: '分 P'
  String get multiPart => '分 P';

  /// zh-TW: '匯入歌單'
  String get importPlaylist => '匯入歌單';

  /// zh-TW: '讀取音樂庫'
  String get libraryRead => '讀取音樂庫';

  /// zh-TW: '修改音樂庫'
  String get libraryWrite => '修改音樂庫';

  /// zh-TW: '排行榜'
  String get charts => '排行榜';

  /// zh-TW: '直播'
  String get live => '直播';

  /// zh-TW: 'Mix'
  String get mix => 'Mix';

  /// zh-TW: '歌詞'
  String get lyrics => '歌詞';

  /// zh-TW: '登入'
  String get login => '登入';
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
