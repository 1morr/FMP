/// 縮圖 URL 工具類
///
/// 用於將高清圖片 URL 轉換為適合顯示尺寸的縮圖 URL，
/// 以減少網路傳輸量、磁碟快取佔用和記憶體使用。
///
/// 支援的圖片源：
/// - Bilibili (hdslb.com)
/// - YouTube (ytimg.com, yt3.ggpht.com)
/// - Netease (music.126.net)
///
/// ## 檔位按「需要的來源高度」選，不是按寬
///
/// 封面框多半是正方形，而 Bilibili / YouTube 的封面是 16:9，配 `BoxFit.cover`
/// 時能用的只有來源的**高**：`@200w` 只有 113px 高，`maxresdefault` 只有
/// 720px 高。把來源寬對上框的邊長會選到矮一檔，畫面就是糊的（issue #107）。
///
/// 因此本類一律先算出需要的來源高度
/// （`displaySize × quantizeDevicePixelRatio(devicePixelRatio)`，見
/// [neededSourceHeight]），再按各家 CDN 的參數反推檔位。
class ThumbnailUrlUtils {
  ThumbnailUrlUtils._();

  /// Bilibili / YouTube 封面的來源長寬比。
  ///
  /// 只用來把「需要的來源高」換算成「需要的來源寬」。對正方形來源
  /// （UP 主頭像）這個係數最多多要一檔，不會裁切：`@{w}w` 只指定寬時
  /// 保持長寬比，任何比 16:9 更方的來源都會得到比要求更多的高。
  static const double wideSourceAspectRatio = 16 / 9;

  /// OS 媒體中繼資料（Windows SMTC / Android 通知）縮圖的目標來源高度。
  ///
  /// 這條路徑沒有 Flutter context 可問 DPR，系統面板的封面也不隨 app 的
  /// 佈局變化，所以直接以來源像素表達、`devicePixelRatio` 傳 1。
  static const double osMediaArtworkHeight = 300;

  /// 落盤圖片（下載的封面／頭像）反推來源尺寸時使用的 DPR。
  ///
  /// 下載服務沒有裝置可問，而同一份檔案可能在任何機器上顯示，所以固定取
  /// 上限。3.0 是實測 `Medium_Phone` AVD `wm density 480` 的值；1440p 旗艦
  /// 更高，但 Bilibili 的 1280 檔位本來就到頂，再調高換不到更大的來源。
  static const double persistedImageDevicePixelRatio = 3.0;

  /// 將 DPR 量化到最接近的 0.5。
  ///
  /// 磁碟快取鍵若使用全精度 DPR，同一 URL 在不同裝置或細微 DPR 差異下會
  /// 生成不同的 key，導致重複下載和重複快取條目。量化到 0.5 可收斂這些
  /// 差異。URL 檔位與磁碟快取邊界共用這個函式，兩者才不會各自分檔；
  /// 記憶體解碼尺寸仍使用全精度 DPR。
  static double quantizeDevicePixelRatio(double devicePixelRatio) {
    return (devicePixelRatio * 2).round() / 2;
  }

  /// 語義檔位在這台裝置上需要的來源高度（實體像素）。
  ///
  /// [displaySize] 是語義圖片元件的邏輯 box 高度（dp），見
  /// `ImageTargetSizes`；[devicePixelRatio] 是裝置 DPR，內部量化。
  static int neededSourceHeight(double displaySize, double devicePixelRatio) {
    final height = displaySize * quantizeDevicePixelRatio(devicePixelRatio);
    return height.ceil().clamp(1, 8192).toInt();
  }

  /// 取得適合顯示尺寸的縮圖 URL
  ///
  /// [url] 原始圖片 URL
  /// [displaySize] 邏輯 box 高度（dp）
  /// [devicePixelRatio] 裝置 DPR
  ///
  /// 返回優化後的 URL，如果無法優化則返回原 URL。
  ///
  /// This is for a single URL consumer that cannot try alternatives, such as
  /// OS media metadata. It does not perform fallback loading. UI and download
  /// paths should use [getOptimizedUrlCandidates] so they can try the next
  /// source-specific candidate when the preferred thumbnail does not exist.
  static String getOptimizedUrl(
    String? url, {
    required double displaySize,
    required double devicePixelRatio,
  }) {
    final candidates = getOptimizedUrlCandidates(
      url,
      displaySize: displaySize,
      devicePixelRatio: devicePixelRatio,
    );
    return candidates.isNotEmpty ? candidates.first : '';
  }

  /// 取得按優先級排序的縮圖候選 URL
  ///
  /// 用於先嘗試優化後的 URL，失敗時再回退到原始 URL。
  /// Preferred for UI rendering, preloading, and downloads because callers can
  /// keep moving through the list when a high-quality CDN variant returns 404.
  static List<String> getOptimizedUrlCandidates(
    String? url, {
    required double displaySize,
    required double devicePixelRatio,
  }) {
    if (url == null || url.isEmpty) return const [];

    // 檔位由「語義 box 高度 × DPR」決定：URL 分檔和磁碟快取邊界共用同一個
    // 量化後的 DPR，兩者才會落在同一檔。
    final targetHeight = neededSourceHeight(displaySize, devicePixelRatio);

    final candidates = <String>[];

    void addCandidate(String candidate) {
      if (candidate.isNotEmpty && !candidates.contains(candidate)) {
        candidates.add(candidate);
      }
    }

    // 根據 URL 域名選擇處理方式
    if (_isBilibiliUrl(url)) {
      for (final candidate in _optimizeBilibiliUrlCandidates(
        url,
        targetHeight,
      )) {
        addCandidate(candidate);
      }
    } else if (_isYouTubeUrl(url) &&
        _isHostOrSubdomain(_hostOf(url), 'ytimg.com')) {
      // YouTube 視頻縮圖：生成從高到低多級質量候選，逐級回退
      for (final candidate in _optimizeYouTubeThumbnailCandidates(
        url,
        targetHeight,
      )) {
        addCandidate(candidate);
      }
    } else if (_isYouTubeUrl(url)) {
      addCandidate(_optimizeYouTubeUrl(url, targetHeight));
    } else if (_isNeteaseUrl(url)) {
      for (final candidate in _optimizeNeteaseUrlCandidates(
        url,
        targetHeight,
      )) {
        addCandidate(candidate);
      }
    }

    // 最後回退到原始 URL。YouTube 的 default/hqdefault/sddefault 是 4:3
    // 檔位，16:9 視頻在這些檔位會被 YouTube 加上下黑邊；用戶界面只顯示
    // 16:9 候選，避免為 16:9 內容額外引入黑邊。原生 4:3 視頻的 16:9 檔位
    // 本身可能被 YouTube 預製黑邊，這屬於源端限制，本層無法消除。
    if (!(_isYouTubeUrl(url) && _isYouTubeBlackBarThumbnail(url))) {
      addCandidate(url);
    }
    return candidates;
  }

  /// 檢查是否為 Bilibili 圖片 URL
  static bool _isBilibiliUrl(String url) {
    final host = _hostOf(url);
    return _isHostOrSubdomain(host, 'hdslb.com') ||
        _isHostOrSubdomain(host, 'bilibili.com');
  }

  /// 檢查是否為 YouTube 圖片 URL
  static bool _isYouTubeUrl(String url) {
    final host = _hostOf(url);
    return _isHostOrSubdomain(host, 'ytimg.com') ||
        _isHostOrSubdomain(host, 'ggpht.com') ||
        _isHostOrSubdomain(host, 'googleusercontent.com');
  }

  static bool _isYouTubeBlackBarThumbnail(String url) {
    final match = RegExp(
      r'/vi(?:_webp)?/[^/]+/([^/]+)\.(?:jpg|webp)',
    ).firstMatch(url);
    final quality = match?.group(1);
    return quality == 'default' ||
        quality == 'hqdefault' ||
        quality == 'sddefault';
  }

  /// Bilibili 寬度檔位（px）。
  ///
  /// Bilibili 圖片服務支援任意尺寸，固定檔位是為了 CDN 快取命中率，
  /// 不按每個 box 逐張生成。
  static const List<int> bilibiliWidthTiers = [200, 400, 640, 1280];

  /// 選擇 Bilibili 合適的尺寸檔位
  ///
  /// 以需要的來源**高度**反推寬：16:9 的封面要 `高 × 16/9` 的寬才有足夠的
  /// 高。刻意不用 `@{w}w_{h}h` 同時指定寬高 —— 那會對非 16:9 的來源
  /// （UP 主頭像、方形歌單封面）做居中裁切，而只指定寬既保長寬比，又保證
  /// 任何比 16:9 更方的來源得到的高只會更多。
  ///
  /// 需要的寬超過最大檔位時取 [bilibiliWidthTiers] 的最大值：那是這個來源
  /// 能給的上限，再往上只剩原圖回退。
  static int selectBilibiliWidth(int neededHeight) {
    final neededWidth = (neededHeight * wideSourceAspectRatio).ceil();
    for (final tier in bilibiliWidthTiers) {
      if (neededWidth <= tier) return tier;
    }
    return bilibiliWidthTiers.last;
  }

  /// 生成 Bilibili 縮圖多級尺寸候選 URL（從高到低）
  ///
  /// 從期望尺寸向下逐級生成候選，避免直接回退到原始大圖。
  static List<String> _optimizeBilibiliUrlCandidates(
    String url,
    int neededHeight,
  ) {
    // 先去掉 query string（如 ?t=123），再去掉已有的 @ 尺寸後綴，
    // 避免生成 `...jpg?t=123@1280w.jpg` 這類錯誤 URL（與 NetEase 路徑一致）。
    final withoutQuery = url.split('?').first;
    final baseUrl = withoutQuery.contains('@')
        ? withoutQuery.substring(0, withoutQuery.indexOf('@'))
        : withoutQuery;
    final desiredWidth = selectBilibiliWidth(neededHeight);

    final candidates = <String>[];
    for (final width in bilibiliWidthTiers.reversed) {
      if (width > desiredWidth) continue;
      candidates.add('$baseUrl@${width}w.jpg');
    }
    // 不包含原圖本身，由 getOptimizedUrlCandidates 添加
    return candidates;
  }

  /// 優化 YouTube 圖片 URL
  ///
  /// YouTube 縮圖 URL 格式：
  /// - https://i.ytimg.com/vi/{videoId}/{quality}.jpg
  ///
  /// 可用的質量檔位（括號內為高度，選檔只看高）：
  /// - default.jpg (120x90，4:3)
  /// - mqdefault.jpg (320x180，16:9)
  /// - hqdefault.jpg (480x360，4:3)
  /// - sddefault.jpg (640x480，4:3)
  /// - maxresdefault.jpg (1280x720，16:9)
  ///
  /// 頻道頭像 URL 格式（ggpht.com）：
  /// - https://yt3.ggpht.com/xxx=s{size}-c-k-c0x00ffffff-no-rj
  static String _optimizeYouTubeUrl(String url, int neededHeight) {
    // 處理視頻縮圖
    if (_isHostOrSubdomain(_hostOf(url), 'ytimg.com')) {
      return _optimizeYouTubeThumbnail(url, neededHeight);
    }

    // 處理頻道頭像
    final host = _hostOf(url);
    if (_isHostOrSubdomain(host, 'ggpht.com') ||
        _isHostOrSubdomain(host, 'googleusercontent.com')) {
      return _optimizeYouTubeAvatar(url, neededHeight);
    }

    return url;
  }

  /// 優化 YouTube 視頻縮圖
  static String _optimizeYouTubeThumbnail(String url, int neededHeight) {
    final quality = _selectYouTubeQuality(neededHeight);
    return _buildYouTubeThumbnailUrl(url, quality);
  }

  /// 生成 YouTube 縮圖多級質量候選 URL（從高到低）
  ///
  /// 僅生成 16:9 質量檔位的候選（maxresdefault、mqdefault），排除 4:3 檔位
  /// （sddefault、hqdefault、default）：YouTube 會給 16:9 視頻的 4:3 檔位
  /// 加上下黑邊，排除它們可避免為 16:9 內容額外引入黑邊。原生 4:3 視頻的
  /// 16:9 檔位仍可能帶有 YouTube 預製黑邊，這屬於源端限制。
  /// 4:3 原始 URL 不會作為最終回退添加，以免優先顯示帶預製黑邊的版本。
  static List<String> _optimizeYouTubeThumbnailCandidates(
    String url,
    int neededHeight,
  ) {
    const qualityOrder = ['maxresdefault', 'mqdefault'];

    final pattern = RegExp(r'/vi(_webp)?/([^/]+)/([^/]+)\.(jpg|webp)');
    final match = pattern.firstMatch(url);
    if (match == null) return const [];

    final originalQuality = match.group(3);
    final desiredQuality = _selectYouTubeQuality(neededHeight);

    final desiredIdx = qualityOrder.indexOf(desiredQuality);
    final originalIdx = qualityOrder.indexOf(originalQuality ?? 'mqdefault');

    if (desiredIdx < 0) return const [];

    final candidates = <String>[];

    if (originalIdx < 0) {
      // 原始 URL 不是 16:9 檔位（如 hqdefault/sddefault）：
      // 從期望檔位向下生成所有 16:9 候選，原始 URL 不作為回退。
      for (int i = desiredIdx; i < qualityOrder.length; i++) {
        final candidate = _buildYouTubeThumbnailUrl(url, qualityOrder[i]);
        if (candidate.isNotEmpty) candidates.add(candidate);
      }
    } else if (originalIdx < desiredIdx) {
      // 原始質量高於期望：從期望檔位向下生成降級候選（跳過原始檔位）
      for (int i = desiredIdx; i < qualityOrder.length; i++) {
        if (i == originalIdx) continue;
        final candidate = _buildYouTubeThumbnailUrl(url, qualityOrder[i]);
        if (candidate.isNotEmpty) candidates.add(candidate);
      }
    } else {
      // 原始質量低於或等於期望：從期望檔位向下生成更高畫質候選，到原始檔位之前停止
      for (int i = desiredIdx; i < qualityOrder.length; i++) {
        if (i >= originalIdx) break;
        final candidate = _buildYouTubeThumbnailUrl(url, qualityOrder[i]);
        if (candidate.isNotEmpty) candidates.add(candidate);
      }
    }

    return candidates;
  }

  /// 用指定質量構建 YouTube 縮圖 URL
  ///
  /// 保留原始 URL 的格式 (WebP/JPG) 以確保可靠性。
  /// 少數影片（如 JqRggTDg5Bo）完全沒有 WebP 縮圖，
  /// 強制轉換會導致所有候選 URL 404，用戶看到長時間 loading spinner。
  static String _buildYouTubeThumbnailUrl(String url, String quality) {
    final pattern = RegExp(r'/vi(_webp)?/([^/]+)/([^/]+)\.(jpg|webp)');
    final match = pattern.firstMatch(url);
    if (match == null) return '';

    final isWebp = match.group(1) != null;
    final videoId = match.group(2);
    final ext = match.group(4);
    final prefix = isWebp ? 'vi_webp' : 'vi';
    return 'https://i.ytimg.com/$prefix/$videoId/$quality.$ext';
  }

  /// `mqdefault` 的來源高度（320×180）。
  static const int youtubeMqdefaultHeight = 180;

  /// `maxresdefault` 的來源高度（1280×720）。
  static const int youtubeMaxresdefaultHeight = 720;

  /// 選擇 YouTube 縮圖質量檔位
  ///
  /// YouTube 的檔位是固定的，只能挑「高度蓋得住 box」的那一檔；而可用的
  /// 只有 16:9 的兩檔：mqdefault (320×180) 和 maxresdefault (1280×720)。
  /// sddefault/hqdefault/default 是 4:3 格式，YouTube 對 16:9 視頻會在上下
  /// 添加黑邊填充，因此顯示候選直接排除 4:3 檔位 —— 也就是說 180px 和
  /// 720px 之間沒有中間檔可用。
  ///
  /// maxresdefault 在非 HD 視頻上可能不存在，此時會回退到 mqdefault。
  static String _selectYouTubeQuality(int neededHeight) {
    if (neededHeight <= youtubeMqdefaultHeight) return 'mqdefault';
    return 'maxresdefault';
  }

  /// 優化 YouTube 頻道頭像
  static String _optimizeYouTubeAvatar(String url, int neededHeight) {
    // 頻道頭像 URL 格式：
    // https://yt3.ggpht.com/xxx=s{size}-c-k-c0x00ffffff-no-rj
    // 或者：https://yt3.ggpht.com/xxx=s176-c-k-c0x00ffffff-no-rj

    // 選擇合適的尺寸
    final size = _selectAvatarSize(neededHeight);

    // 替換尺寸參數
    final sizePattern = RegExp(r'=s\d+');
    if (sizePattern.hasMatch(url)) {
      return url.replaceFirst(sizePattern, '=s$size');
    }

    // 如果沒有尺寸參數，嘗試添加
    if (_isHostOrSubdomain(_hostOf(url), 'ggpht.com') && !url.contains('=s')) {
      return '$url=s$size';
    }

    return url;
  }

  /// 選擇頭像尺寸
  ///
  /// 頭像是正方形，`=sN` 的 N 同時是寬和高，直接拿需要的高度比對。
  static int _selectAvatarSize(int neededHeight) {
    // 頭像常用尺寸：48, 88, 176, 240
    if (neededHeight <= 48) return 48;
    if (neededHeight <= 88) return 88;
    if (neededHeight <= 176) return 176;
    return 240;
  }

  /// 取得 OS 媒體中繼資料用的縮圖 URL（Windows SMTC / 系統通知）
  static String getOsMediaArtwork(String? url) {
    return getOptimizedUrl(
      url,
      displaySize: osMediaArtworkHeight,
      devicePixelRatio: 1,
    );
  }

  /// 檢查是否為網易雲圖片 URL
  static bool _isNeteaseUrl(String url) {
    return _isHostOrSubdomain(_hostOf(url), 'music.126.net');
  }

  /// 網易雲尺寸檔位（px）。`?param=NyN` 請求的是 N×N 的方形。
  static const List<int> neteaseSizeTiers = [100, 200, 400, 800];

  /// 選擇網易雲合適的尺寸檔位
  ///
  /// 網易雲的專輯封面是方形，`?param=NyN` 的 N 同時是寬和高，需要的高度
  /// 直接就是需要的檔位，不必乘 [wideSourceAspectRatio]。
  static int selectNeteaseSize(int neededHeight) {
    for (final tier in neteaseSizeTiers) {
      if (neededHeight <= tier) return tier;
    }
    return neteaseSizeTiers.last;
  }

  /// 生成網易雲縮圖多級尺寸候選 URL（從高到低）
  static List<String> _optimizeNeteaseUrlCandidates(
    String url,
    int neededHeight,
  ) {
    final baseUrl = url.split('?').first;
    final desiredSize = selectNeteaseSize(neededHeight);

    final candidates = <String>[];
    for (final size in neteaseSizeTiers.reversed) {
      if (size > desiredSize) continue;
      candidates.add('$baseUrl?param=${size}y$size');
    }
    return candidates;
  }

  static String? _hostOf(String url) => Uri.tryParse(url)?.host.toLowerCase();

  static bool _isHostOrSubdomain(String? host, String domain) {
    if (host == null || host.isEmpty) return false;
    return host == domain || host.endsWith('.$domain');
  }
}
