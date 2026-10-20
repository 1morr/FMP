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
  late final Translations$home$zh_TW home = Translations$home$zh_TW.internal(
    _root,
  );
  late final Translations$library$zh_TW library =
      Translations$library$zh_TW.internal(_root);
  late final Translations$playlist$zh_TW playlist =
      Translations$playlist$zh_TW.internal(_root);
  late final Translations$selection$zh_TW selection =
      Translations$selection$zh_TW.internal(_root);
  late final Translations$offline$zh_TW offline =
      Translations$offline$zh_TW.internal(_root);
  late final Translations$settings$zh_TW settings =
      Translations$settings$zh_TW.internal(_root);
  late final Translations$about$zh_TW about = Translations$about$zh_TW.internal(
    _root,
  );
  late final Translations$debug$zh_TW debug = Translations$debug$zh_TW.internal(
    _root,
  );
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
  late final Translations$radio$zh_TW radio = Translations$radio$zh_TW.internal(
    _root,
  );
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
  late final Translations$errorReport$zh_TW errorReport =
      Translations$errorReport$zh_TW.internal(_root);
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

  /// zh-TW: '首頁'
  String get home => '首頁';

  /// zh-TW: '音樂庫'
  String get library => '音樂庫';

  /// zh-TW: '返回（Esc）'
  String get backTooltip => '返回（Esc）';

  /// zh-TW: '搜尋'
  String get search => '搜尋';

  /// zh-TW: '設定'
  String get settings => '設定';

  /// zh-TW: '搜尋（Ctrl+F）'
  String get searchTooltip => '搜尋（Ctrl+F）';

  /// zh-TW: '設定（Ctrl+,）'
  String get settingsTooltip => '設定（Ctrl+,）';

  /// zh-TW: '電台'
  String get radio => '電台';

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

  /// zh-TW: '搜尋直播間'
  String get roomHint => '搜尋直播間';

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

  /// zh-TW: '下一首播放（Mix 中無法使用）'
  String get playNextInMix => '下一首播放（Mix 中無法使用）';

  /// zh-TW: '加入佇列（Mix 中無法使用）'
  String get addToQueueInMix => '加入佇列（Mix 中無法使用）';

  /// zh-TW: '開始 Mix'
  String get startMix => '開始 Mix';

  /// zh-TW: '已加入下一首播放'
  String get addedToNext => '已加入下一首播放';

  /// zh-TW: '已加入佇列'
  String get addedToQueue => '已加入佇列';

  /// zh-TW: '曲目'
  String get modeTracks => '曲目';

  /// zh-TW: '直播間'
  String get modeRooms => '直播間';

  /// zh-TW: '全部'
  String get filterAll => '全部';

  /// zh-TW: '開播中'
  String get filterLive => '開播中';

  /// zh-TW: '未開播'
  String get filterOffline => '未開播';

  /// zh-TW: '收聽'
  String get listen => '收聽';

  /// zh-TW: '加為電台'
  String get addToRadio => '加為電台';

  /// zh-TW: '展開分 P'
  String get showParts => '展開分 P';

  /// zh-TW: '收合分 P'
  String get hideParts => '收合分 P';

  /// zh-TW: '正在載入分 P'
  String get loadingParts => '正在載入分 P';

  /// zh-TW: '無法載入分 P'
  String get partsFailed => '無法載入分 P';
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

  /// zh-TW: '下一首播放（Mix 中無法使用）'
  String get playNextInMix => '下一首播放（Mix 中無法使用）';

  /// zh-TW: '加入佇列（Mix 中無法使用）'
  String get addToQueueInMix => '加入佇列（Mix 中無法使用）';

  /// zh-TW: '開始 Mix'
  String get startMix => '開始 Mix';

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

// Path: home
class Translations$home$zh_TW {
  Translations$home$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '首頁'
  String get title => '首頁';

  /// zh-TW: '最近播放'
  String get recentlyPlayed => '最近播放';

  /// zh-TW: '我的歌單'
  String get myPlaylists => '我的歌單';

  /// zh-TW: '電台'
  String get radio => '電台';

  /// zh-TW: '查看全部'
  String get viewAll => '查看全部';

  /// zh-TW: '這裡還沒有內容'
  String get empty => '這裡還沒有內容';

  /// zh-TW: '搜尋並播放歌曲，或匯入歌單'
  String get emptyHint => '搜尋並播放歌曲，或匯入歌單';

  /// zh-TW: '更多選項'
  String get more => '更多選項';

  /// zh-TW: '播放'
  String get play => '播放';

  /// zh-TW: '下一首播放'
  String get playNext => '下一首播放';

  /// zh-TW: '加入佇列'
  String get addToQueue => '加入佇列';

  /// zh-TW: '下一首播放（Mix 中無法使用）'
  String get playNextInMix => '下一首播放（Mix 中無法使用）';

  /// zh-TW: '加入佇列（Mix 中無法使用）'
  String get addToQueueInMix => '加入佇列（Mix 中無法使用）';

  /// zh-TW: '開始 Mix'
  String get startMix => '開始 Mix';

  /// zh-TW: '已加入下一首播放'
  String get addedToNext => '已加入下一首播放';

  /// zh-TW: '已加入佇列'
  String get addedToQueue => '已加入佇列';
}

// Path: library
class Translations$library$zh_TW {
  Translations$library$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '音樂庫'
  String get title => '音樂庫';

  /// zh-TW: '歷史'
  String get history => '歷史';

  /// zh-TW: '歌單'
  String get playlists => '歌單';

  /// zh-TW: '新增歌單'
  String get newPlaylist => '新增歌單';

  /// zh-TW: '還沒有歌單'
  String get empty => '還沒有歌單';

  /// zh-TW: '按「新增歌單」建立一張歌單，或按「匯入」帶進一張。'
  String get emptyHint => '按「新增歌單」建立一張歌單，或按「匯入」帶進一張。';

  /// zh-TW: '{count} 首'
  String trackCount({required Object count}) => '${count} 首';

  /// zh-TW: '1 首'
  String get trackCountOne => '1 首';

  /// zh-TW: '本機'
  String get local => '本機';

  /// zh-TW: '更多選項'
  String get more => '更多選項';

  /// zh-TW: '全部加入佇列'
  String get addToQueue => '全部加入佇列';

  /// zh-TW: '隨機加入佇列'
  String get shuffleToQueue => '隨機加入佇列';

  /// zh-TW: '全部加入佇列（Mix 中無法使用）'
  String get addToQueueInMix => '全部加入佇列（Mix 中無法使用）';

  /// zh-TW: '隨機加入佇列（Mix 中無法使用）'
  String get shuffleToQueueInMix => '隨機加入佇列（Mix 中無法使用）';

  /// zh-TW: '已將「{name}」加入佇列'
  String addedToQueue({required Object name}) => '已將「${name}」加入佇列';

  /// zh-TW: '無法加入佇列：{reason}'
  String addFailed({required Object reason}) => '無法加入佇列：${reason}';

  /// zh-TW: '編輯'
  String get edit => '編輯';

  /// zh-TW: '刪除'
  String get delete => '刪除';

  /// zh-TW: '刪除歌單？'
  String get deleteTitle => '刪除歌單？';

  /// zh-TW: '「{name}」會被刪除，無法復原。歌曲本身與播放歷史不受影響。'
  String deleteBody({required Object name}) =>
      '「${name}」會被刪除，無法復原。歌曲本身與播放歷史不受影響。';

  /// zh-TW: '已刪除歌單'
  String get deleted => '已刪除歌單';

  /// zh-TW: '無法刪除歌單：{reason}'
  String deleteFailed({required Object reason}) => '無法刪除歌單：${reason}';

  /// zh-TW: '新增歌單'
  String get createTitle => '新增歌單';

  /// zh-TW: '編輯歌單'
  String get editTitle => '編輯歌單';

  /// zh-TW: '名稱'
  String get name => '名稱';

  /// zh-TW: '請輸入名稱'
  String get nameRequired => '請輸入名稱';

  /// zh-TW: '描述（選填）'
  String get description => '描述（選填）';

  /// zh-TW: '封面'
  String get cover => '封面';

  /// zh-TW: '第一首歌的封面'
  String get coverDefault => '第一首歌的封面';

  /// zh-TW: '建立'
  String get create => '建立';

  /// zh-TW: '儲存'
  String get save => '儲存';

  /// zh-TW: '取消'
  String get cancel => '取消';

  /// zh-TW: '已建立歌單'
  String get created => '已建立歌單';

  /// zh-TW: '已儲存歌單'
  String get saved => '已儲存歌單';

  /// zh-TW: '無法建立歌單：{reason}'
  String createFailed({required Object reason}) => '無法建立歌單：${reason}';

  /// zh-TW: '無法儲存歌單：{reason}'
  String saveFailed({required Object reason}) => '無法儲存歌單：${reason}';

  /// zh-TW: '拖曳以排序'
  String get reorder => '拖曳以排序';

  /// zh-TW: '無法調整歌單順序：{reason}'
  String reorderFailed({required Object reason}) => '無法調整歌單順序：${reason}';

  /// zh-TW: '自訂圖片'
  String get coverCustom => '自訂圖片';

  /// zh-TW: '自訂'
  String get coverChooseCustom => '自訂';

  /// zh-TW: '使用預設'
  String get coverUseDefault => '使用預設';

  /// zh-TW: '圖片網址'
  String get coverUrl => '圖片網址';

  /// zh-TW: '請輸入以 https 開頭的網址'
  String get coverInvalidUrl => '請輸入以 https 開頭的網址';

  /// zh-TW: '這個網址不屬於任何已安裝的音源'
  String get coverNotFromSource => '這個網址不屬於任何已安裝的音源';

  /// zh-TW: '匯入'
  String get imported => '匯入';

  /// zh-TW: 'Mix'
  String get mix => 'Mix';

  /// zh-TW: 'Mix 播放'
  String get mixPlay => 'Mix 播放';

  /// zh-TW: 'Mix 播放（{reason}）'
  String mixPlayDisabled({required Object reason}) => 'Mix 播放（${reason}）';

  /// zh-TW: '種子曲目'
  String get mixSeed => '種子曲目';

  /// zh-TW: '這個音源不支援 Mix'
  String get mixUnsupported => '這個音源不支援 Mix';

  /// zh-TW: '加入歌單…'
  String get addToPlaylist => '加入歌單…';

  /// zh-TW: '加入歌單'
  String get addToPlaylistTitle => '加入歌單';

  /// zh-TW: '還沒有本機歌單'
  String get noLocalPlaylists => '還沒有本機歌單';

  /// zh-TW: '加入'
  String get add => '加入';

  /// zh-TW: '已加入「{name}」'
  String addedToPlaylist({required Object name}) => '已加入「${name}」';

  /// zh-TW: '已加入 {count} 張歌單'
  String addedToPlaylists({required Object count}) => '已加入 ${count} 張歌單';

  /// zh-TW: '無法加入歌單：{reason}'
  String addToPlaylistFailed({required Object reason}) => '無法加入歌單：${reason}';

  /// zh-TW: '匯入歌單'
  String get importTooltip => '匯入歌單';

  /// zh-TW: '匯入歌單'
  String get importTitle => '匯入歌單';

  /// zh-TW: '網址'
  String get importUrlLabel => '網址';

  /// zh-TW: '匯入'
  String get importAction => '匯入';

  /// zh-TW: '正在辨識網址…'
  String get importLooking => '正在辨識網址…';

  /// zh-TW: '已讀 {count} 首'
  String importProgress({required Object count}) => '已讀 ${count} 首';

  /// zh-TW: '已安裝的音源都不認得這個網址'
  String get importUnrecognized => '已安裝的音源都不認得這個網址';

  /// zh-TW: '還不支援匯入這種網址'
  String get importUnsupported => '還不支援匯入這種網址';

  /// zh-TW: '無法匯入：{reason}'
  String importFailed({required Object reason}) => '無法匯入：${reason}';

  /// zh-TW: '已匯入歌單'
  String get importDone => '已匯入歌單';

  /// zh-TW: '已匯入，但只讀到歌單的一部分。刷新可以讀完其餘的。'
  String get importPartial => '已匯入，但只讀到歌單的一部分。刷新可以讀完其餘的。';

  /// zh-TW: '刷新'
  String get refresh => '刷新';

  /// zh-TW: '刷新中…'
  String get refreshing => '刷新中…';

  /// zh-TW: '已刷新歌單'
  String get refreshed => '已刷新歌單';

  /// zh-TW: '只讀到歌單的一部分，沒有移除任何歌曲'
  String get refreshedPartly => '只讀到歌單的一部分，沒有移除任何歌曲';

  /// zh-TW: '無法刷新歌單：{reason}'
  String refreshFailed({required Object reason}) => '無法刷新歌單：${reason}';

  /// zh-TW: '離線中，無法刷新歌單'
  String get refreshOffline => '離線中，無法刷新歌單';

  /// zh-TW: '這個音源不能刷新歌單'
  String get refreshNoSource => '這個音源不能刷新歌單';

  /// zh-TW: '上次刷新：{time}'
  String statusRefreshed({required Object time}) => '上次刷新：${time}';

  /// zh-TW: '上次刷新：部分完成 · {time}'
  String statusPartial({required Object time}) => '上次刷新：部分完成 · ${time}';

  /// zh-TW: '還沒刷新過'
  String get statusNever => '還沒刷新過';

  /// zh-TW: '刷新失敗'
  String get statusFailed => '刷新失敗';

  /// zh-TW: '來源失效：遠端歌單已刪除或無權限'
  String get statusGone => '來源失效：遠端歌單已刪除或無權限';

  /// zh-TW: '需要登入才能刷新'
  String get statusAuth => '需要登入才能刷新';

  /// zh-TW: '重試'
  String get retry => '重試';

  /// zh-TW: '使用遠端的'
  String get useRemote => '使用遠端的';

  /// zh-TW: '下一次刷新會寫回遠端的值'
  String get useRemoteHint => '下一次刷新會寫回遠端的值';

  /// zh-TW: '自動刷新'
  String get refreshInterval => '自動刷新';

  /// zh-TW: '不啟用'
  String get refreshIntervalOff => '不啟用';

  /// zh-TW: '每小時'
  String get refreshEveryHour => '每小時';

  /// zh-TW: '每 {count} 小時'
  String refreshEveryHours({required Object count}) => '每 ${count} 小時';

  /// zh-TW: '每天'
  String get refreshEveryDay => '每天';

  /// zh-TW: '每 {count} 天'
  String refreshEveryDays({required Object count}) => '每 ${count} 天';

  /// zh-TW: '加入遠端歌單…'
  String get addToRemote => '加入遠端歌單…';

  /// zh-TW: '加入遠端歌單（請只選同一個音源的曲目）'
  String get addToRemoteMixed => '加入遠端歌單（請只選同一個音源的曲目）';

  /// zh-TW: '從遠端歌單移除'
  String get removeFromRemote => '從遠端歌單移除';

  /// zh-TW: '加入遠端歌單'
  String get remoteTitle => '加入遠端歌單';

  /// zh-TW: '正在讀取你的歌單'
  String get remoteLoading => '正在讀取你的歌單';

  /// zh-TW: '讀不到你的歌單'
  String get remoteLoadFailed => '讀不到你的歌單';

  /// zh-TW: '還沒有可以加入的歌單'
  String get remoteEmpty => '還沒有可以加入的歌單';

  /// zh-TW: '在遠端新增歌單'
  String get remoteNew => '在遠端新增歌單';

  /// zh-TW: '新增遠端歌單'
  String get remoteNewTitle => '新增遠端歌單';

  /// zh-TW: '名稱'
  String get remoteNewName => '名稱';

  /// zh-TW: '新增'
  String get remoteNewAction => '新增';

  /// zh-TW: '無法新增歌單：{reason}'
  String remoteNewFailed({required Object reason}) => '無法新增歌單：${reason}';

  /// zh-TW: '已加入 {count} 個歌單'
  String remoteAdded({required Object count}) => '已加入 ${count} 個歌單';

  /// zh-TW: '已加入 1 個歌單'
  String get remoteAddedOne => '已加入 1 個歌單';

  /// zh-TW: '，{count} 首已存在'
  String remoteAlreadyThere({required Object count}) => '，${count} 首已存在';

  /// zh-TW: '，{count} 項失敗'
  String remoteFailedCount({required Object count}) => '，${count} 項失敗';

  /// zh-TW: '沒有加入任何歌單'
  String get remoteAddNone => '沒有加入任何歌單';

  /// zh-TW: '無法加入遠端歌單：{reason}'
  String remoteAddError({required Object reason}) => '無法加入遠端歌單：${reason}';

  /// zh-TW: '失敗的項目'
  String get remoteDetailsTitle => '失敗的項目';

  /// zh-TW: '{name}：{count} 項失敗'
  String remoteDetailCount({required Object name, required Object count}) =>
      '${name}：${count} 項失敗';

  /// zh-TW: '沒有說明原因'
  String get remoteNoReason => '沒有說明原因';

  /// zh-TW: '關閉'
  String get remoteClose => '關閉';

  /// zh-TW: '從遠端歌單移除？'
  String get removeRemoteTitle => '從遠端歌單移除？';

  /// zh-TW: '將從「{name}」移除 {count} 首，{source}上的歌單也會一併更新。無法復原。'
  String removeRemoteBody({
    required Object name,
    required Object count,
    required Object source,
  }) => '將從「${name}」移除 ${count} 首，${source}上的歌單也會一併更新。無法復原。';

  /// zh-TW: '移除'
  String get removeRemoteConfirm => '移除';

  /// zh-TW: '已從遠端歌單移除 {count} 首'
  String removedFromRemote({required Object count}) => '已從遠端歌單移除 ${count} 首';

  /// zh-TW: '沒有移除任何曲目'
  String get removeRemoteNone => '沒有移除任何曲目';

  /// zh-TW: '無法從遠端歌單移除：{reason}'
  String removeRemoteFailed({required Object reason}) => '無法從遠端歌單移除：${reason}';
}

// Path: playlist
class Translations$playlist$zh_TW {
  Translations$playlist$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '更多選項'
  String get more => '更多選項';

  /// zh-TW: '播放'
  String get play => '播放';

  /// zh-TW: '下一首播放'
  String get playNext => '下一首播放';

  /// zh-TW: '加入佇列'
  String get addToQueue => '加入佇列';

  /// zh-TW: '下一首播放（Mix 中無法使用）'
  String get playNextInMix => '下一首播放（Mix 中無法使用）';

  /// zh-TW: '加入佇列（Mix 中無法使用）'
  String get addToQueueInMix => '加入佇列（Mix 中無法使用）';

  /// zh-TW: '開始 Mix'
  String get startMix => '開始 Mix';

  /// zh-TW: '已加入下一首播放'
  String get addedToNext => '已加入下一首播放';

  /// zh-TW: '已加入佇列'
  String get addedToQueue => '已加入佇列';

  /// zh-TW: '從歌單移除'
  String get remove => '從歌單移除';

  /// zh-TW: '無法從歌單移除：{reason}'
  String removeFailed({required Object reason}) => '無法從歌單移除：${reason}';

  /// zh-TW: '拖曳以排序'
  String get reorder => '拖曳以排序';

  /// zh-TW: '無法調整曲目順序：{reason}'
  String reorderFailed({required Object reason}) => '無法調整曲目順序：${reason}';

  /// zh-TW: '這張歌單還沒有歌'
  String get empty => '這張歌單還沒有歌';

  /// zh-TW: '在歌曲的選單選「加入歌單…」'
  String get emptyHint => '在歌曲的選單選「加入歌單…」';

  /// zh-TW: '找不到這張歌單'
  String get notFound => '找不到這張歌單';

  /// zh-TW: '已失效'
  String get unavailable => '已失效';

  /// zh-TW: '從歌單移除已選的歌？'
  String get removeTitle => '從歌單移除已選的歌？';

  /// zh-TW: '已選的 {count} 首會從「{name}」移除，無法復原。'
  String removeBody({required Object count, required Object name}) =>
      '已選的 ${count} 首會從「${name}」移除，無法復原。';

  /// zh-TW: '移除'
  String get removeConfirm => '移除';

  /// zh-TW: '取消'
  String get cancel => '取消';

  /// zh-TW: '已從歌單移除'
  String get removed => '已從歌單移除';
}

// Path: selection
class Translations$selection$zh_TW {
  Translations$selection$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '選取'
  String get select => '選取';

  /// zh-TW: '已選 {count} 首'
  String count({required Object count}) => '已選 ${count} 首';

  /// zh-TW: '取消選取（Esc）'
  String get cancelTooltip => '取消選取（Esc）';

  /// zh-TW: '全選（Ctrl+A）'
  String get selectAllTooltip => '全選（Ctrl+A）';

  /// zh-TW: '加入佇列'
  String get addToQueue => '加入佇列';

  /// zh-TW: '加入佇列（Mix 中無法使用）'
  String get addToQueueInMix => '加入佇列（Mix 中無法使用）';

  /// zh-TW: '加入歌單…'
  String get addToPlaylist => '加入歌單…';

  /// zh-TW: '已加入佇列'
  String get addedToQueue => '已加入佇列';

  /// zh-TW: '加入遠端歌單…'
  String get addToRemote => '加入遠端歌單…';

  /// zh-TW: '加入遠端歌單（請只選同一個音源的曲目）'
  String get addToRemoteMixed => '加入遠端歌單（請只選同一個音源的曲目）';

  /// zh-TW: '從遠端歌單移除'
  String get removeFromRemote => '從遠端歌單移除';
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

  /// zh-TW: '關於'
  String get about => '關於';

  /// zh-TW: 'Debug'
  String get debug => 'Debug';
}

// Path: about
class Translations$about$zh_TW {
  Translations$about$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '版本'
  String get version => '版本';

  /// zh-TW: '{version}（{flavor}）'
  String versionValue({required Object version, required Object flavor}) =>
      '${version}（${flavor}）';

  /// zh-TW: '再點 {count} 次即可開啟開發者模式'
  String tapsLeft({required Object count}) => '再點 ${count} 次即可開啟開發者模式';

  /// zh-TW: '已開啟開發者模式'
  String get developerModeOn => '已開啟開發者模式';

  /// zh-TW: '開發者模式已經開啟'
  String get alreadyDeveloper => '開發者模式已經開啟';
}

// Path: debug
class Translations$debug$zh_TW {
  Translations$debug$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: 'Debug'
  String get title => 'Debug';

  /// zh-TW: '概覽'
  String get overview => '概覽';

  /// zh-TW: '開發者模式'
  String get developerMode => '開發者模式';

  /// zh-TW: '關閉後設定頁不再顯示 Debug，log 層級回到預設'
  String get developerModeHint => '關閉後設定頁不再顯示 Debug，log 層級回到預設';

  /// zh-TW: 'Log 層級'
  String get logLevel => 'Log 層級';

  /// zh-TW: 'info'
  String get logLevelInfo => 'info';

  /// zh-TW: 'debug'
  String get logLevelDebug => 'debug';

  /// zh-TW: '多記下細節，log 檔也會變大'
  String get logLevelDebugHint => '多記下細節，log 檔也會變大';

  /// zh-TW: '{level}（預設）'
  String logLevelDefault({required Object level}) => '${level}（預設）';

  /// zh-TW: 'App'
  String get app => 'App';

  /// zh-TW: '版本'
  String get version => '版本';

  /// zh-TW: 'Flavor'
  String get flavor => 'Flavor';

  /// zh-TW: '平台'
  String get platform => '平台';

  /// zh-TW: '資料目錄'
  String get dataDirectory => '資料目錄';

  /// zh-TW: '快取用量'
  String get cacheUsage => '快取用量';

  /// zh-TW: '{size}，在「設定 → 網路」管理'
  String cacheUsageValue({required Object size}) => '${size}，在「設定 → 網路」管理';

  /// zh-TW: '診斷包'
  String get diagnostics => '診斷包';

  /// zh-TW: '這個 App 的版本、插件與設定摘要，加上 log 檔；不含帳號名稱。'
  String get diagnosticsHint => '這個 App 的版本、插件與設定摘要，加上 log 檔；不含帳號名稱。';

  /// zh-TW: '複製摘要'
  String get diagnosticsCopy => '複製摘要';

  /// zh-TW: '存成檔案'
  String get diagnosticsSave => '存成檔案';

  /// zh-TW: '分享'
  String get diagnosticsShare => '分享';

  /// zh-TW: '已複製摘要'
  String get diagnosticsCopied => '已複製摘要';

  /// zh-TW: '已儲存'
  String get exportSaved => '已儲存';

  /// zh-TW: '無法產生檔案：{message}'
  String exportFailed({required Object message}) => '無法產生檔案：${message}';

  /// zh-TW: '檔案裡有這個 App 的版本、插件、設定與最近的 log 紀錄。Cookie、token 與簽名網址已遮蔽，帳號名稱不在裡面，送給任何人之前仍請再檢查一次內容。'
  String get exportReminderBody =>
      '檔案裡有這個 App 的版本、插件、設定與最近的 log 紀錄。Cookie、token 與簽名網址已遮蔽，帳號名稱不在裡面，送給任何人之前仍請再檢查一次內容。';

  /// zh-TW: '匯出 log 檔'
  String get logExport => '匯出 log 檔';

  /// zh-TW: '存成檔案'
  String get logExportSave => '存成檔案';

  /// zh-TW: '分享'
  String get logExportShare => '分享';

  /// zh-TW: 'Log 與錯誤歷史'
  String get log => 'Log 與錯誤歷史';

  /// zh-TW: '網路'
  String get network => '網路';

  /// zh-TW: '取消'
  String get cancel => '取消';

  /// zh-TW: '搜尋 log'
  String get logSearchHint => '搜尋 log';

  /// zh-TW: '所有層級'
  String get filterLevelAll => '所有層級';

  /// zh-TW: '{level} 以上'
  String filterLevelFrom({required Object level}) => '${level} 以上';

  /// zh-TW: '所有 tag'
  String get filterTagAll => '所有 tag';

  /// zh-TW: '只看錯誤'
  String get errorsOnly => '只看錯誤';

  /// zh-TW: '含之前的紀錄'
  String get includeEarlier => '含之前的紀錄';

  /// zh-TW: '正在讀取 log 檔'
  String get earlierLoading => '正在讀取 log 檔';

  /// zh-TW: '無法讀取 log 檔'
  String get earlierFailed => '無法讀取 log 檔';

  /// zh-TW: '{shown} / {total} 筆'
  String logCount({required Object shown, required Object total}) =>
      '${shown} / ${total} 筆';

  /// zh-TW: '沒有紀錄'
  String get logEmpty => '沒有紀錄';

  /// zh-TW: '沒有符合篩選的紀錄'
  String get logNoMatch => '沒有符合篩選的紀錄';

  /// zh-TW: '複製已篩選'
  String get logCopy => '複製已篩選';

  /// zh-TW: '已複製 {count} 筆'
  String logCopied({required Object count}) => '已複製 ${count} 筆';

  /// zh-TW: '沒有可複製的內容'
  String get logCopyNothing => '沒有可複製的內容';

  /// zh-TW: '清除 log'
  String get logClear => '清除 log';

  /// zh-TW: '清除 log？'
  String get logClearTitle => '清除 log？';

  /// zh-TW: '這會刪除這次執行的紀錄與本機上的 log 檔，無法復原。'
  String get logClearBody => '這會刪除這次執行的紀錄與本機上的 log 檔，無法復原。';

  /// zh-TW: '已清除 log'
  String get logCleared => '已清除 log';

  /// zh-TW: '無法刪除 log 檔'
  String get logClearFailed => '無法刪除 log 檔';

  /// zh-TW: '搜尋請求'
  String get netSearchHint => '搜尋請求';

  /// zh-TW: '所有音源'
  String get netSourceAll => '所有音源';

  /// zh-TW: 'App（非插件）'
  String get netSourceApp => 'App（非插件）';

  /// zh-TW: '所有狀態'
  String get netStatusAll => '所有狀態';

  /// zh-TW: '失敗'
  String get netStatusFailed => '失敗';

  /// zh-TW: '沒有網路紀錄'
  String get netEmpty => '沒有網路紀錄';

  /// zh-TW: '這次執行發出的請求會列在這裡。'
  String get netEmptyHint => '這次執行發出的請求會列在這裡。';

  /// zh-TW: '沒有符合篩選的請求'
  String get netNoMatch => '沒有符合篩選的請求';

  /// zh-TW: '{shown} / {total} 筆'
  String netCount({required Object shown, required Object total}) =>
      '${shown} / ${total} 筆';

  /// zh-TW: '—'
  String get netUnknown => '—';

  /// zh-TW: '網址'
  String get netDetailUrl => '網址';

  /// zh-TW: 'Query'
  String get netDetailQuery => 'Query';

  /// zh-TW: '無'
  String get netDetailNoQuery => '無';

  /// zh-TW: '狀態'
  String get netDetailStatus => '狀態';

  /// zh-TW: '耗時'
  String get netDetailDuration => '耗時';

  /// zh-TW: '大小'
  String get netDetailSize => '大小';

  /// zh-TW: '音源'
  String get netDetailSource => '音源';

  /// zh-TW: 'Client'
  String get netDetailClient => 'Client';

  /// zh-TW: '有帶憑證'
  String get netDetailCredentials => '有帶憑證';

  /// zh-TW: '重試次數'
  String get netDetailRetry => '重試次數';

  /// zh-TW: '錯誤類型'
  String get netDetailError => '錯誤類型';

  /// zh-TW: '無'
  String get netDetailNoError => '無';

  /// zh-TW: '對應的錯誤紀錄'
  String get netDetailRelated => '對應的錯誤紀錄';

  /// zh-TW: '無'
  String get netDetailNoRelated => '無';

  /// zh-TW: '時間'
  String get netDetailTime => '時間';

  /// zh-TW: '是'
  String get yes => '是';

  /// zh-TW: '否'
  String get no => '否';

  /// zh-TW: '{ms} ms'
  String netDuration({required Object ms}) => '${ms} ms';

  /// zh-TW: '關閉'
  String get close => '關閉';

  /// zh-TW: '詳細'
  String get logDetail => '詳細';

  /// zh-TW: '播放狀態'
  String get playback => '播放狀態';

  /// zh-TW: '資料庫'
  String get database => '資料庫';

  /// zh-TW: '音源健康檢查'
  String get health => '音源健康檢查';

  /// zh-TW: '對已安裝且啟用的插件用真實連線跑檢查案例（需要登入的案例用已存的憑證）。一次只檢查一個插件。'
  String get hcHint => '對已安裝且啟用的插件用真實連線跑檢查案例（需要登入的案例用已存的憑證）。一次只檢查一個插件。';

  /// zh-TW: '全部檢查'
  String get hcAll => '全部檢查';

  /// zh-TW: '檢查'
  String get hcCheck => '檢查';

  /// zh-TW: '檢查中…'
  String get hcChecking => '檢查中…';

  /// zh-TW: '沒有檢查案例'
  String get hcNone => '沒有檢查案例';

  /// zh-TW: '已停用'
  String get hcDisabled => '已停用';

  /// zh-TW: '{count} 個案例'
  String hcCount({required Object count}) => '${count} 個案例';

  /// zh-TW: '檢查案例讀不懂'
  String get hcUnreadable => '檢查案例讀不懂';

  /// zh-TW: '通過'
  String get hcPassed => '通過';

  /// zh-TW: '失敗'
  String get hcFailed => '失敗';

  /// zh-TW: '略過（未登入）'
  String get hcSkipped => '略過（未登入）';

  /// zh-TW: '略過（會改動遠端）'
  String get hcSkippedMutates => '略過（會改動遠端）';

  /// zh-TW: '無法檢查：{problem}'
  String hcProblem({required Object problem}) => '無法檢查：${problem}';

  /// zh-TW: '無法檢查：插件沒有載入（見 log）'
  String get hcNotLoaded => '無法檢查：插件沒有載入（見 log）';

  /// zh-TW: '還沒有安裝的插件'
  String get hcEmpty => '還沒有安裝的插件';

  /// zh-TW: '{capability} · {outcome} · {ms} ms'
  String hcCase({
    required Object capability,
    required Object outcome,
    required Object ms,
  }) => '${capability} · ${outcome} · ${ms} ms';

  /// zh-TW: '錯誤類別：{type}'
  String hcErrorType({required Object type}) => '錯誤類別：${type}';

  /// zh-TW: '插件開發'
  String get pluginDev => '插件開發';

  /// zh-TW: '資料夾裡的每個插件目錄（一個 .js、checks.json、fixtures/）載入成「開發中」，取代同 id 的已安裝版；改了檔案按「重新載入」。模式只決定「執行」案例的方式，每個案例在獨立的環境（空的儲存與憑證）裡跑；App 其他地方用到的開發中插件一律真實連線。'
  String get pdHint =>
      '資料夾裡的每個插件目錄（一個 .js、checks.json、fixtures/）載入成「開發中」，取代同 id 的已安裝版；改了檔案按「重新載入」。模式只決定「執行」案例的方式，每個案例在獨立的環境（空的儲存與憑證）裡跑；App 其他地方用到的開發中插件一律真實連線。';

  /// zh-TW: '資料夾'
  String get pdFolder => '資料夾';

  /// zh-TW: '還沒選資料夾'
  String get pdNoFolder => '還沒選資料夾';

  /// zh-TW: '選擇資料夾'
  String get pdPick => '選擇資料夾';

  /// zh-TW: '重新掃描'
  String get pdRescan => '重新掃描';

  /// zh-TW: '卸載'
  String get pdUnload => '卸載';

  /// zh-TW: '載入中…'
  String get pdApplying => '載入中…';

  /// zh-TW: '資料夾不存在'
  String get pdFolderMissing => '資料夾不存在';

  /// zh-TW: '資料夾裡沒有插件目錄（含一個 .js 檔的資料夾）'
  String get pdFolderEmpty => '資料夾裡沒有插件目錄（含一個 .js 檔的資料夾）';

  /// zh-TW: '{first} 與 {second} 的插件 id 都是「{id}」，只載入 {first}'
  String pdDuplicateId({
    required Object first,
    required Object second,
    required Object id,
  }) => '${first} 與 ${second} 的插件 id 都是「${id}」，只載入 ${first}';

  /// zh-TW: '取代已安裝 {version}'
  String pdTagReplaces({required Object version}) => '取代已安裝 ${version}';

  /// zh-TW: '載入失敗'
  String get pdTagFailed => '載入失敗';

  /// zh-TW: '插件 id 改成了「{id}」，請重新掃描資料夾'
  String pdIdChanged({required Object id}) => '插件 id 改成了「${id}」，請重新掃描資料夾';

  /// zh-TW: '重播'
  String get pdReplay => '重播';

  /// zh-TW: '錄製'
  String get pdRecord => '錄製';

  /// zh-TW: '真實'
  String get pdReal => '真實';

  /// zh-TW: '重新載入'
  String get pdReload => '重新載入';

  /// zh-TW: '查看 log'
  String get pdViewLog => '查看 log';

  /// zh-TW: '全部執行'
  String get pdRunAll => '全部執行';

  /// zh-TW: '執行'
  String get pdRun => '執行';

  /// zh-TW: '執行中'
  String get pdRunning => '執行中';

  /// zh-TW: '錄製以真實連線執行；結果符合 checks.json 才會覆寫 fixtures/ 裡該能力的檔案（手改過的略過）。誤錄請在插件資料夾用 git checkout 還原。'
  String get pdRecordWarning =>
      '錄製以真實連線執行；結果符合 checks.json 才會覆寫 fixtures/ 裡該能力的檔案（手改過的略過）。誤錄請在插件資料夾用 git checkout 還原。';

  /// zh-TW: '沒有檢查案例'
  String get pdNoCases => '沒有檢查案例';

  /// zh-TW: '{outcome} · {ms} ms · {mode}'
  String pdCaseLine({
    required Object outcome,
    required Object ms,
    required Object mode,
  }) => '${outcome} · ${ms} ms · ${mode}';

  /// zh-TW: '通過'
  String get pdPassed => '通過';

  /// zh-TW: '失敗'
  String get pdFailed => '失敗';

  /// zh-TW: '略過：需要登入，目前沒有登入'
  String get pdSkippedLogin => '略過：需要登入，目前沒有登入';

  /// zh-TW: '略過：fixture 是手改過的'
  String get pdSkippedEdited => '略過：fixture 是手改過的';

  /// zh-TW: '略過：會改動遠端'
  String get pdSkippedMutates => '略過：會改動遠端';

  /// zh-TW: '還沒執行'
  String get pdNotRun => '還沒執行';

  /// zh-TW: '錯誤類別：{type}'
  String pdErrorType({required Object type}) => '錯誤類別：${type}';

  /// zh-TW: '已寫入 {count} 個 fixture'
  String pdWritten({required Object count}) => '已寫入 ${count} 個 fixture';

  /// zh-TW: '沒有寫入 fixture'
  String get pdNotWritten => '沒有寫入 fixture';

  /// zh-TW: '回傳值'
  String get pdValue => '回傳值';

  /// zh-TW: '（太長，已截斷）'
  String get pdTruncated => '（太長，已截斷）';

  /// zh-TW: '複製'
  String get pdCopy => '複製';

  /// zh-TW: '已重新載入 {name} {version}'
  String pdReloaded({required Object name, required Object version}) =>
      '已重新載入 ${name} ${version}';

  /// zh-TW: '重新載入失敗：{name}'
  String pdReloadFailed({required Object name}) => '重新載入失敗：${name}';

  /// zh-TW: '沒有在播放'
  String get pbEmpty => '沒有在播放';

  /// zh-TW: '播放或排入佇列後，這裡會顯示後端、串流與佇列的狀態。'
  String get pbEmptyHint => '播放或排入佇列後，這裡會顯示後端、串流與佇列的狀態。';

  /// zh-TW: '複製快照'
  String get pbCopy => '複製快照';

  /// zh-TW: '已複製快照'
  String get pbCopied => '已複製快照';

  /// zh-TW: '狀態'
  String get pbState => '狀態';

  /// zh-TW: '閒置'
  String get pbStateIdle => '閒置';

  /// zh-TW: '載入中'
  String get pbStateLoading => '載入中';

  /// zh-TW: '播放中'
  String get pbStatePlaying => '播放中';

  /// zh-TW: '已暫停'
  String get pbStatePaused => '已暫停';

  /// zh-TW: '緩衝中'
  String get pbStateBuffering => '緩衝中';

  /// zh-TW: '等待重試'
  String get pbStateRetrying => '等待重試';

  /// zh-TW: '等網路'
  String get pbStateWaitingNetwork => '等網路';

  /// zh-TW: '已停止'
  String get pbStateFailed => '已停止';

  /// zh-TW: '錯誤類型'
  String get pbError => '錯誤類型';

  /// zh-TW: '重試次數'
  String get pbRetryAttempt => '重試次數';

  /// zh-TW: '下次重試'
  String get pbNextRetry => '下次重試';

  /// zh-TW: '曲目'
  String get pbTrack => '曲目';

  /// zh-TW: '插件'
  String get pbPlugin => '插件';

  /// zh-TW: '後端'
  String get pbBackend => '後端';

  /// zh-TW: '輸出裝置'
  String get pbOutputDevice => '輸出裝置';

  /// zh-TW: '系統預設或不適用'
  String get pbOutputDefault => '系統預設或不適用';

  /// zh-TW: '串流'
  String get pbStream => '串流';

  /// zh-TW: '網路'
  String get pbSourceNetwork => '網路';

  /// zh-TW: '內附 asset'
  String get pbSourceAsset => '內附 asset';

  /// zh-TW: '候選 {index} / {count}'
  String pbCandidate({required Object index, required Object count}) =>
      '候選 ${index} / ${count}';

  /// zh-TW: '—'
  String get pbUnknown => '—';

  /// zh-TW: '位置'
  String get pbPosition => '位置';

  /// zh-TW: '佇列'
  String get pbQueue => '佇列';

  /// zh-TW: '佇列是空的'
  String get pbQueueEmpty => '佇列是空的';

  /// zh-TW: '共 {total} 首，目前第 {index} 首'
  String pbQueueSummary({required Object total, required Object index}) =>
      '共 ${total} 首，目前第 ${index} 首';

  /// zh-TW: '前面'
  String get pbBefore => '前面';

  /// zh-TW: '後面'
  String get pbAfter => '後面';

  /// zh-TW: '無'
  String get pbNone => '無';

  /// zh-TW: '隨機'
  String get pbShuffle => '隨機';

  /// zh-TW: '循環'
  String get pbLoop => '循環';

  /// zh-TW: '關閉'
  String get pbLoopOff => '關閉';

  /// zh-TW: '全部'
  String get pbLoopAll => '全部';

  /// zh-TW: '單曲'
  String get pbLoopOne => '單曲';

  /// zh-TW: '臨時播放中（目前位置是回到佇列時的那一首）'
  String get pbTemporary => '臨時播放中（目前位置是回到佇列時的那一首）';

  /// zh-TW: '直播中（停止後回到佇列）'
  String get pbLive => '直播中（停止後回到佇列）';

  /// zh-TW: '直播間'
  String get pbLiveRoom => '直播間';

  /// zh-TW: 'Mix'
  String get pbMix => 'Mix';

  /// zh-TW: '資料表'
  String get dbTables => '資料表';

  /// zh-TW: '{count} 筆'
  String dbRowCount({required Object count}) => '${count} 筆';

  /// zh-TW: '回到資料表清單'
  String get dbBack => '回到資料表清單';

  /// zh-TW: '第 {page} / {pages} 頁，共 {total} 筆'
  String dbPage({
    required Object page,
    required Object pages,
    required Object total,
  }) => '第 ${page} / ${pages} 頁，共 ${total} 筆';

  /// zh-TW: '上一頁'
  String get dbPrevious => '上一頁';

  /// zh-TW: '下一頁'
  String get dbNext => '下一頁';

  /// zh-TW: '這張表沒有資料'
  String get dbNoRows => '這張表沒有資料';

  /// zh-TW: 'NULL'
  String get dbNull => 'NULL';

  /// zh-TW: '無法讀取資料庫'
  String get dbLoadFailed => '無法讀取資料庫';

  /// zh-TW: '檢查'
  String get dbCheck => '檢查';

  /// zh-TW: '檢查中…'
  String get dbChecking => '檢查中…';

  /// zh-TW: '沒有發現問題'
  String get dbCheckClean => '沒有發現問題';

  /// zh-TW: '發現問題'
  String get dbCheckProblems => '發現問題';

  /// zh-TW: '完整性（integrity_check）'
  String get dbIntegrity => '完整性（integrity_check）';

  /// zh-TW: '外鍵（foreign_key_check）'
  String get dbForeignKeys => '外鍵（foreign_key_check）';

  /// zh-TW: '正常'
  String get dbOk => '正常';

  /// zh-TW: '{table} 的 rowid {rowId} 找不到父表 {parent} 的列'
  String dbViolation({
    required Object table,
    required Object rowId,
    required Object parent,
  }) => '${table} 的 rowid ${rowId} 找不到父表 ${parent} 的列';

  /// zh-TW: '孤兒曲目'
  String get dbOrphans => '孤兒曲目';

  /// zh-TW: '{count} 首（啟動時會自動清掉，不算損壞）'
  String dbOrphansValue({required Object count}) => '${count} 首（啟動時會自動清掉，不算損壞）';

  /// zh-TW: '檢查失敗'
  String get dbCheckFailed => '檢查失敗';

  /// zh-TW: '重設資料'
  String get reset => '重設資料';

  /// zh-TW: '清空資料庫（含設定、歌單、佇列與播放歷史）、所有音源的登入憑證、登入網頁的資料與快取，然後重啟 App。不會動 log 檔、備份與已下載的檔案。'
  String get resetBody =>
      '清空資料庫（含設定、歌單、佇列與播放歷史）、所有音源的登入憑證、登入網頁的資料與快取，然後重啟 App。不會動 log 檔、備份與已下載的檔案。';

  /// zh-TW: '清空之前會先把資料庫備份到資料目錄的 backups 資料夾；備份失敗就什麼都不清。憑證不在備份裡，還原後要重新登入。'
  String get resetBackupNote =>
      '清空之前會先把資料庫備份到資料目錄的 backups 資料夾；備份失敗就什麼都不清。憑證不在備份裡，還原後要重新登入。';

  /// zh-TW: '重設資料…'
  String get resetButton => '重設資料…';

  /// zh-TW: '無法備份資料庫，沒有清除任何資料：{message}'
  String resetBackupFailed({required Object message}) =>
      '無法備份資料庫，沒有清除任何資料：${message}';

  /// zh-TW: '重設所有資料？'
  String get resetConfirmTitle => '重設所有資料？';

  /// zh-TW: '資料庫已備份到 {path}。按下「清空並重啟」會清空資料庫、憑證、登入網頁的資料與快取，除了這份備份之外無法復原。'
  String resetConfirmBody({required Object path}) =>
      '資料庫已備份到 ${path}。按下「清空並重啟」會清空資料庫、憑證、登入網頁的資料與快取，除了這份備份之外無法復原。';

  /// zh-TW: '完成後 App 會自動重新啟動。'
  String get resetRestartsItself => '完成後 App 會自動重新啟動。';

  /// zh-TW: '完成後 App 會關閉，請自己重新開啟。'
  String get resetRestartsManually => '完成後 App 會關閉，請自己重新開啟。';

  /// zh-TW: '我了解這會清空所有資料'
  String get resetUnderstand => '我了解這會清空所有資料';

  /// zh-TW: '清空並重啟'
  String get resetConfirm => '清空並重啟';

  /// zh-TW: '正在清空…'
  String get resetWorking => '正在清空…';

  /// zh-TW: '重設沒有完成：{message}'
  String resetFailed({required Object message}) => '重設沒有完成：${message}';

  /// zh-TW: '立即備份'
  String get dbBackUp => '立即備份';

  /// zh-TW: '已備份到 {path}'
  String dbBackedUp({required Object path}) => '已備份到 ${path}';

  /// zh-TW: '無法備份資料庫：{message}'
  String dbBackUpFailed({required Object message}) => '無法備份資料庫：${message}';

  /// zh-TW: '從備份還原'
  String get dbRestore => '從備份還原';

  /// zh-TW: '選擇要還原的備份'
  String get dbRestoreTitle => '選擇要還原的備份';

  /// zh-TW: '沒有備份。先按「立即備份」，或重設資料時會自動建立。'
  String get dbRestoreEmpty => '沒有備份。先按「立即備份」，或重設資料時會自動建立。';

  /// zh-TW: '無法讀取備份清單：{message}'
  String dbRestoreListFailed({required Object message}) =>
      '無法讀取備份清單：${message}';

  /// zh-TW: '從這份備份還原？'
  String get dbRestoreConfirmTitle => '從這份備份還原？';

  /// zh-TW: '備份時間：{time}。目前的資料庫會改名留在資料目錄（fmp.db.before-restore-…），換成這份備份。備份不含登入憑證，還原後要重新登入。'
  String dbRestoreConfirmBody({required Object time}) =>
      '備份時間：${time}。目前的資料庫會改名留在資料目錄（fmp.db.before-restore-…），換成這份備份。備份不含登入憑證，還原後要重新登入。';

  /// zh-TW: '還原並重啟'
  String get dbRestoreConfirm => '還原並重啟';

  /// zh-TW: '正在還原…'
  String get dbRestoreWorking => '正在還原…';

  /// zh-TW: '還原沒有完成：{message}'
  String dbRestoreFailed({required Object message}) => '還原沒有完成：${message}';

  /// zh-TW: '可以從備份還原，或重設資料。'
  String get dbCheckProblemsActions => '可以從備份還原，或重設資料。';
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

  /// zh-TW: 'Mix 中無法隨機播放'
  String get shuffleInMixTooltip => 'Mix 中無法隨機播放';

  /// zh-TW: '隨機播放（Mix 中無法使用）'
  String get shuffleInMix => '隨機播放（Mix 中無法使用）';

  /// zh-TW: '循環：關閉（Ctrl+R）'
  String get loopOffTooltip => '循環：關閉（Ctrl+R）';

  /// zh-TW: '循環：全部（Ctrl+R）'
  String get loopAllTooltip => '循環：全部（Ctrl+R）';

  /// zh-TW: '循環：單曲（Ctrl+R）'
  String get loopOneTooltip => '循環：單曲（Ctrl+R）';

  /// zh-TW: '循環：關閉（Mix 中沒有「全部」）'
  String get loopOffInMix => '循環：關閉（Mix 中沒有「全部」）';

  /// zh-TW: '循環：單曲（Mix 中沒有「全部」）'
  String get loopOneInMix => '循環：單曲（Mix 中沒有「全部」）';

  /// zh-TW: '循環：關閉（Ctrl+R；Mix 中沒有「全部」）'
  String get loopOffInMixTooltip => '循環：關閉（Ctrl+R；Mix 中沒有「全部」）';

  /// zh-TW: '循環：單曲（Ctrl+R；Mix 中沒有「全部」）'
  String get loopOneInMixTooltip => '循環：單曲（Ctrl+R；Mix 中沒有「全部」）';

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

  /// zh-TW: '直播中'
  String get liveBadge => '直播中';

  /// zh-TW: '直播已結束'
  String get liveEnded => '直播已結束';

  /// zh-TW: '查詢失敗'
  String get liveStatusFailed => '查詢失敗';

  /// zh-TW: '已停止'
  String get liveStopped => '已停止';

  /// zh-TW: '重新連線中'
  String get liveReconnecting => '重新連線中';

  /// zh-TW: '無法播放：{reason}'
  String liveCannotPlay({required Object reason}) => '無法播放：${reason}';

  /// zh-TW: '已收聽 {time}'
  String liveListened({required Object time}) => '已收聽 ${time}';

  /// zh-TW: '{count} 人在看'
  String liveOnline({required Object count}) => '${count} 人在看';

  /// zh-TW: '停止收聽'
  String get stopLive => '停止收聽';

  /// zh-TW: '主播'
  String get liveHost => '主播';

  /// zh-TW: '觀看人數'
  String get liveViewers => '觀看人數';
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

  /// zh-TW: '發佈時間'
  String get detailsPublished => '發佈時間';

  /// zh-TW: '專輯'
  String get detailsAlbum => '專輯';

  /// zh-TW: '簡介'
  String get detailsDescription => '簡介';

  /// zh-TW: '展開'
  String get detailsExpand => '展開';

  /// zh-TW: '收起'
  String get detailsCollapse => '收起';

  /// zh-TW: '正在載入詳細資料'
  String get detailsLoading => '正在載入詳細資料';

  /// zh-TW: '無法取得詳細資料'
  String get detailsFailed => '無法取得詳細資料';

  /// zh-TW: '重試'
  String get detailsRetry => '重試';

  /// zh-TW: '播放'
  String get statView => '播放';

  /// zh-TW: '按讚'
  String get statLike => '按讚';

  /// zh-TW: '收藏'
  String get statFavorite => '收藏';

  /// zh-TW: '評論'
  String get statComment => '評論';

  /// zh-TW: '分享'
  String get statShare => '分享';

  /// zh-TW: '彈幕'
  String get statDanmaku => '彈幕';

  /// zh-TW: '投幣'
  String get statCoin => '投幣';

  /// zh-TW: '佇列（Ctrl+Q）'
  String get queueTooltip => '佇列（Ctrl+Q）';

  /// zh-TW: '共 {count} 首'
  String queueCount({required Object count}) => '共 ${count} 首';

  /// zh-TW: '隨機順序跟著位置；拖曳只換歌，不改順序'
  String get queueShuffleNote => '隨機順序跟著位置；拖曳只換歌，不改順序';

  /// zh-TW: 'Mix：{title}'
  String queueMixNote({required Object title}) => 'Mix：${title}';

  /// zh-TW: '開始 Mix'
  String get queueStartMix => '開始 Mix';

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

  /// zh-TW: '電台狀態刷新間隔'
  String get radioInterval => '電台狀態刷新間隔';

  /// zh-TW: '多久查一次電台是否開播；App 在背景或離線時不查。'
  String get radioIntervalHint => '多久查一次電台是否開播；App 在背景或離線時不查。';

  /// zh-TW: '關閉'
  String get radioIntervalOff => '關閉';

  /// zh-TW: '{minutes} 分鐘'
  String radioIntervalMinutes({required Object minutes}) => '${minutes} 分鐘';

  /// zh-TW: '排行刷新間隔'
  String get chartInterval => '排行刷新間隔';

  /// zh-TW: '多久更新一次首頁的排行；App 在背景或離線時不更新。'
  String get chartIntervalHint => '多久更新一次首頁的排行；App 在背景或離線時不更新。';

  /// zh-TW: '關閉'
  String get chartIntervalOff => '關閉';

  /// zh-TW: '{minutes} 分鐘'
  String chartIntervalMinutes({required Object minutes}) => '${minutes} 分鐘';

  /// zh-TW: '{label}（預設）'
  String optionDefault({required Object label}) => '${label}（預設）';
}

// Path: radio
class Translations$radio$zh_TW {
  Translations$radio$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '電台'
  String get title => '電台';

  /// zh-TW: '以網址新增'
  String get addFromUrl => '以網址新增';

  /// zh-TW: '刷新狀態'
  String get refresh => '刷新狀態';

  /// zh-TW: '以網址新增電台'
  String get urlTitle => '以網址新增電台';

  /// zh-TW: '直播間網址'
  String get urlLabel => '直播間網址';

  /// zh-TW: '新增'
  String get add => '新增';

  /// zh-TW: '取消'
  String get cancel => '取消';

  /// zh-TW: '已加入電台'
  String get added => '已加入電台';

  /// zh-TW: '已在電台清單'
  String get alreadyAdded => '已在電台清單';

  /// zh-TW: '無法辨識這個網址'
  String get unrecognizedUrl => '無法辨識這個網址';

  /// zh-TW: '無法新增電台：{reason}'
  String addFailed({required Object reason}) => '無法新增電台：${reason}';

  /// zh-TW: '已更新電台狀態'
  String get refreshed => '已更新電台狀態';

  /// zh-TW: '沒有可以刷新的電台'
  String get nothingToRefresh => '沒有可以刷新的電台';

  /// zh-TW: '無法刷新狀態：{reason}'
  String refreshFailed({required Object reason}) => '無法刷新狀態：${reason}';

  /// zh-TW: '離線中，沒有刷新：顯示的是上次查到的狀態'
  String get refreshOffline => '離線中，沒有刷新：顯示的是上次查到的狀態';

  /// zh-TW: '重試'
  String get retry => '重試';

  /// zh-TW: '處理中'
  String get working => '處理中';

  /// zh-TW: '還沒有電台'
  String get empty => '還沒有電台';

  /// zh-TW: '在搜尋頁切到「直播間」，從結果的選單「加為電台」；或以直播間的網址新增。'
  String get emptyHint => '在搜尋頁切到「直播間」，從結果的選單「加為電台」；或以直播間的網址新增。';

  /// zh-TW: '開播中'
  String get statusLive => '開播中';

  /// zh-TW: '未開播'
  String get statusOffline => '未開播';

  /// zh-TW: '查詢失敗'
  String get statusFailed => '查詢失敗';

  /// zh-TW: '還沒查過'
  String get statusUnchecked => '還沒查過';

  /// zh-TW: '更多選項'
  String get more => '更多選項';

  /// zh-TW: '刪除'
  String get remove => '刪除';

  /// zh-TW: '刪除電台？'
  String get removeTitle => '刪除電台？';

  /// zh-TW: '「{title}」會從電台清單移除。'
  String removeBody({required Object title}) => '「${title}」會從電台清單移除。';

  /// zh-TW: '已刪除電台'
  String get removed => '已刪除電台';

  /// zh-TW: '無法刪除電台：{reason}'
  String removeFailed({required Object reason}) => '無法刪除電台：${reason}';

  /// zh-TW: '拖曳以排序'
  String get reorder => '拖曳以排序';

  /// zh-TW: '無法調整順序：{reason}'
  String reorderFailed({required Object reason}) => '無法調整順序：${reason}';

  /// zh-TW: '無法收聽：{reason}'
  String cannotPlay({required Object reason}) => '無法收聽：${reason}';
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

  /// zh-TW: '開發中'
  String get tagDev => '開發中';

  /// zh-TW: '開發中的插件由 Debug 頁「插件開發」管理，卸載後才能啟用、更新或移除。'
  String get devManaged => '開發中的插件由 Debug 頁「插件開發」管理，卸載後才能啟用、更新或移除。';

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

  /// zh-TW: '登入'
  String get signIn => '登入';

  /// zh-TW: '{name}的登入已失效'
  String invalidatedPrompt({required Object name}) => '${name}的登入已失效';

  /// zh-TW: '最後刷新：{time}，{result}'
  String lastRefresh({required Object time, required Object result}) =>
      '最後刷新：${time}，${result}';

  /// zh-TW: '已更新憑證'
  String get refreshRefreshed => '已更新憑證';

  /// zh-TW: '不需要更新'
  String get refreshUnchanged => '不需要更新';

  /// zh-TW: '失敗'
  String get refreshFailed => '失敗';

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
  String get verifying => '正在確認登入';

  /// zh-TW: '重新產生'
  String get qrRegenerate => '重新產生';

  /// zh-TW: '重試'
  String get retry => '重試';

  /// zh-TW: '關閉'
  String get close => '關閉';

  /// zh-TW: '登入「{name}」'
  String webTitle({required Object name}) => '登入「${name}」';

  /// zh-TW: '正在開啟登入頁'
  String get webLoading => '正在開啟登入頁';

  /// zh-TW: '登入沒有完成'
  String get webStuckTitle => '登入沒有完成';

  /// zh-TW: '頁面停在跳轉中。按「重試」重新開啟登入頁，通常不必再輸入一次帳號密碼。'
  String get webStuckBody => '頁面停在跳轉中。按「重試」重新開啟登入頁，通常不必再輸入一次帳號密碼。';

  /// zh-TW: '還是沒有完成。請關閉 FMP 再重新開啟，然後再按一次「網頁登入」；網頁上的登入狀態會保留。'
  String get webStuckRestart =>
      '還是沒有完成。請關閉 FMP 再重新開啟，然後再按一次「網頁登入」；網頁上的登入狀態會保留。';

  /// zh-TW: '無法開啟登入頁'
  String get webFailed => '無法開啟登入頁';

  /// zh-TW: '貼上「{name}」的 cookie'
  String cookieTitle({required Object name}) => '貼上「${name}」的 cookie';

  /// zh-TW: 'Cookie'
  String get cookieLabel => 'Cookie';

  /// zh-TW: 'name=value; name2=value2'
  String get cookieHint => 'name=value; name2=value2';

  /// zh-TW: '如何取得'
  String get cookieHelpTitle => '如何取得';

  /// zh-TW: '在電腦的瀏覽器登入這個網站。'
  String get cookieStep1 => '在電腦的瀏覽器登入這個網站。';

  /// zh-TW: '按 F12 開啟開發者工具，在「網路」分頁重新整理頁面，選一個送往這個網站的請求。'
  String get cookieStep2 => '按 F12 開啟開發者工具，在「網路」分頁重新整理頁面，選一個送往這個網站的請求。';

  /// zh-TW: '在請求標頭找到「Cookie」，複製整個值貼在上面。'
  String get cookieStep3 => '在請求標頭找到「Cookie」，複製整個值貼在上面。';

  /// zh-TW: '也可以貼上瀏覽器擴充功能匯出的 cookies.txt（Netscape 格式）內容。'
  String get cookieFile => '也可以貼上瀏覽器擴充功能匯出的 cookies.txt（Netscape 格式）內容。';

  /// zh-TW: 'Cookie 等同你的登入，不要交給別人。FMP 只把它存在這台裝置上。'
  String get cookieWarning => 'Cookie 等同你的登入，不要交給別人。FMP 只把它存在這台裝置上。';

  /// zh-TW: '沒有讀到 cookie。請貼上 name=value 的內容或 cookies.txt。'
  String get cookieEmpty => '沒有讀到 cookie。請貼上 name=value 的內容或 cookies.txt。';

  /// zh-TW: '「{name}」不接受這些 cookie。請從已登入的頁面重新複製。'
  String cookieRejected({required Object name}) =>
      '「${name}」不接受這些 cookie。請從已登入的頁面重新複製。';

  /// zh-TW: '「{name}」沒有接受這次登入，請再試一次。'
  String loginRejected({required Object name}) => '「${name}」沒有接受這次登入，請再試一次。';

  /// zh-TW: '歌單'
  String get playlists => '歌單';

  /// zh-TW: '{name} 的歌單'
  String playlistsTitle({required Object name}) => '${name} 的歌單';

  /// zh-TW: '這個帳號還沒有歌單'
  String get playlistsEmpty => '這個帳號還沒有歌單';

  /// zh-TW: '無法讀取歌單'
  String get playlistsFailed => '無法讀取歌單';

  /// zh-TW: '可寫'
  String get playlistWritable => '可寫';

  /// zh-TW: '已匯入'
  String get playlistImported => '已匯入';

  /// zh-TW: '選取「{name}」'
  String playlistSelect({required Object name}) => '選取「${name}」';

  /// zh-TW: '匯入所選 ({count})'
  String importSelected({required Object count}) => '匯入所選 (${count})';

  /// zh-TW: '匯入中 {done}／{total}'
  String importingProgress({required Object done, required Object total}) =>
      '匯入中 ${done}／${total}';

  /// zh-TW: '匯入失敗：{reason}'
  String playlistImportFailed({required Object reason}) => '匯入失敗：${reason}';

  /// zh-TW: '這個來源還不能匯入歌單'
  String get playlistUnsupported => '這個來源還不能匯入歌單';

  /// zh-TW: '已匯入 {count} 張'
  String importedCount({required Object count}) => '已匯入 ${count} 張';

  /// zh-TW: '已匯入 {count} 張，{failed} 張失敗'
  String importedWithFailures({
    required Object count,
    required Object failed,
  }) => '已匯入 ${count} 張，${failed} 張失敗';

  /// zh-TW: '更多選項'
  String get more => '更多選項';

  /// zh-TW: '從帳號匯入電台'
  String get liveImport => '從帳號匯入電台';

  /// zh-TW: '新增 {added} 個，{existing} 個已在電台清單'
  String liveImportBoth({required Object added, required Object existing}) =>
      '新增 ${added} 個，${existing} 個已在電台清單';

  /// zh-TW: '新增 {added} 個'
  String liveImportAdded({required Object added}) => '新增 ${added} 個';

  /// zh-TW: '{existing} 個已在電台清單'
  String liveImportAllExisting({required Object existing}) =>
      '${existing} 個已在電台清單';

  /// zh-TW: '這個帳號沒有關注的直播間'
  String get liveImportEmpty => '這個帳號沒有關注的直播間';

  /// zh-TW: '無法匯入電台：{reason}'
  String liveImportFailed({required Object reason}) => '無法匯入電台：${reason}';
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

// Path: errorReport
class Translations$errorReport$zh_TW {
  Translations$errorReport$zh_TW.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-TW: '錯誤詳細'
  String get title => '錯誤詳細';

  /// zh-TW: '詳細'
  String get actionDetail => '詳細';

  /// zh-TW: '回報'
  String get actionReport => '回報';

  /// zh-TW: '複製'
  String get copy => '複製';

  /// zh-TW: '已複製'
  String get copied => '已複製';

  /// zh-TW: '在 GitHub 回報'
  String get reportOnGitHub => '在 GitHub 回報';

  /// zh-TW: '報告已複製，請貼到 GitHub 的「錯誤報告」欄位'
  String get reportCopied => '報告已複製，請貼到 GitHub 的「錯誤報告」欄位';

  /// zh-TW: '無法開啟瀏覽器，請自行開啟下方的網址'
  String get openFailed => '無法開啟瀏覽器，請自行開啟下方的網址';

  /// zh-TW: '請在瀏覽器開啟以下網址，並貼上已複製的報告'
  String get manualHint => '請在瀏覽器開啟以下網址，並貼上已複製的報告';

  /// zh-TW: '送出前請檢查'
  String get reminderTitle => '送出前請檢查';

  /// zh-TW: 'FMP 的 GitHub repo 是公開的，所有人都看得到報告。報告已遮蔽 cookie、token 與簽名網址，但送出前請再檢查一次內容。'
  String get reminderBody =>
      'FMP 的 GitHub repo 是公開的，所有人都看得到報告。報告已遮蔽 cookie、token 與簽名網址，但送出前請再檢查一次內容。';

  /// zh-TW: '不再提醒'
  String get reminderDontAsk => '不再提醒';

  /// zh-TW: '繼續'
  String get reminderContinue => '繼續';

  /// zh-TW: '取消'
  String get cancel => '取消';

  /// zh-TW: '時間'
  String get time => '時間';

  /// zh-TW: '錯誤類型'
  String get type => '錯誤類型';

  /// zh-TW: '原因類別'
  String get reason => '原因類別';

  /// zh-TW: '音源'
  String get source => '音源';

  /// zh-TW: '使用者動作'
  String get action => '使用者動作';

  /// zh-TW: '模組'
  String get module => '模組';

  /// zh-TW: '請求'
  String get request => '請求';

  /// zh-TW: '狀態碼'
  String get status => '狀態碼';

  /// zh-TW: '耗時'
  String get duration => '耗時';

  /// zh-TW: '請求錯誤'
  String get requestError => '請求錯誤';

  /// zh-TW: '沒有對應的請求紀錄'
  String get noRequest => '沒有對應的請求紀錄';

  /// zh-TW: 'App'
  String get app => 'App';

  /// zh-TW: '系統'
  String get system => '系統';

  /// zh-TW: '原因'
  String get cause => '原因';

  /// zh-TW: 'Stack trace'
  String get stackTrace => 'Stack trace';
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
