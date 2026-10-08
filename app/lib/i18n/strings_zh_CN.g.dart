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
  late final Translations$history$zh_CN history =
      Translations$history$zh_CN.internal(_root);
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
  late final Translations$sources$zh_CN sources =
      Translations$sources$zh_CN.internal(_root);
  @override
  late final Translations$plugins$zh_CN plugins =
      Translations$plugins$zh_CN.internal(_root);
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
  @override
  String get history => '历史';
  @override
  String get panelTitle => '正在播放';
  @override
  String get panelEmpty => '没有正在播放的歌曲';
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
  @override
  String get more => '更多选项';
  @override
  String get play => '播放';
  @override
  String get playNext => '下一首播放';
  @override
  String get addToQueue => '添加到队列';
  @override
  String get addedToNext => '已添加为下一首播放';
  @override
  String get addedToQueue => '已添加到队列';
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
  @override
  String get network => '网络';
  @override
  String get back => '返回';
  @override
  String get playback => '播放';
  @override
  String get plugins => '插件';
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
  String get loopOffTooltip => '循环：关闭（Ctrl+R）';
  @override
  String get loopAllTooltip => '循环：全部（Ctrl+R）';
  @override
  String get loopOneTooltip => '循环：单曲（Ctrl+R）';
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
  String get showLyricsTooltip => '显示歌词（Ctrl+L）';
  @override
  String get showArtworkTooltip => '显示封面';
  @override
  String get tabLyrics => '歌词';
  @override
  String get tabQueue => '队列';
  @override
  String get tabDetails => '详情';
  @override
  String get noLyrics => '没有歌词';
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
  String get queueTooltip => '队列（Ctrl+Q）';
  @override
  String queueCount({required Object count}) => '共 ${count} 首';
  @override
  String get queueShuffleNote => '随机顺序跟着位置；拖动只换歌，不改顺序';
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
  String get clear => '清除缓存';
  @override
  String get clearTitle => '清除缓存？';
  @override
  String get clearBody => '已缓存的封面会被删除，需要时重新下载。设置和数据不受影响。';
  @override
  String get cancel => '取消';
  @override
  String get cleared => '已清除缓存';
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
  String get tagInstalled => '已安装';
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
  String get needsAppUpdate => '需要更新 FMP';
  @override
  String get remove => '移除';
  @override
  String get install => '安装';
  @override
  String installTitle({required Object name}) => '安装“${name}”？';
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
  String get removeBody => '插件及其数据、缓存都会删除。曲目会保留，显示“音源未安装”。';
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
