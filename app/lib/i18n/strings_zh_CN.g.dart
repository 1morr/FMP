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
  late final Translations$legacyResult$zh_CN legacyResult =
      Translations$legacyResult$zh_CN.internal(_root);
  @override
  late final Translations$shell$zh_CN shell = Translations$shell$zh_CN.internal(
    _root,
  );
  @override
  late final Translations$search$zh_CN search =
      Translations$search$zh_CN.internal(_root);
  @override
  late final Translations$history$zh_CN history =
      Translations$history$zh_CN.internal(_root);
  @override
  late final Translations$home$zh_CN home = Translations$home$zh_CN.internal(
    _root,
  );
  @override
  late final Translations$charts$zh_CN charts =
      Translations$charts$zh_CN.internal(_root);
  @override
  late final Translations$library$zh_CN library =
      Translations$library$zh_CN.internal(_root);
  @override
  late final Translations$playlist$zh_CN playlist =
      Translations$playlist$zh_CN.internal(_root);
  @override
  late final Translations$selection$zh_CN selection =
      Translations$selection$zh_CN.internal(_root);
  @override
  late final Translations$offline$zh_CN offline =
      Translations$offline$zh_CN.internal(_root);
  @override
  late final Translations$settings$zh_CN settings =
      Translations$settings$zh_CN.internal(_root);
  @override
  late final Translations$about$zh_CN about = Translations$about$zh_CN.internal(
    _root,
  );
  @override
  late final Translations$debug$zh_CN debug = Translations$debug$zh_CN.internal(
    _root,
  );
  @override
  late final Translations$backup$zh_CN backup =
      Translations$backup$zh_CN.internal(_root);
  @override
  late final Translations$player$zh_CN player =
      Translations$player$zh_CN.internal(_root);
  @override
  late final Translations$playerPage$zh_CN playerPage =
      Translations$playerPage$zh_CN.internal(_root);
  @override
  late final Translations$appearance$zh_CN appearance =
      Translations$appearance$zh_CN.internal(_root);
  @override
  late final Translations$playback$zh_CN playback =
      Translations$playback$zh_CN.internal(_root);
  @override
  late final Translations$network$zh_CN network =
      Translations$network$zh_CN.internal(_root);
  @override
  late final Translations$librarySettings$zh_CN librarySettings =
      Translations$librarySettings$zh_CN.internal(_root);
  @override
  late final Translations$importPreview$zh_CN importPreview =
      Translations$importPreview$zh_CN.internal(_root);
  @override
  late final Translations$radio$zh_CN radio = Translations$radio$zh_CN.internal(
    _root,
  );
  @override
  late final Translations$sources$zh_CN sources =
      Translations$sources$zh_CN.internal(_root);
  @override
  late final Translations$plugins$zh_CN plugins =
      Translations$plugins$zh_CN.internal(_root);
  @override
  late final Translations$onboarding$zh_CN onboarding =
      Translations$onboarding$zh_CN.internal(_root);
  @override
  late final Translations$accounts$zh_CN accounts =
      Translations$accounts$zh_CN.internal(_root);
  @override
  late final Translations$errors$zh_CN errors =
      Translations$errors$zh_CN.internal(_root);
  @override
  late final Translations$errorReport$zh_CN errorReport =
      Translations$errorReport$zh_CN.internal(_root);
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
  @override
  String get retry => '重试';
  @override
  String get exportDiagnostics => '导出诊断';
  @override
  String get exportDone => '已导出诊断文件';
  @override
  String get exportFailed => '无法导出诊断文件';
  @override
  late final Translations$startup$legacyImport$zh_CN legacyImport =
      Translations$startup$legacyImport$zh_CN.internal(_root);
}

// Path: legacyResult
class Translations$legacyResult$zh_CN extends Translations$legacyResult$zh_TW {
  Translations$legacyResult$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '已从旧版导入数据';
  @override
  String playlists({required Object count}) => '歌单：${count}';
  @override
  String tracks({required Object count}) => '曲目：${count}';
  @override
  String history({required Object count}) => '播放历史：${count}';
  @override
  String radio({required Object count}) => '电台：${count}';
  @override
  String accounts({required Object count}) => '账号：${count}';
  @override
  String relogin({required Object platforms}) => '需要重新登录：${platforms}';
  @override
  String get unimportedTitle => '没有导入的设置';
  @override
  late final Translations$legacyResult$unimported$zh_CN unimported =
      Translations$legacyResult$unimported$zh_CN.internal(_root);
  @override
  String localPlaylists({required Object count}) =>
      '${count} 张平台歌单的网址无法识别或重复，已转成本机歌单。';
  @override
  String get needsSources => '导入的数据用到尚未安装的音源，安装后才能播放与更新。';
  @override
  String get installSources => '安装音源';
  @override
  String get acknowledge => '知道了';
}

// Path: shell
class Translations$shell$zh_CN extends Translations$shell$zh_TW {
  Translations$shell$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get home => '首页';
  @override
  String get library => '音乐库';
  @override
  String get backTooltip => '返回（Esc）';
  @override
  String get search => '搜索';
  @override
  String get settings => '设置';
  @override
  String get searchTooltip => '搜索（Ctrl+F）';
  @override
  String get settingsTooltip => '设置（Ctrl+,）';
  @override
  String get radio => '电台';
  @override
  String get queue => '队列';
  @override
  String get railCollapseTooltip => '收起侧边栏';
  @override
  String get railExpandTooltip => '展开侧边栏';
  @override
  String get queueTooltip => '队列（Ctrl+Q）';
  @override
  String get queueEmptyTitle => '队列是空的';
  @override
  String get queueEmptyBody => '在搜索或音乐库里播放歌曲，会排进这里。';
  @override
  String get queueEmptyAction => '去搜索';
  @override
  String get panelTitle => '正在播放';
  @override
  String get panelNextUp => '下一首';
  @override
  String get panelAddToPlaylistTooltip => '加入歌单';
  @override
  String get panelCollapseTooltip => '收起正在播放面板';
  @override
  String get panelShowTooltip => '显示正在播放面板';
  @override
  String get panelHideTooltip => '隐藏正在播放面板';
  @override
  String get panelMenuItem => '正在播放面板';
  @override
  String get panelResizeTooltip => '拖动或按 ←／→ 调整宽度';
  @override
  String get minimizeTooltip => '最小化';
  @override
  String get maximizeTooltip => '最大化';
  @override
  String get restoreTooltip => '还原';
  @override
  String get closeWindowTooltip => '关闭';
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
  String get roomHint => '搜索直播间';
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
  @override
  String get loadedAll => '已加载全部';
  @override
  String get allSources => '全部音源';
  @override
  String get groupEmpty => '这个音源没有结果';
  @override
  String get more => '更多选项';
  @override
  String get play => '播放';
  @override
  String get playNext => '下一首播放';
  @override
  String get addToQueue => '添加到队列';
  @override
  String get playNextInMix => '下一首播放（Mix 中无法使用）';
  @override
  String get addToQueueInMix => '加入队列（Mix 中无法使用）';
  @override
  String get startMix => '开始 Mix';
  @override
  String get addedToNext => '已添加为下一首播放';
  @override
  String get addedToQueue => '已添加到队列';
  @override
  String get modeTracks => '曲目';
  @override
  String get modeRooms => '直播间';
  @override
  String get filterAll => '全部';
  @override
  String get filterLive => '开播中';
  @override
  String get filterOffline => '未开播';
  @override
  String get listen => '收听';
  @override
  String get notLive => '尚未开播';
  @override
  String get addToRadio => '添加到电台';
  @override
  String get showParts => '展开分P';
  @override
  String get hideParts => '收起分P';
  @override
  String get loadingParts => '正在载入分P';
  @override
  String get partsFailed => '无法载入分P';
  @override
  String get historyTitle => '搜索历史';
  @override
  String get historyClear => '清除';
  @override
  String get historyDelete => '删除这条搜索历史';
}

// Path: history
class Translations$history$zh_CN extends Translations$history$zh_TW {
  Translations$history$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '播放历史';
  @override
  String get empty => '还没有播放记录';
  @override
  String get emptyHint => '听过的歌会按日期出现在这里';
  @override
  String get today => '今天';
  @override
  String get yesterday => '昨天';
  @override
  String subtitle({required Object artist, required Object time}) =>
      '${artist} · ${time}';
  @override
  String get more => '更多选项';
  @override
  String get play => '播放';
  @override
  String get playNext => '下一首播放';
  @override
  String get addToQueue => '加入队列';
  @override
  String get playNextInMix => '下一首播放（Mix 中无法使用）';
  @override
  String get addToQueueInMix => '加入队列（Mix 中无法使用）';
  @override
  String get startMix => '开始 Mix';
  @override
  String get addedToNext => '已加入下一首播放';
  @override
  String get addedToQueue => '已加入队列';
  @override
  String get remove => '从历史移除';
  @override
  String get clearAll => '清除全部历史';
  @override
  String get clearTitle => '清除全部播放历史？';
  @override
  String get clearBody => '所有播放记录都会被删除，无法恢复。队列与设置不受影响。';
  @override
  String get cancel => '取消';
  @override
  String get confirm => '清除';
  @override
  String get cleared => '已清除播放历史';
  @override
  String get selectDate => '选择日期';
  @override
  String get search => '搜索历史';
  @override
  String get searchHint => '搜索曲名或作者';
  @override
  String get closeSearch => '关闭搜索';
  @override
  String get statsToday => '今天';
  @override
  String get statsWeek => '本周';
  @override
  String get statsAll => '全部';
  @override
  String statsCount({required num count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        count,
        other: '${count} 首',
      );
  @override
  String durationHm({required Object hours, required Object minutes}) =>
      '${hours} 小时 ${minutes} 分';
  @override
  String durationM({required Object minutes}) => '${minutes} 分';
  @override
  String get filterAll => '全部';
  @override
  String get sortTooltip => '排序';
  @override
  String get sortNewest => '新到旧';
  @override
  String get sortOldest => '旧到新';
  @override
  String get sortMostPlayed => '播放次数';
  @override
  String get clearDate => '清除日期筛选';
  @override
  String dayCount({required num count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        count,
        other: '${count} 首',
      );
  @override
  String dayCollapse({required Object day}) => '收起 ${day}';
  @override
  String dayExpand({required Object day}) => '展开 ${day}';
  @override
  String playCount({required num count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        count,
        other: '${count} 次',
      );
  @override
  String sourceIcon({required Object name}) => '音源：${name}';
  @override
  String get removeAllOfTrack => '删除此曲所有记录';
  @override
  String get removeAllTitle => '删除这首歌的所有记录？';
  @override
  String removeAllBody({required Object title}) =>
      '“${title}”的所有播放记录都会被删除，无法恢复。';
  @override
  String get deleteSelected => '删除';
  @override
  String deleteSelectedTitle({required num count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        count,
        other: '删除 ${count} 条记录？',
      );
  @override
  String get deleteSelectedBody => '选中的播放记录会被删除，无法恢复。';
  @override
  String deleteSelectedTracksTitle({required num count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        count,
        other: '删除 ${count} 首歌的所有记录？',
      );
  @override
  String get deleteSelectedTracksBody => '这几首歌的所有播放记录都会被删除，无法恢复。';
  @override
  String get delete => '删除';
  @override
  String deletedCount({required num count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        count,
        other: '已删除 ${count} 条',
      );
  @override
  String get retry => '重试';
  @override
  String get goSearch => '去搜索';
  @override
  String get noMatch => '没有符合的记录';
  @override
  String get noMatchHint => '换个筛选条件或关键字试试';
  @override
  String get pageMore => '更多操作';
}

// Path: home
class Translations$home$zh_CN extends Translations$home$zh_TW {
  Translations$home$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '首页';
  @override
  String get recentlyPlayed => '最近播放';
  @override
  String get myPlaylists => '我的歌单';
  @override
  String get radio => '电台';
  @override
  String get viewAll => '查看全部';
  @override
  String get empty => '这里还没有内容';
  @override
  String get emptyHint => '搜索并播放歌曲，或导入歌单';
  @override
  String get more => '更多选项';
  @override
  String get play => '播放';
  @override
  String get playNext => '下一首播放';
  @override
  String get addToQueue => '加入队列';
  @override
  String get playNextInMix => '下一首播放（Mix 中无法使用）';
  @override
  String get addToQueueInMix => '加入队列（Mix 中无法使用）';
  @override
  String get startMix => '开始 Mix';
  @override
  String get addedToNext => '已加入下一首播放';
  @override
  String get addedToQueue => '已加入队列';
  @override
  String get createPlaylist => '创建歌单';
  @override
  String get scrollLeft => '向左滚动';
  @override
  String get scrollRight => '向右滚动';
}

// Path: charts
class Translations$charts$zh_CN extends Translations$charts$zh_TW {
  Translations$charts$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '排行';
  @override
  String get explore => '探索';
  @override
  String updatedAt({required Object time}) => '更新于 ${time}';
  @override
  String get updateFailed => '更新失败';
  @override
  String get loading => '正在加载排行';
  @override
  String get empty => '这个榜单没有内容';
  @override
  String get failed => '排行更新失败';
  @override
  String get failedHint => '之后会自动重试，也可以在探索页刷新。';
  @override
  String get exploreFailedHint => '点右上角的“刷新”再试一次。';
  @override
  String get off => '自动更新已关闭';
  @override
  String get offHint => '在探索页点“刷新”加载，或在“设置”的“网络”设置排行刷新间隔。';
  @override
  String get exploreOffHint => '点右上角的“刷新”加载。';
  @override
  String get refresh => '刷新';
  @override
  String get refreshed => '已更新排行';
  @override
  String get refreshOffline => '离线中，没有刷新：显示的是上次的排行';
  @override
  String refreshFailed({required Object reason}) => '无法刷新排行：${reason}';
  @override
  String tab({required Object title, required Object source}) =>
      '${title} · ${source}';
  @override
  String source({required Object source, required Object status}) =>
      '${source} · ${status}';
  @override
  String get noCharts => '没有启用的排行';
  @override
  String get noChartsHint => '在“设置”的“音乐库”选择首页要显示的排行。';
  @override
  String get noSource => '没有插件提供排行';
  @override
  String get noSourceHint => '安装并启用提供排行的插件后，它的榜单会出现在这里。';
}

// Path: library
class Translations$library$zh_CN extends Translations$library$zh_TW {
  Translations$library$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '音乐库';
  @override
  String get history => '历史';
  @override
  String get playlists => '歌单';
  @override
  String get newPlaylist => '新建歌单';
  @override
  String get empty => '还没有歌单';
  @override
  String get emptyHint => '点「新建歌单」创建一个歌单，或点「导入」带进一个。';
  @override
  String trackCount({required num count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        count,
        other: '${count} 首',
      );
  @override
  String get local => '本地';
  @override
  String get more => '更多选项';
  @override
  String get addToQueue => '全部添加到队列';
  @override
  String get shuffleToQueue => '随机添加到队列';
  @override
  String get addToQueueInMix => '全部添加到队列（Mix 中无法使用）';
  @override
  String get shuffleToQueueInMix => '随机添加到队列（Mix 中无法使用）';
  @override
  String addedToQueue({required Object name}) => '已将「${name}」添加到队列';
  @override
  String addFailed({required Object reason}) => '无法添加到队列：${reason}';
  @override
  String get edit => '编辑';
  @override
  String get delete => '删除';
  @override
  String get deleteTitle => '删除歌单？';
  @override
  String deleteBody({required Object name}) =>
      '「${name}」将被删除，无法恢复。歌曲本身和播放历史不受影响。';
  @override
  String get deleted => '已删除歌单';
  @override
  String deleteFailed({required Object reason}) => '无法删除歌单：${reason}';
  @override
  String get createTitle => '新建歌单';
  @override
  String get editTitle => '编辑歌单';
  @override
  String get name => '名称';
  @override
  String get nameRequired => '请输入名称';
  @override
  String get description => '描述（选填）';
  @override
  String get cover => '封面';
  @override
  String get coverDefault => '第一首歌的封面';
  @override
  String get create => '创建';
  @override
  String get save => '保存';
  @override
  String get cancel => '取消';
  @override
  String get created => '已创建歌单';
  @override
  String get saved => '已保存歌单';
  @override
  String createFailed({required Object reason}) => '无法创建歌单：${reason}';
  @override
  String saveFailed({required Object reason}) => '无法保存歌单：${reason}';
  @override
  String get reorder => '拖动以排序';
  @override
  String reorderFailed({required Object reason}) => '无法调整歌单顺序：${reason}';
  @override
  String get coverCustom => '自定义图片';
  @override
  String get coverChooseCustom => '自定义';
  @override
  String get coverUseDefault => '使用默认';
  @override
  String get coverUrl => '图片网址';
  @override
  String get coverInvalidUrl => '请输入以 https 开头的网址';
  @override
  String get coverNotFromSource => '这个网址不属于任何已安装的音源';
  @override
  String get imported => '导入';
  @override
  String get mix => 'Mix';
  @override
  String get mixPlay => 'Mix 播放';
  @override
  String mixPlayDisabled({required Object reason}) => 'Mix 播放（${reason}）';
  @override
  String get mixSeed => '种子曲目';
  @override
  String get mixUnsupported => '这个音源不支持 Mix';
  @override
  String get addToPlaylist => '添加到歌单…';
  @override
  String get addToPlaylistTitle => '添加到歌单';
  @override
  String get noLocalPlaylists => '还没有本地歌单';
  @override
  String get add => '添加';
  @override
  String addedToPlaylist({required Object name}) => '已添加到「${name}」';
  @override
  String addedToPlaylists({required num count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        count,
        other: '已添加到 ${count} 个歌单',
      );
  @override
  String addToPlaylistFailed({required Object reason}) => '无法添加到歌单：${reason}';
  @override
  String get importTooltip => '导入歌单';
  @override
  String get importTitle => '导入歌单';
  @override
  String get importUrlLabel => '网址';
  @override
  String get importAction => '导入';
  @override
  String get importLooking => '正在识别网址…';
  @override
  String importProgress({required Object count}) => '已读 ${count} 首';
  @override
  String importProgressOf({required Object count, required Object total}) =>
      '已导入 ${count}／${total} 首';
  @override
  String get importCancelledNone => '已取消导入';
  @override
  String refreshProgress({required Object count}) => '已更新 ${count} 首';
  @override
  String refreshProgressOf({required Object count, required Object total}) =>
      '已更新 ${count}／${total} 首';
  @override
  String get importUnrecognized => '已安装的音源都不认识这个网址';
  @override
  String importFailed({required Object reason}) => '无法导入：${reason}';
  @override
  String get importDone => '已导入歌单';
  @override
  String get importPartial => '已导入，但只读到歌单的一部分。刷新可以读完其余的。';
  @override
  String get refresh => '刷新';
  @override
  String get refreshing => '刷新中…';
  @override
  String get refreshed => '已刷新歌单';
  @override
  String get refreshedPartly => '只读到歌单的一部分，没有移除任何歌曲';
  @override
  String refreshFailed({required Object reason}) => '无法刷新歌单：${reason}';
  @override
  String get refreshOffline => '离线中，无法刷新歌单';
  @override
  String get refreshNoSource => '这个音源不能刷新歌单';
  @override
  String statusRefreshed({required Object time}) => '上次刷新：${time}';
  @override
  String statusPartial({required Object time}) => '上次刷新：部分完成 · ${time}';
  @override
  String get statusNever => '还没刷新过';
  @override
  String get statusFailed => '刷新失败';
  @override
  String get statusGone => '来源失效：远程歌单已删除或无权限';
  @override
  String get statusAuth => '需要登录才能刷新';
  @override
  String get retry => '重试';
  @override
  String get useRemote => '使用远程的';
  @override
  String get useRemoteHint => '下一次刷新会写回远程的值';
  @override
  String get refreshInterval => '自动刷新';
  @override
  String get refreshIntervalOff => '不启用';
  @override
  String get refreshEveryHour => '每小时';
  @override
  String refreshEveryHours({required Object count}) => '每 ${count} 小时';
  @override
  String get refreshEveryDay => '每天';
  @override
  String refreshEveryDays({required Object count}) => '每 ${count} 天';
  @override
  String get addToRemote => '加入远端歌单…';
  @override
  String get addToRemoteMixed => '加入远端歌单（请只选同一个音源的曲目）';
  @override
  String get removeFromRemote => '从远端歌单移除';
  @override
  String get remoteTitle => '加入远端歌单';
  @override
  String get remoteLoading => '正在读取你的歌单';
  @override
  String get remoteLoadFailed => '读不到你的歌单';
  @override
  String get remoteEmpty => '还没有可以加入的歌单';
  @override
  String get remoteNew => '在远端新增歌单';
  @override
  String get remoteNewTitle => '新增远端歌单';
  @override
  String get remoteNewName => '名称';
  @override
  String get remoteNewAction => '新增';
  @override
  String remoteNewFailed({required Object reason}) => '无法新增歌单：${reason}';
  @override
  String remoteAdded({required Object count}) => '已加入 ${count} 个歌单';
  @override
  String get remoteAddedOne => '已加入 1 个歌单';
  @override
  String remoteAlreadyThere({required Object count}) => '，${count} 首已存在';
  @override
  String remoteFailedCount({required Object count}) => '，${count} 项失败';
  @override
  String get remoteAddNone => '没有加入任何歌单';
  @override
  String remoteAddError({required Object reason}) => '无法加入远端歌单：${reason}';
  @override
  String get remoteDetailsTitle => '失败的项目';
  @override
  String remoteDetailCount({required Object name, required Object count}) =>
      '${name}：${count} 项失败';
  @override
  String get remoteNoReason => '没有说明原因';
  @override
  String get remoteClose => '关闭';
  @override
  String get removeRemoteTitle => '从远端歌单移除？';
  @override
  String removeRemoteBody({
    required Object name,
    required Object count,
    required Object source,
  }) => '将从「${name}」移除 ${count} 首，${source} 上的歌单也会一并更新。无法恢复。';
  @override
  String get removeRemoteConfirm => '移除';
  @override
  String removedFromRemote({required Object count}) => '已从远端歌单移除 ${count} 首';
  @override
  String get removeRemoteNone => '没有移除任何曲目';
  @override
  String removeRemoteFailed({required Object reason}) => '无法从远端歌单移除：${reason}';
  @override
  String get importAsPlatform => '导入为平台歌单';
  @override
  String importAsPlatformHint({required Object source}) =>
      '跟着 ${source} 上的歌单刷新';
  @override
  String get importAsMatch => '匹配到其他音源';
  @override
  String get importAsMatchHint => '在其他音源找同一首歌，建成不会刷新的本地歌单';
  @override
  String get loadingPlaylists => '正在加载歌单';
  @override
  String heroOwner({required Object name}) => '拥有者：${name}';
  @override
  String heroImported({required Object source}) => '已导入 · ${source}';
  @override
  String durationHoursMinutes({
    required Object hours,
    required Object minutes,
  }) => '${hours} 小时 ${minutes} 分';
  @override
  String durationMinutes({required Object minutes}) => '${minutes} 分';
  @override
  String get durationUnderMinute => '不到 1 分';
  @override
  String get coverFromTracks => '从歌曲封面选';
  @override
  String get coverFromTracksTitle => '选择封面';
  @override
  String get coverFromTracksLoading => '正在读取歌单的封面';
  @override
  String get coverFromTracksEmpty => '歌单里的歌曲都没有封面';
  @override
  String get coverFromTracksFailed => '无法读取歌单的封面';
  @override
  String coverFromTracksItem({required Object index}) => '第 ${index} 张封面';
  @override
  String addToPlaylistTracks({required num count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        count,
        other: '${count} 首歌曲',
      );
}

// Path: playlist
class Translations$playlist$zh_CN extends Translations$playlist$zh_TW {
  Translations$playlist$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get more => '更多选项';
  @override
  String get play => '播放';
  @override
  String get playNext => '下一首播放';
  @override
  String get addToQueue => '加入队列';
  @override
  String get playNextInMix => '下一首播放（Mix 中无法使用）';
  @override
  String get addToQueueInMix => '加入队列（Mix 中无法使用）';
  @override
  String get startMix => '开始 Mix';
  @override
  String get addedToNext => '已加入下一首播放';
  @override
  String get addedToQueue => '已加入队列';
  @override
  String get remove => '从歌单移除';
  @override
  String removeFailed({required Object reason}) => '无法从歌单移除：${reason}';
  @override
  String get reorder => '拖动以排序';
  @override
  String reorderFailed({required Object reason}) => '无法调整曲目顺序：${reason}';
  @override
  String get empty => '这个歌单还没有歌';
  @override
  String get emptyHint => '在歌曲的菜单中选择「添加到歌单…」';
  @override
  String get notFound => '找不到这个歌单';
  @override
  String get unavailable => '已失效';
  @override
  String get removeTitle => '从歌单移除选中的歌？';
  @override
  String removeBody({required Object count, required Object name}) =>
      '选中的 ${count} 首将从「${name}」移除，无法恢复。';
  @override
  String get removeConfirm => '移除';
  @override
  String get cancel => '取消';
  @override
  String get removed => '已从歌单移除';
  @override
  String get loading => '正在加载歌单';
  @override
  String get retry => '重试';
}

// Path: selection
class Translations$selection$zh_CN extends Translations$selection$zh_TW {
  Translations$selection$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get select => '选择';
  @override
  String count({required Object count}) => '已选 ${count} 首';
  @override
  String get cancelTooltip => '取消选择（Esc）';
  @override
  String get selectAllTooltip => '全选（Ctrl+A）';
  @override
  String get playNext => '下一首播放';
  @override
  String get playNextInMix => '下一首播放（Mix 中无法使用）';
  @override
  String get addedToNext => '已加入下一首播放';
  @override
  String get deselectAllTooltip => '取消全选';
  @override
  String get addToQueue => '加入队列';
  @override
  String get addToQueueInMix => '加入队列（Mix 中无法使用）';
  @override
  String get addToPlaylist => '添加到歌单…';
  @override
  String get addedToQueue => '已加入队列';
  @override
  String get addToRemote => '加入远端歌单…';
  @override
  String get addToRemoteMixed => '加入远端歌单（请只选同一个音源的曲目）';
  @override
  String get removeFromRemote => '从远端歌单移除';
  @override
  String get more => '更多操作';
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
  String get accounts => '账号';
  @override
  String get appearance => '外观';
  @override
  String get network => '网络';
  @override
  String get back => '返回';
  @override
  String get playback => '播放';
  @override
  String get library => '音乐库';
  @override
  String get plugins => '插件';
  @override
  String get backup => '备份与还原';
  @override
  String get about => '关于';
  @override
  String get debug => 'Debug';
  @override
  late final Translations$settings$summary$zh_CN summary =
      Translations$settings$summary$zh_CN.internal(_root);
}

// Path: about
class Translations$about$zh_CN extends Translations$about$zh_TW {
  Translations$about$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get version => '版本';
  @override
  String versionValue({required Object version, required Object flavor}) =>
      '${version}（${flavor}）';
  @override
  String tapsLeft({required Object count}) => '再点 ${count} 次即可开启开发者模式';
  @override
  String get developerModeOn => '已开启开发者模式';
  @override
  String get alreadyDeveloper => '开发者模式已经开启';
}

// Path: debug
class Translations$debug$zh_CN extends Translations$debug$zh_TW {
  Translations$debug$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Debug';
  @override
  String get overview => '概览';
  @override
  String get developerMode => '开发者模式';
  @override
  String get developerModeHint => '关闭后设置页不再显示 Debug，日志级别回到默认';
  @override
  String get logLevel => '日志级别';
  @override
  String get logLevelInfo => 'info';
  @override
  String get logLevelDebug => 'debug';
  @override
  String get logLevelDebugHint => '记录更多细节，日志文件也会变大';
  @override
  String logLevelDefault({required Object level}) => '${level}（默认）';
  @override
  String get app => '应用';
  @override
  String get version => '版本';
  @override
  String get flavor => 'Flavor';
  @override
  String get platform => '平台';
  @override
  String get dataDirectory => '数据目录';
  @override
  String get cacheUsage => '缓存用量';
  @override
  String cacheUsageValue({required Object size}) => '${size}，在「设置 → 网络」中管理';
  @override
  String get diagnostics => '诊断包';
  @override
  String get diagnosticsHint => '这个 App 的版本、插件与设置摘要，加上 log 文件；不含账号名称。';
  @override
  String get diagnosticsCopy => '复制摘要';
  @override
  String get diagnosticsSave => '存成文件';
  @override
  String get diagnosticsShare => '分享';
  @override
  String get diagnosticsCopied => '已复制摘要';
  @override
  String get exportSaved => '已保存';
  @override
  String exportFailed({required Object message}) => '无法生成文件：${message}';
  @override
  String get exportReminderBody =>
      '文件里有这个 App 的版本、插件、设置与最近的 log 记录。Cookie、token 与签名网址已遮蔽，账号名称不在里面，发给任何人之前仍请再检查一次内容。';
  @override
  String get logExport => '导出 log 文件';
  @override
  String get logExportSave => '存成文件';
  @override
  String get logExportShare => '分享';
  @override
  String get log => '日志与错误历史';
  @override
  String get network => '网络';
  @override
  String get cancel => '取消';
  @override
  String get logSearchHint => '搜索日志';
  @override
  String get filterLevelAll => '所有级别';
  @override
  String filterLevelFrom({required Object level}) => '${level} 及以上';
  @override
  String get filterTagAll => '所有 tag';
  @override
  String get errorsOnly => '只看错误';
  @override
  String get includeEarlier => '包含之前的记录';
  @override
  String get earlierLoading => '正在读取日志文件';
  @override
  String get earlierFailed => '无法读取日志文件';
  @override
  String logCount({required Object shown, required Object total}) =>
      '${shown} / ${total} 条';
  @override
  String get logEmpty => '没有记录';
  @override
  String get logNoMatch => '没有符合筛选的记录';
  @override
  String get logCopy => '复制已筛选';
  @override
  String logCopied({required Object count}) => '已复制 ${count} 条';
  @override
  String get logCopyNothing => '没有可复制的内容';
  @override
  String get logClear => '清除日志';
  @override
  String get logClearTitle => '清除日志？';
  @override
  String get logClearBody => '这会删除本次运行的记录和本机上的日志文件，无法恢复。';
  @override
  String get logCleared => '已清除日志';
  @override
  String get logClearFailed => '无法删除日志文件';
  @override
  String get netSearchHint => '搜索请求';
  @override
  String get netSourceAll => '所有音源';
  @override
  String get netSourceApp => '应用（非插件）';
  @override
  String get netStatusAll => '所有状态';
  @override
  String get netStatusFailed => '失败';
  @override
  String get netEmpty => '没有网络记录';
  @override
  String get netEmptyHint => '本次运行发出的请求会列在这里。';
  @override
  String get netNoMatch => '没有符合筛选的请求';
  @override
  String netCount({required Object shown, required Object total}) =>
      '${shown} / ${total} 条';
  @override
  String get netUnknown => '—';
  @override
  String get netDetailUrl => '网址';
  @override
  String get netDetailQuery => 'Query';
  @override
  String get netDetailNoQuery => '无';
  @override
  String get netDetailStatus => '状态';
  @override
  String get netDetailDuration => '耗时';
  @override
  String get netDetailSize => '大小';
  @override
  String get netDetailSource => '音源';
  @override
  String get netDetailClient => 'Client';
  @override
  String get netDetailCredentials => '已携带凭证';
  @override
  String get netDetailRetry => '重试次数';
  @override
  String get netDetailError => '错误类型';
  @override
  String get netDetailNoError => '无';
  @override
  String get netDetailRelated => '对应的错误记录';
  @override
  String get netDetailNoRelated => '无';
  @override
  String get netDetailTime => '时间';
  @override
  String get yes => '是';
  @override
  String get no => '否';
  @override
  String netDuration({required Object ms}) => '${ms} ms';
  @override
  String get close => '关闭';
  @override
  String get logDetail => '详细';
  @override
  String get playback => '播放状态';
  @override
  String get database => '数据库';
  @override
  String get health => '音源健康检查';
  @override
  String get hcHint => '对已安装且启用的插件用真实连接跑检查用例（需要登录的用例使用已存的凭证）。一次只检查一个插件。';
  @override
  String get hcAll => '全部检查';
  @override
  String get hcCheck => '检查';
  @override
  String get hcChecking => '检查中…';
  @override
  String get hcNone => '没有检查用例';
  @override
  String get hcDisabled => '已停用';
  @override
  String hcCount({required Object count}) => '${count} 个用例';
  @override
  String get hcUnreadable => '检查用例无法读取';
  @override
  String get hcPassed => '通过';
  @override
  String get hcFailed => '失败';
  @override
  String get hcSkipped => '跳过（未登录）';
  @override
  String get hcSkippedMutates => '跳过（会改动远端）';
  @override
  String hcProblem({required Object problem}) => '无法检查：${problem}';
  @override
  String get hcNotLoaded => '无法检查：插件没有加载（见 log）';
  @override
  String get hcEmpty => '还没有安装的插件';
  @override
  String hcCase({
    required Object capability,
    required Object outcome,
    required Object ms,
  }) => '${capability} · ${outcome} · ${ms} ms';
  @override
  String hcErrorType({required Object type}) => '错误类别：${type}';
  @override
  String get pluginDev => '插件开发';
  @override
  String get pdHint =>
      '文件夹里的每个插件目录（一个 .js、checks.json、fixtures/）载入为“开发中”，取代同 id 的已安装版；改了文件按“重新载入”。模式只决定“执行”用例的方式，每个用例在独立的环境（空的存储与凭证）里跑；App 其他地方用到的开发中插件一律真实联网。';
  @override
  String get pdFolder => '文件夹';
  @override
  String get pdNoFolder => '还没选文件夹';
  @override
  String get pdPick => '选择文件夹';
  @override
  String get pdRescan => '重新扫描';
  @override
  String get pdUnload => '卸载';
  @override
  String get pdApplying => '载入中…';
  @override
  String get pdFolderMissing => '文件夹不存在';
  @override
  String get pdFolderEmpty => '文件夹里没有插件目录（含一个 .js 文件的文件夹）';
  @override
  String pdDuplicateId({
    required Object first,
    required Object second,
    required Object id,
  }) => '${first} 和 ${second} 的插件 id 都是“${id}”，只载入 ${first}';
  @override
  String pdTagReplaces({required Object version}) => '取代已安装 ${version}';
  @override
  String get pdTagFailed => '载入失败';
  @override
  String pdIdChanged({required Object id}) => '插件 id 改成了“${id}”，请重新扫描文件夹';
  @override
  String get pdReplay => '重放';
  @override
  String get pdRecord => '录制';
  @override
  String get pdReal => '真实';
  @override
  String get pdReload => '重新载入';
  @override
  String get pdViewLog => '查看 log';
  @override
  String get pdRunAll => '全部执行';
  @override
  String get pdRun => '执行';
  @override
  String get pdRunning => '执行中';
  @override
  String get pdRecordWarning =>
      '录制以真实联网执行；结果符合 checks.json 才会覆盖 fixtures/ 里该能力的文件（手改过的跳过）。误录请在插件文件夹用 git checkout 还原。';
  @override
  String get pdNoCases => '没有检查用例';
  @override
  String pdCaseLine({
    required Object outcome,
    required Object ms,
    required Object mode,
  }) => '${outcome} · ${ms} ms · ${mode}';
  @override
  String get pdPassed => '通过';
  @override
  String get pdFailed => '失败';
  @override
  String get pdSkippedLogin => '跳过：需要登录，目前没有登录';
  @override
  String get pdSkippedEdited => '跳过：fixture 是手改过的';
  @override
  String get pdSkippedMutates => '跳过：会改动远端';
  @override
  String get pdNotRun => '还没执行';
  @override
  String pdErrorType({required Object type}) => '错误类别：${type}';
  @override
  String pdWritten({required Object count}) => '已写入 ${count} 个 fixture';
  @override
  String get pdNotWritten => '没有写入 fixture';
  @override
  String get pdValue => '返回值';
  @override
  String get pdTruncated => '（太长，已截断）';
  @override
  String get pdCopy => '复制';
  @override
  String pdReloaded({required Object name, required Object version}) =>
      '已重新载入 ${name} ${version}';
  @override
  String pdReloadFailed({required Object name}) => '重新载入失败：${name}';
  @override
  String get pbEmpty => '没有在播放';
  @override
  String get pbEmptyHint => '播放或加入队列后，这里会显示后端、流与队列的状态。';
  @override
  String get pbCopy => '复制快照';
  @override
  String get pbCopied => '已复制快照';
  @override
  String get pbState => '状态';
  @override
  String get pbStateIdle => '空闲';
  @override
  String get pbStateLoading => '加载中';
  @override
  String get pbStatePlaying => '播放中';
  @override
  String get pbStatePaused => '已暂停';
  @override
  String get pbStateBuffering => '缓冲中';
  @override
  String get pbStateRetrying => '等待重试';
  @override
  String get pbStateWaitingNetwork => '等网络';
  @override
  String get pbStateFailed => '已停止';
  @override
  String get pbError => '错误类型';
  @override
  String get pbRetryAttempt => '重试次数';
  @override
  String get pbNextRetry => '下次重试';
  @override
  String get pbTrack => '曲目';
  @override
  String get pbPlugin => '插件';
  @override
  String get pbBackend => '后端';
  @override
  String get pbOutputDevice => '输出设备';
  @override
  String get pbOutputDefault => '系统默认或不适用';
  @override
  String get pbStream => '流';
  @override
  String get pbSourceNetwork => '网络';
  @override
  String get pbSourceAsset => '内置 asset';
  @override
  String pbCandidate({required Object index, required Object count}) =>
      '候选 ${index} / ${count}';
  @override
  String get pbUnknown => '—';
  @override
  String get pbPosition => '位置';
  @override
  String get pbQueue => '队列';
  @override
  String get pbQueueEmpty => '队列是空的';
  @override
  String pbQueueSummary({required Object total, required Object index}) =>
      '共 ${total} 首，当前第 ${index} 首';
  @override
  String get pbBefore => '前面';
  @override
  String get pbAfter => '后面';
  @override
  String get pbNone => '无';
  @override
  String get pbShuffle => '随机';
  @override
  String get pbLoop => '循环';
  @override
  String get pbLoopOff => '关闭';
  @override
  String get pbLoopAll => '全部';
  @override
  String get pbLoopOne => '单曲';
  @override
  String get pbTemporary => '临时播放中（当前位置是回到队列时的那一首）';
  @override
  String get pbLive => '直播中（停止后回到队列）';
  @override
  String get pbLiveRoom => '直播间';
  @override
  String get pbMix => 'Mix';
  @override
  String get dbTables => '数据表';
  @override
  String dbRowCount({required Object count}) => '${count} 条';
  @override
  String get dbBack => '回到数据表列表';
  @override
  String dbPage({
    required Object page,
    required Object pages,
    required Object total,
  }) => '第 ${page} / ${pages} 页，共 ${total} 条';
  @override
  String get dbPrevious => '上一页';
  @override
  String get dbNext => '下一页';
  @override
  String get dbNoRows => '这张表没有数据';
  @override
  String get dbNull => 'NULL';
  @override
  String get dbLoadFailed => '无法读取数据库';
  @override
  String get dbCheck => '检查';
  @override
  String get dbChecking => '检查中…';
  @override
  String get dbCheckClean => '没有发现问题';
  @override
  String get dbCheckProblems => '发现问题';
  @override
  String get dbIntegrity => '完整性（integrity_check）';
  @override
  String get dbForeignKeys => '外键（foreign_key_check）';
  @override
  String get dbOk => '正常';
  @override
  String dbViolation({
    required Object table,
    required Object rowId,
    required Object parent,
  }) => '${table} 的 rowid ${rowId} 找不到父表 ${parent} 的行';
  @override
  String get dbOrphans => '孤儿曲目';
  @override
  String dbOrphansValue({required Object count}) => '${count} 首（启动时会自动清掉，不算损坏）';
  @override
  String get dbCheckFailed => '检查失败';
  @override
  String get reset => '重置数据';
  @override
  String get resetBody =>
      '清空数据库（含设置、歌单、队列与播放历史）、所有音源的登录凭证、登录网页的数据与缓存，然后重启 App。不会动 log 文件、备份与已下载的文件。';
  @override
  String get resetBackupNote =>
      '清空之前会先把数据库备份到数据目录的 backups 文件夹；备份失败就什么都不清。凭证不在备份里，还原后要重新登录。';
  @override
  String get resetButton => '重置数据…';
  @override
  String resetBackupFailed({required Object message}) =>
      '无法备份数据库，没有清除任何数据：${message}';
  @override
  String get resetConfirmTitle => '重置所有数据？';
  @override
  String resetConfirmBody({required Object path}) =>
      '数据库已备份到 ${path}。按下“清空并重启”会清空数据库、凭证、登录网页的数据与缓存，除了这份备份之外无法恢复。';
  @override
  String get resetRestartsItself => '完成后 App 会自动重新启动。';
  @override
  String get resetRestartsManually => '完成后 App 会关闭，请自己重新打开。';
  @override
  String get resetUnderstand => '我了解这会清空所有数据';
  @override
  String get resetConfirm => '清空并重启';
  @override
  String get resetWorking => '正在清空…';
  @override
  String resetFailed({required Object message}) => '重置没有完成：${message}';
  @override
  String get dbBackUp => '立即备份';
  @override
  String dbBackedUp({required Object path}) => '已备份到 ${path}';
  @override
  String dbBackUpFailed({required Object message}) => '无法备份数据库：${message}';
  @override
  String get dbRestore => '从备份还原';
  @override
  String get dbRestoreTitle => '选择要还原的备份';
  @override
  String get dbRestoreEmpty => '没有备份。先按“立即备份”，或重置数据时会自动创建。';
  @override
  String dbRestoreListFailed({required Object message}) =>
      '无法读取备份列表：${message}';
  @override
  String get dbRestoreWorking => '正在还原…';
  @override
  String dbRestoreFailed({required Object message}) => '还原没有完成：${message}';
  @override
  String get dbCheckProblemsActions => '可以从备份还原，或重置数据。';
}

// Path: backup
class Translations$backup$zh_CN extends Translations$backup$zh_TW {
  Translations$backup$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get intro =>
      '备份包含歌单、设置、已安装的插件等数据，不含登录、Cookie、缓存与下载的文件。还原会替换当前的数据，并保留这台设备当前的登录。';
  @override
  String get export => '导出备份';
  @override
  String get restore => '从备份文件还原';
  @override
  String get exportWorking => '正在导出…';
  @override
  String get stageWorking => '正在检查备份…';
  @override
  String get restoreWorking => '正在还原…';
  @override
  String exported({required Object location}) => '备份已保存到 ${location}';
  @override
  String exportFailed({required Object message}) => '备份没有导出：${message}';
  @override
  String restoreFailed({required Object message}) => '还原没有完成：${message}';
  @override
  String get rejectedNewer => '这份备份来自较新版的 FMP，请先更新 FMP。';
  @override
  String get rejectedNotFmp => '这不是 FMP 的备份。';
  @override
  String get rejectedCorrupt => '备份文件已损坏。';
  @override
  String get restoreTitle => '从这份备份还原？';
  @override
  String get restoreBody => '当前的数据会被替换；替换前会自动备份。这台设备的登录会保留。';
  @override
  String get restartsItself => '完成后 App 会自动重新启动。';
  @override
  String get restartsManually => '完成后 App 会关闭，请自己再打开。';
  @override
  String get pluginsHeading => '备份里的插件';
  @override
  String get noPlugins => '这份备份没有插件。';
  @override
  String pluginLine({required Object name, required Object version}) =>
      '${name} ${version}';
  @override
  String get hosts => '会连接的网站';
  @override
  String get listSeparator => '、';
  @override
  String olderThanInstalled({required Object version}) =>
      '比这台的旧（这台是 ${version}）';
  @override
  String addedHosts({required Object hosts}) => '这台目前没有的网站：${hosts}';
  @override
  String get indexesHeading => '备份会带入的自定义插件库';
  @override
  String get unusableHeading => '这些插件在这个版本无法使用，不会还原';
  @override
  String get legacyImport => '从旧版导入…';
  @override
  String get legacyImportWorking => '正在读取旧版数据…';
  @override
  String get legacyChooseTitle => '从哪里导入旧版数据？';
  @override
  String get legacyFromDatabase => '旧版数据库';
  @override
  String get legacyFromDatabaseMissing => '旧版数据库（这台设备上找不到）';
  @override
  String get legacyFromBackup => '旧版备份文件（.json）';
  @override
  String get legacyHint => '这台设备上有旧版 FMP 的数据，还没有导入过。';
  @override
  String get legacyConfirmTitle => '从旧版导入？';
  @override
  String get legacyConfirmBody =>
      '会替换当前的歌单、曲目、播放历史、队列与电台，以及旧版有的设置；保留已安装的插件、插件设置与这台设备当前的登录。替换前会自动备份。';
  @override
  String get legacyWillImport => '将导入';
  @override
  String legacyQueue({required Object count}) => '队列：${count}';
  @override
  String get legacyBackupNoQueue => '旧版备份文件不含队列，替换后队列是空的。';
  @override
  String get legacyConfirm => '替换并重新启动';
  @override
  String get legacyWorking => '正在替换…';
  @override
  String legacyFailed({required Object message}) => '导入没有完成：${message}';
  @override
  String get legacyRejectedNotBackup => '这不是旧版 FMP 的备份文件。';
  @override
  String get legacyRejectedNewer => '这份备份来自较新版的 FMP，无法导入。';
  @override
  String get legacyRejectedCorrupt => '备份文件已损坏。';
  @override
  String get legacyRejectedEmpty => '这份备份没有可导入的数据。';
  @override
  String get confirm => '还原并重新启动';
  @override
  String get cancel => '取消';
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
  @override
  String get shuffle => '随机播放';
  @override
  String get loopOff => '循环：关闭';
  @override
  String get loopAll => '循环：全部';
  @override
  String get loopOne => '循环：单曲';
  @override
  String get more => '更多';
  @override
  String queueFull({required Object count}) => '队列已满（最多 ${count} 首），没有添加';
  @override
  String get retrying => '重试中';
  @override
  String get waitingForNetwork => '等待网络连接';
  @override
  String get preview => '试听';
  @override
  String trackSkipped({required Object title, required Object reason}) =>
      '已跳过「${title}」：${reason}';
  @override
  String cannotPlay({required Object title, required Object reason}) =>
      '无法播放「${title}」：${reason}';
  @override
  String stoppedAfterFailures({required Object count}) =>
      '连续 ${count} 首无法播放，已停止播放';
  @override
  String previewPlaying({required Object title}) => '「${title}」只有试听片段';
  @override
  String get outputDeviceFailed => '音频输出设备无法使用，已暂停播放';
  @override
  String get outputDeviceFellBack => '音频输出设备无法使用，已改用系统默认';
  @override
  String get shuffleTooltip => '随机播放（Ctrl+S）';
  @override
  String get shuffleInMixTooltip => 'Mix 中无法随机播放';
  @override
  String get shuffleInMix => '随机播放（Mix 中无法使用）';
  @override
  String get loopOffTooltip => '循环：关闭（Ctrl+R）';
  @override
  String get loopAllTooltip => '循环：全部（Ctrl+R）';
  @override
  String get loopOneTooltip => '循环：单曲（Ctrl+R）';
  @override
  String get loopOffInMix => '循环：关闭（Mix 中没有“全部”）';
  @override
  String get loopOneInMix => '循环：单曲（Mix 中没有“全部”）';
  @override
  String get loopOffInMixTooltip => '循环：关闭（Ctrl+R；Mix 中没有“全部”）';
  @override
  String get loopOneInMixTooltip => '循环：单曲（Ctrl+R；Mix 中没有“全部”）';
  @override
  String get volume => '音量';
  @override
  String get volumeTooltip => '音量（Ctrl+↑／↓）';
  @override
  String get mute => '静音';
  @override
  String get unmute => '取消静音';
  @override
  String get outputDevice => '输出设备';
  @override
  String get systemDefault => '系统默认';
  @override
  String get liveBadge => '直播中';
  @override
  String get liveEnded => '直播已结束';
  @override
  String get liveStatusFailed => '查询失败';
  @override
  String get liveStopped => '已停止';
  @override
  String get liveReconnecting => '重新连接中';
  @override
  String liveCannotPlay({required Object reason}) => '无法播放：${reason}';
  @override
  String liveListened({required Object time}) => '已收听 ${time}';
  @override
  String liveOnline({required Object count}) => '${count} 人在看';
  @override
  String get stopLive => '停止收听';
  @override
  String get liveHost => '主播';
  @override
  String get liveViewers => '观看人数';
}

// Path: playerPage
class Translations$playerPage$zh_CN extends Translations$playerPage$zh_TW {
  Translations$playerPage$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get openHint => '打开播放页';
  @override
  String get closeTooltip => '关闭播放页（Esc）';
  @override
  String get infoTooltip => '歌曲信息';
  @override
  String get closeInfoTooltip => '关闭歌曲信息';
  @override
  String get speed => '播放速度';
  @override
  String speedValue({required Object speed}) => '${speed}×';
  @override
  String get detailsUploader => '上传者';
  @override
  String get detailsDuration => '时长';
  @override
  String get detailsSource => '音源';
  @override
  String get detailsPublished => '发布时间';
  @override
  String get detailsAlbum => '专辑';
  @override
  String get detailsDescription => '简介';
  @override
  String get detailsExpand => '展开';
  @override
  String get detailsCollapse => '收起';
  @override
  String get detailsLoading => '正在加载详细信息';
  @override
  String get detailsFailed => '无法获取详细信息';
  @override
  String get detailsRetry => '重试';
  @override
  String get statView => '播放';
  @override
  String get statLike => '点赞';
  @override
  String get statFavorite => '收藏';
  @override
  String get statComment => '评论';
  @override
  String get statShare => '分享';
  @override
  String get statDanmaku => '弹幕';
  @override
  String get statCoin => '投币';
  @override
  String queueCount({required num count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        count,
        other: '共 ${count} 首',
      );
  @override
  String get queueShuffleNote => '随机顺序跟着位置；拖动只换歌，不改顺序';
  @override
  String queueMixNote({required Object title}) => 'Mix：${title}';
  @override
  String get queueStartMix => '开始 Mix';
  @override
  String get queueClear => '清空队列';
  @override
  String get queueClearTitle => '清空队列？';
  @override
  String get queueClearBody => '队列里的歌都会移除并停止播放。播放历史与设置不受影响。';
  @override
  String get queueClearConfirm => '清空';
  @override
  String get queueCancel => '取消';
  @override
  String get queueCleared => '已清空队列';
  @override
  String get queueMore => '更多选项';
  @override
  String get queuePlayNext => '下一首播放';
  @override
  String get queueRemove => '从队列移除';
  @override
  String get queueReorder => '拖动以重新排列';
  @override
  String get queueTitle => '队列';
  @override
  String get queueShuffle => '打乱';
  @override
  String get queueShuffled => '已打乱';
  @override
  String get queueJumpTop => '跳到顶部';
  @override
  String get queueJumpBottom => '跳到底部';
  @override
  String queuePlayingAt({required Object index}) => '正在播放第 ${index} 首';
  @override
  String queueRemoveTrack({required Object title}) => '从队列移除「${title}」';
  @override
  String get queueMixLoading => '正在加载更多歌曲';
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
  @override
  String get themeColor => '主题色';
  @override
  String get themeColorCustom => '自定义颜色';
  @override
  String get customColorTitle => '自定义主题色';
  @override
  String get customColorHex => '色值（HEX）';
  @override
  String get customColorHexInvalid => '请输入 6 位色值，例如 6750A4';
  @override
  String get customColorHue => '色相';
  @override
  String get customColorSaturation => '饱和度';
  @override
  String get customColorBrightness => '明度';
  @override
  String get customColorApply => '应用';
  @override
  String get customColorCancel => '取消';
  @override
  late final Translations$appearance$presets$zh_CN presets =
      Translations$appearance$presets$zh_CN.internal(_root);
  @override
  String get font => '字体';
  @override
  String get fontSystem => '默认字体';
  @override
  late final Translations$appearance$fonts$zh_CN fonts =
      Translations$appearance$fonts$zh_CN.internal(_root);
}

// Path: playback
class Translations$playback$zh_CN extends Translations$playback$zh_TW {
  Translations$playback$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get audioQuality => '音质';
  @override
  String get audioQualityHint => '适用于所有音源';
  @override
  String get qualityHigh => '高';
  @override
  String get qualityMedium => '中';
  @override
  String get qualityLow => '低';
  @override
  String get qualityHighDescription => '高：最高码率，音质最佳';
  @override
  String get qualityMediumDescription => '中：中等码率，平衡音质与流量';
  @override
  String get qualityLowDescription => '低：最低码率，省流量';
  @override
  String get qualityFallback => '音源没有所选的那一级时，会改用其他可用的一级';
  @override
  String get formatPriority => '格式偏好';
  @override
  String get formatPriorityHint => '音源同时提供两种格式时先选哪一种';
  @override
  String get formatOpusFirst => 'Opus 优先';
  @override
  String get formatAacFirst => 'AAC 优先';
  @override
  String get rememberPosition => '记住播放位置';
  @override
  String get rememberPositionHint => '临时播放结束回到队列或重新打开 App 时，从原来的位置继续';
  @override
  String get tempPlayRewind => '临时播放回队列后退';
  @override
  String get tempPlayRewindHint => '回到原来的位置时稍微往回一点，方便接上';
  @override
  String get rewindNone => '不后退';
  @override
  String rewindSeconds({required Object seconds}) => '${seconds} 秒';
  @override
  String optionDefault({required Object label}) => '${label}（默认）';
  @override
  String get skipPreviewClips => '跳过试听片段';
  @override
  String get skipPreviewClipsHint => '只有试听片段的歌曲直接跳过；关闭时照播并标示「试听」';
  @override
  String get restartRewind => '重启后恢复后退';
  @override
  String get restartRewindHint => '重新打开 App 后按播放，从上次的位置稍微往回一点，方便接上';
  @override
  String get playHistoryLimit => '播放历史保留条数';
  @override
  String get playHistoryLimitHint => '超过的旧记录会自动删除；调小时立即删除';
  @override
  String playHistoryLimitOption({required Object count}) => '${count} 条';
  @override
  String get autoScrollToCurrent => '切歌时滚动到当前歌曲';
  @override
  String get autoScrollToCurrentHint => '队列列表打开时，换歌后自动滚动到正在播放的那一首';
}

// Path: network
class Translations$network$zh_CN extends Translations$network$zh_TW {
  Translations$network$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get cacheLimit => '缓存上限';
  @override
  String cacheLimitDefault({required Object size}) => '${size}（默认）';
  @override
  String get usage => '缓存用量';
  @override
  String get artwork => '封面';
  @override
  String get charts => '排行';
  @override
  String get clear => '清除缓存';
  @override
  String get clearTitle => '清除缓存？';
  @override
  String get clearBody => '已缓存的封面会被删除，需要时重新下载。设置和数据不受影响。';
  @override
  String get cancel => '取消';
  @override
  String get cleared => '已清除缓存';
  @override
  String get radioInterval => '电台状态刷新间隔';
  @override
  String get radioIntervalHint => '多久查一次电台是否开播；App 在后台或离线时不查。';
  @override
  String get radioIntervalOff => '关闭';
  @override
  String radioIntervalMinutes({required Object minutes}) => '${minutes} 分钟';
  @override
  String get chartInterval => '排行刷新间隔';
  @override
  String get chartIntervalHint => '多久更新一次首页的排行；App 在后台或离线时不更新。';
  @override
  String get chartIntervalOff => '关闭';
  @override
  String chartIntervalMinutes({required Object minutes}) => '${minutes} 分钟';
  @override
  String optionDefault({required Object label}) => '${label}（默认）';
}

// Path: librarySettings
class Translations$librarySettings$zh_CN
    extends Translations$librarySettings$zh_TW {
  Translations$librarySettings$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get homeCharts => '首页排行';
  @override
  String get homeChartsHint => '勾选要在首页显示的排行，拖动调整顺序。';
  @override
  String get noCharts => '没有提供排行的音源';
  @override
  String get noChartsHint => '安装并启用提供排行的插件后，它的榜单会出现在这里。';
  @override
  String get reorder => '拖动以排序';
  @override
  String reorderFailed({required Object reason}) => '无法调整顺序：${reason}';
  @override
  String toggleFailed({required Object reason}) => '无法更改首页排行：${reason}';
  @override
  String get matchTargets => '匹配目标音源';
  @override
  String get matchTargetsHint =>
      '从不能播放的音源导入、或匹配到其他音源时，在勾选的音源搜索同一首歌；分数相同时按这个顺序。拖动调整顺序。';
  @override
  String get noMatchTargets => '没有可以作为匹配目标的音源';
  @override
  String get noMatchTargetsHint => '安装并启用能搜索与播放的插件，它就会出现在这里。';
  @override
  String matchReorderFailed({required Object reason}) =>
      '无法调整匹配目标的顺序：${reason}';
  @override
  String matchToggleFailed({required Object reason}) => '无法更改匹配目标：${reason}';
}

// Path: importPreview
class Translations$importPreview$zh_CN
    extends Translations$importPreview$zh_TW {
  Translations$importPreview$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '导入预览';
  @override
  String get cancel => '取消导入';
  @override
  String from({required Object source}) => '来自 ${source}';
  @override
  String reading({required Object count}) => '读取中 ${count} 首';
  @override
  String readFailed({required Object reason}) => '读不到歌单：${reason}';
  @override
  String get retry => '重试';
  @override
  String songs({required Object count}) => '${count} 首';
  @override
  String get songsOne => '1 首';
  @override
  String searchesEach({required Object count}) => '每首会在 ${count} 个音源搜索';
  @override
  String get searchesEachOne => '每首会在 1 个音源搜索';
  @override
  String reused({required Object count}) => '${count} 首沿用之前的匹配';
  @override
  String get targets => '匹配目标';
  @override
  String get noTargets => '没有可以匹配的音源：安装并启用能搜索与播放的插件。';
  @override
  String get pickTarget => '至少勾选一个音源';
  @override
  String get lastTarget => '至少要有一个匹配目标';
  @override
  String get start => '开始匹配';
  @override
  String progress({required Object done, required Object total}) =>
      '已匹配 ${done}/${total}';
  @override
  String currentSong({required Object title}) => '正在匹配：${title}';
  @override
  String get truncated => '来源只提供了部分曲目';
  @override
  String get pending => '等待中';
  @override
  String get searching => '搜索中…';
  @override
  String get unmatched => '匹配失败';
  @override
  String get searchFailed => '搜索失败';
  @override
  String get excluded => '已排除';
  @override
  String get reusedTag => '沿用之前的匹配';
  @override
  String get reusedHint => '沿用之前的匹配，没有重新搜索。重搜可以看其他候选。';
  @override
  String score({required Object percent}) => '${percent}%';
  @override
  String get noCandidates => '没有候选';
  @override
  String get showCandidates => '显示候选';
  @override
  String get hideCandidates => '收起候选';
  @override
  String get keyword => '搜索关键词';
  @override
  String get research => '重搜';
  @override
  String get exclude => '排除';
  @override
  String get include => '取消排除';
  @override
  String get create => '创建歌单';
  @override
  String skipped({required Object count}) => '${count} 首不会加入';
  @override
  String get skippedOne => '1 首不会加入';
  @override
  String get created => '已创建歌单';
  @override
  String createFailed({required Object reason}) => '无法创建歌单：${reason}';
  @override
  String get leaveTitle => '放弃这次导入？';
  @override
  String get leaveBody => '目前的匹配结果会丢掉，什么都不会保存。';
  @override
  String get leaveConfirm => '放弃';
  @override
  String get leaveKeep => '继续';
  @override
  String largeTitle({required Object count}) => '要搜索约 ${count} 次';
  @override
  String get largeBody => '这会花一些时间。可以先减少匹配目标，搜索的次数就会少一些。';
  @override
  String get largeBodyOneTarget => '这会花一些时间。';
  @override
  String get largeCancel => '取消';
  @override
  String get largeStart => '开始';
}

// Path: radio
class Translations$radio$zh_CN extends Translations$radio$zh_TW {
  Translations$radio$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '电台';
  @override
  String get addFromUrl => '通过网址添加';
  @override
  String get refresh => '刷新状态';
  @override
  String get urlTitle => '通过网址添加电台';
  @override
  String get urlLabel => '直播间网址';
  @override
  String get add => '添加';
  @override
  String get cancel => '取消';
  @override
  String get added => '已添加到电台';
  @override
  String get alreadyAdded => '已在电台列表中';
  @override
  String get unrecognizedUrl => '无法识别这个网址';
  @override
  String addFailed({required Object reason}) => '无法添加电台：${reason}';
  @override
  String get refreshed => '已更新电台状态';
  @override
  String get nothingToRefresh => '没有可以刷新的电台';
  @override
  String refreshFailed({required Object reason}) => '无法刷新状态：${reason}';
  @override
  String get refreshOffline => '离线中，未刷新：显示的是上次查到的状态';
  @override
  String get retry => '重试';
  @override
  String get working => '处理中';
  @override
  String get empty => '还没有电台';
  @override
  String get emptyHint => '在搜索页切换到“直播间”，从结果的菜单“添加到电台”；或通过直播间的网址添加。';
  @override
  String get statusLive => '开播中';
  @override
  String get statusOffline => '未开播';
  @override
  String get statusFailed => '查询失败';
  @override
  String get statusUnchecked => '尚未查询';
  @override
  String get more => '更多选项';
  @override
  String get remove => '删除';
  @override
  String get removeTitle => '删除电台？';
  @override
  String removeBody({required Object title}) => '“${title}”将从电台列表中移除。';
  @override
  String get removed => '已删除电台';
  @override
  String removeFailed({required Object reason}) => '无法删除电台：${reason}';
  @override
  String get reorder => '拖动以排序';
  @override
  String reorderFailed({required Object reason}) => '无法调整顺序：${reason}';
  @override
  String cannotPlay({required Object reason}) => '无法收听：${reason}';
  @override
  String get sort => '排序';
  @override
  String get sortDone => '完成';
  @override
  String get sortModeHint => '拖动手柄调整顺序；退出排序模式后，开播中的电台会排在前面。';
  @override
  String get urlHint => '粘贴直播间的网址，由已启用的音源识别。';
}

// Path: sources
class Translations$sources$zh_CN extends Translations$sources$zh_TW {
  Translations$sources$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get notInstalled => '音源未安装';
  @override
  String get disabled => '音源已停用';
}

// Path: plugins
class Translations$plugins$zh_CN extends Translations$plugins$zh_TW {
  Translations$plugins$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get tabInstalled => '已安装';
  @override
  String get tabAvailable => '可安装';
  @override
  String get checkUpdates => '检查更新';
  @override
  String get updateAll => '全部更新';
  @override
  String get more => '更多选项';
  @override
  String get installFromFile => '从文件安装';
  @override
  String get installFromUrl => '从网址安装';
  @override
  String get manageIndexes => '管理插件库';
  @override
  String get working => '处理中';
  @override
  String get noneInstalled => '还没有安装插件';
  @override
  String get noneInstalledHint => '到“可安装”标签页挑选要安装的插件';
  @override
  String versionAuthor({required Object version, required Object author}) =>
      '${version} · ${author}';
  @override
  String get tagDisabled => '已停用';
  @override
  String get tagUnresponsive => '无响应';
  @override
  String get tagUpdate => '有更新';
  @override
  String get tagMismatch => '与插件库不一致';
  @override
  String get tagInstalled => '已安装';
  @override
  String get tagDev => '开发中';
  @override
  String get devManaged => '开发中的插件由 Debug 页“插件开发”管理，卸载后才能启用、更新或移除。';
  @override
  String enable({required Object name}) => '启用“${name}”';
  @override
  String get showDetails => '详细信息';
  @override
  String get hideDetails => '收起详细信息';
  @override
  String get capabilities => '能力';
  @override
  String get hosts => '会连接的域名';
  @override
  String get source => '来源';
  @override
  String get listSeparator => '、';
  @override
  String get sourceOfficial => '官方插件库';
  @override
  String sourceCustom({required Object url}) => '自定义插件库：${url}';
  @override
  String get sourceLocal => '从文件或网址安装';
  @override
  String get customIndex => '自定义插件库';
  @override
  String updateTo({required Object version}) => '更新到 ${version}';
  @override
  String get reinstall => '从插件库重新安装';
  @override
  String reinstalled({required Object name}) => '已从插件库重新安装“${name}”';
  @override
  String get needsAppUpdate => '需要更新 FMP';
  @override
  String get remove => '移除';
  @override
  String get install => '安装';
  @override
  String installTitle({required Object name}) => '安装“${name}”？';
  @override
  String get installAllTitle => '安装这些插件？';
  @override
  String updateTitle({required Object name}) => '更新“${name}”？';
  @override
  String byline({required Object author, required Object version}) =>
      '作者 ${author} · 版本 ${version}';
  @override
  String get addedAccess => '新版本比当前版本多了以下能力或域名，确认后才会更新。';
  @override
  String get addedCapabilities => '新增的能力';
  @override
  String get addedHosts => '新增的域名';
  @override
  String get loginWarning => '此脚本会以你的登录身份访问这些网站。';
  @override
  String get unofficial => '非官方来源：这个插件没有经过 FMP 审查。';
  @override
  String replaces({required Object version}) => '会替换已安装的版本 ${version}。';
  @override
  String get cancel => '取消';
  @override
  String get confirmInstall => '安装';
  @override
  String get confirmUpdate => '更新';
  @override
  String removeTitle({required Object name}) => '移除“${name}”？';
  @override
  String get removeBody => '插件及其数据、登录、缓存都会删除。曲目会保留，显示“音源未安装”。';
  @override
  String get confirmRemove => '移除';
  @override
  String installed({required Object name}) => '已安装“${name}”';
  @override
  String updated({required Object name, required Object version}) =>
      '已将“${name}”更新到 ${version}';
  @override
  String updatedCount({required Object count}) => '已更新 ${count} 个插件';
  @override
  String removed({required Object name}) => '已移除“${name}”';
  @override
  String get upToDate => '插件都是最新版本';
  @override
  String updatesFound({required Object count}) => '有 ${count} 个插件可以更新';
  @override
  String mismatchFound({required Object count}) =>
      '有 ${count} 个插件与插件库不一致，可以从插件库重新安装';
  @override
  String get checkFailed => '有插件库读取失败，可能还有更新没找到';
  @override
  String get hashMismatch => '插件库刚更新，请稍后再试';
  @override
  String get manifestMismatch => '插件文件与插件库的数据不一致，未安装';
  @override
  String get appUpdateRequired => '需要更新 FMP 才能安装这个插件';
  @override
  String installFailed({required Object name, required Object reason}) =>
      '无法安装“${name}”：${reason}';
  @override
  String installFileFailed({required Object reason}) => '无法安装插件：${reason}';
  @override
  String updateFailed({required Object name, required Object reason}) =>
      '无法更新“${name}”：${reason}';
  @override
  String removeFailed({required Object name, required Object reason}) =>
      '无法移除“${name}”：${reason}';
  @override
  String enableFailed({required Object name, required Object reason}) =>
      '无法启用“${name}”：${reason}';
  @override
  String disableFailed({required Object name, required Object reason}) =>
      '无法停用“${name}”：${reason}';
  @override
  String get indexLoadFailed => '无法读取这个插件库';
  @override
  String get indexNeedsAppUpdate => '需要更新 FMP 才能读取这个插件库';
  @override
  String get indexEmpty => '这个插件库没有插件';
  @override
  String get allFailed => '无法读取插件库';
  @override
  String get retry => '重试';
  @override
  String get urlLabel => '插件文件的网址（https）';
  @override
  String get urlInvalid => '请输入以 https 开头的网址';
  @override
  String get download => '下载';
  @override
  String get indexesTitle => '插件库';
  @override
  String get addIndex => '添加插件库';
  @override
  String get indexUrlLabel => 'index.json 的网址（https）';
  @override
  String get indexWarning => '非官方来源：这个列表的插件没有经过 FMP 审查。';
  @override
  String get add => '添加';
  @override
  String get removeIndex => '移除这个插件库';
  @override
  String get indexAdded => '已添加插件库';
  @override
  String get indexRemoved => '已移除插件库';
  @override
  String get indexExists => '这个插件库已在列表中';
  @override
  String get close => '关闭';
  @override
  late final Translations$plugins$capabilityNames$zh_CN capabilityNames =
      Translations$plugins$capabilityNames$zh_CN.internal(_root);
}

// Path: onboarding
class Translations$onboarding$zh_CN extends Translations$onboarding$zh_TW {
  Translations$onboarding$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '安装插件后才能开始搜索';
  @override
  String get body => '插件让 FMP 连接各个音乐来源。勾选想用的；之后随时可以到“设置 > 插件”调整。';
  @override
  String get later => '稍后再说';
  @override
  String get goToPlugins => '前往插件页';
  @override
  String get loading => '正在加载插件';
  @override
  String installedCount({required Object count}) => '已安装的插件：${count}';
  @override
  String get failedTitle => '有些插件没有安装成功';
}

// Path: accounts
class Translations$accounts$zh_CN extends Translations$accounts$zh_TW {
  Translations$accounts$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get none => '没有可以登录的音源';
  @override
  String get noneHint => '安装支持登录的插件之后，就能在这里登录。';
  @override
  String get goToPlugins => '前往插件页';
  @override
  String get loadFailed => '无法读取账号';
  @override
  String get working => '处理中';
  @override
  String get notLoggedIn => '未登录';
  @override
  String get statusActive => '正常';
  @override
  String get statusInvalidated => '已失效';
  @override
  String get statusUnreadable => '暂时无法读取，稍后重试';
  @override
  String get browseAsLoggedIn => '以登录身份浏览与播放';
  @override
  String get automationRisk => '以登录身份大量请求可能被视为自动化行为（推测）';
  @override
  String get loginQr => '扫码登录';
  @override
  String get loginWebView => '网页登录';
  @override
  String get loginCookie => '粘贴 Cookie';
  @override
  String get relogin => '重新登录';
  @override
  String get signIn => '登录';
  @override
  String invalidatedPrompt({required Object name}) => '${name}的登录已失效';
  @override
  String lastRefresh({required Object time, required Object result}) =>
      '最后刷新：${time}，${result}';
  @override
  String get refreshRefreshed => '已更新凭证';
  @override
  String get refreshUnchanged => '无需更新';
  @override
  String get refreshFailed => '失败';
  @override
  String get logout => '退出登录';
  @override
  String noMethod({required Object name}) => '此平台还不能登录“${name}”';
  @override
  String logoutTitle({required Object name}) => '退出登录“${name}”？';
  @override
  String get logoutBody => 'FMP 中这个音源的登录数据会被删除。“以登录身份浏览与播放”的设置会保留。';
  @override
  String get confirmLogout => '退出登录';
  @override
  String get cancel => '取消';
  @override
  String loggedIn({required Object name}) => '已登录“${name}”';
  @override
  String loggedOut({required Object name}) => '已退出登录“${name}”';
  @override
  String loginFailed({required Object name, required Object reason}) =>
      '无法登录“${name}”：${reason}';
  @override
  String logoutFailed({required Object name, required Object reason}) =>
      '无法退出登录“${name}”：${reason}';
  @override
  String settingFailed({required Object reason}) => '无法保存设置：${reason}';
  @override
  String qrTitle({required Object name}) => '扫码登录“${name}”';
  @override
  String get qrImage => '登录用的二维码';
  @override
  String get qrStarting => '正在生成二维码';
  @override
  String get qrWaiting => '用手机上的 App 扫描二维码';
  @override
  String get qrScanned => '已扫描，请在手机上确认';
  @override
  String get qrExpired => '二维码已过期';
  @override
  String get verifying => '正在确认登录';
  @override
  String get qrRegenerate => '重新生成';
  @override
  String get retry => '重试';
  @override
  String get close => '关闭';
  @override
  String webTitle({required Object name}) => '登录“${name}”';
  @override
  String get webLoading => '正在打开登录页';
  @override
  String get webStuckTitle => '登录没有完成';
  @override
  String get webStuckBody => '页面停在跳转中。点“重试”重新打开登录页，一般不用再输入一次账号密码。';
  @override
  String get webStuckRestart =>
      '还是没有完成。请关闭 FMP 再重新打开，然后再点一次“网页登录”；网页上的登录状态会保留。';
  @override
  String get webFailed => '无法打开登录页';
  @override
  String cookieTitle({required Object name}) => '粘贴“${name}”的 Cookie';
  @override
  String get cookieLabel => 'Cookie';
  @override
  String get cookieHint => 'name=value; name2=value2';
  @override
  String get cookieHelpTitle => '如何获取';
  @override
  String get cookieStep1 => '在电脑的浏览器中登录这个网站。';
  @override
  String get cookieStep2 => '按 F12 打开开发者工具，在“网络”标签页刷新页面，选一个发往这个网站的请求。';
  @override
  String get cookieStep3 => '在请求标头中找到“Cookie”，复制整个值粘贴到上面。';
  @override
  String get cookieFile => '也可以粘贴浏览器扩展导出的 cookies.txt（Netscape 格式）内容。';
  @override
  String get cookieWarning => 'Cookie 相当于你的登录，不要交给别人。FMP 只把它保存在这台设备上。';
  @override
  String get cookieEmpty => '没有读到 Cookie。请粘贴 name=value 格式的内容或 cookies.txt。';
  @override
  String cookieRejected({required Object name}) =>
      '“${name}”不接受这些 Cookie。请从已登录的页面重新复制。';
  @override
  String loginRejected({required Object name}) => '“${name}”没有接受这次登录，请再试一次。';
  @override
  String get playlists => '歌单';
  @override
  String playlistsTitle({required Object name}) => '${name} 的歌单';
  @override
  String get playlistsEmpty => '这个账号还没有歌单';
  @override
  String get playlistsFailed => '无法读取歌单';
  @override
  String get playlistWritable => '可写';
  @override
  String get playlistImported => '已导入';
  @override
  String playlistSelect({required Object name}) => '选取“${name}”';
  @override
  String importSelected({required Object count}) => '导入所选 (${count})';
  @override
  String get importPageTitle => '导入歌单';
  @override
  String importOverall({required Object done, required Object total}) =>
      '歌单 ${done}／${total}';
  @override
  String itemProgress({required Object count}) => '已读 ${count} 首';
  @override
  String itemProgressOf({required Object count, required Object total}) =>
      '已导入 ${count}／${total} 首';
  @override
  String get itemWaiting => '等待中';
  @override
  String get itemImporting => '导入中';
  @override
  String get itemDone => '完成';
  @override
  String get itemCancelled => '已取消';
  @override
  String get importCancel => '取消';
  @override
  String get importFinish => '完成';
  @override
  String importCancelled({required Object count}) => '已取消：已导入 ${count} 张';
  @override
  String playlistImportFailed({required Object reason}) => '导入失败：${reason}';
  @override
  String get playlistUnsupported => '这个来源还不能导入歌单';
  @override
  String importedCount({required Object count}) => '已导入 ${count} 张';
  @override
  String importedWithFailures({
    required Object count,
    required Object failed,
  }) => '已导入 ${count} 张，${failed} 张失败';
  @override
  String get more => '更多选项';
  @override
  String get liveImport => '从账号导入电台';
  @override
  String liveImportBoth({required Object added, required Object existing}) =>
      '新增 ${added} 个，${existing} 个已在电台列表';
  @override
  String liveImportAdded({required Object added}) => '新增 ${added} 个';
  @override
  String liveImportAllExisting({required Object existing}) =>
      '${existing} 个已在电台列表';
  @override
  String get liveImportEmpty => '这个账号没有关注的直播间';
  @override
  String liveImportFailed({required Object reason}) => '无法导入电台：${reason}';
  @override
  String get selectAll => '全选';
  @override
  String get deselectAll => '取消全选';
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

// Path: errorReport
class Translations$errorReport$zh_CN extends Translations$errorReport$zh_TW {
  Translations$errorReport$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '错误详情';
  @override
  String get actionDetail => '详细';
  @override
  String get actionReport => '反馈';
  @override
  String get copy => '复制';
  @override
  String get copied => '已复制';
  @override
  String get reportOnGitHub => '在 GitHub 反馈';
  @override
  String get reportCopied => '报告已复制，请粘贴到 GitHub 的“错误报告”一栏';
  @override
  String get openFailed => '无法打开浏览器，请自行打开下方的网址';
  @override
  String get manualHint => '请在浏览器打开以下网址，并粘贴已复制的报告';
  @override
  String get reminderTitle => '提交前请检查';
  @override
  String get reminderBody =>
      'FMP 的 GitHub 仓库是公开的，所有人都看得到报告。报告已遮蔽 cookie、token 与签名网址，但提交前请再检查一次内容。';
  @override
  String get reminderDontAsk => '不再提醒';
  @override
  String get reminderContinue => '继续';
  @override
  String get cancel => '取消';
  @override
  String get time => '时间';
  @override
  String get type => '错误类型';
  @override
  String get reason => '原因类别';
  @override
  String get source => '音源';
  @override
  String get action => '用户操作';
  @override
  String get module => '模块';
  @override
  String get request => '请求';
  @override
  String get status => '状态码';
  @override
  String get duration => '耗时';
  @override
  String get requestError => '请求错误';
  @override
  String get noRequest => '没有对应的请求记录';
  @override
  String get app => 'App';
  @override
  String get system => '系统';
  @override
  String get cause => '原因';
  @override
  String get stackTrace => 'Stack trace';
}

// Path: startup.legacyImport
class Translations$startup$legacyImport$zh_CN
    extends Translations$startup$legacyImport$zh_TW {
  Translations$startup$legacyImport$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get title => '正在从旧版导入数据';
  @override
  String get stepRead => '读取旧数据';
  @override
  String get stepConvert => '转换';
  @override
  String get stepWrite => '写入';
  @override
  String get stepVerify => '验证';
  @override
  String get stepDone => '完成';
  @override
  String get failedTitle => '无法导入旧版数据';
  @override
  String failedStep({required Object step}) => '失败的步骤：${step}';
  @override
  String get detailsHint => '详细原因可以用「导出诊断」保存下来。';
  @override
  String get safeNote => '旧数据没有被改动，之后可以在设置页再导入。';
  @override
  String get startBlank => '以空白数据启动';
}

// Path: legacyResult.unimported
class Translations$legacyResult$unimported$zh_CN
    extends Translations$legacyResult$unimported$zh_TW {
  Translations$legacyResult$unimported$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get streamPriority => '各音源的串流优先顺序';
  @override
  String get cacheLimit => '缓存上限';
  @override
  String get homeRanking => '首页排行的顺序与停用';
}

// Path: settings.summary
class Translations$settings$summary$zh_CN
    extends Translations$settings$summary$zh_TW {
  Translations$settings$summary$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String appearance({required Object theme}) => '主题：${theme}';
  @override
  String appearanceWithFont({required Object theme, required Object font}) =>
      '主题：${theme} · ${font}';
  @override
  String playback({required Object quality}) => '音质：${quality}';
}

// Path: appearance.presets
class Translations$appearance$presets$zh_CN
    extends Translations$appearance$presets$zh_TW {
  Translations$appearance$presets$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get defaultPurple => '默认紫';
  @override
  String get indigo => '靛蓝';
  @override
  String get blue => '海洋蓝';
  @override
  String get teal => '青绿';
  @override
  String get green => '森林绿';
  @override
  String get yellow => '阳光黄';
  @override
  String get orange => '琥珀橙';
  @override
  String get red => '宝石红';
  @override
  String get pink => '玫瑰粉';
}

// Path: appearance.fonts
class Translations$appearance$fonts$zh_CN
    extends Translations$appearance$fonts$zh_TW {
  Translations$appearance$fonts$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get jhengHei => '微软正黑体';
  @override
  String get yaHei => '微软雅黑';
  @override
  String get pmingliu => '新细明体';
  @override
  String get dfkai => '标楷体';
  @override
  String get sansSerif => '无衬线';
  @override
  String get serif => '衬线';
  @override
  String get monospace => '等宽';
}

// Path: plugins.capabilityNames
class Translations$plugins$capabilityNames$zh_CN
    extends Translations$plugins$capabilityNames$zh_TW {
  Translations$plugins$capabilityNames$zh_CN.internal(TranslationsZhCn root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhCn _root; // ignore: unused_field

  // Translations
  @override
  String get search => '搜索';
  @override
  String get resolveStream => '播放';
  @override
  String get trackDetail => '曲目详情';
  @override
  String get multiPart => '分P';
  @override
  String get importPlaylist => '导入歌单';
  @override
  String get libraryRead => '读取音乐库';
  @override
  String get libraryWrite => '修改音乐库';
  @override
  String get charts => '排行榜';
  @override
  String get live => '直播';
  @override
  String get mix => 'Mix';
  @override
  String get lyrics => '歌词';
  @override
  String get login => '登录';
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
