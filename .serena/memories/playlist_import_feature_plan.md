# 歌单导入功能设计文档

> 创建日期: 2026-02-10
> 状态: 规划中

## 1. 功能概述

允许用户从其他音乐平台（网易云音乐、QQ音乐、Spotify）导入歌单，通过搜索匹配在 Bilibili/YouTube 上找到对应歌曲，创建本地歌单。

### 1.1 用户流程

```
用户粘贴歌单链接 → 解析获取歌曲列表 → 搜索匹配 B站/YouTube → 用户确认/调整 → 创建本地歌单
```

### 1.2 支持的平台

| 平台 | 链接格式示例 | 认证要求 |
|------|-------------|---------|
| 网易云音乐 | `music.163.com/#/playlist?id=xxx` / `163cn.tv/xxx` | 无需 |
| QQ音乐 | `y.qq.com/n/ryqq/playlist/xxx` / `i.y.qq.com/xxx` | 无需 |
| Spotify | `open.spotify.com/playlist/xxx` | 需要 (Client Credentials) |

---

## 2. 技术方案

### 2.1 架构设计

```
lib/
├── data/
│   └── sources/
│       └── playlist_import/
│           ├── playlist_import_source.dart      # 抽象接口
│           ├── netease_playlist_source.dart     # 网易云实现
│           ├── qq_music_playlist_source.dart    # QQ音乐实现
│           ├── qq_music_sign.dart               # QQ音乐签名算法
│           └── spotify_playlist_source.dart     # Spotify实现
├── services/
│   └── playlist_import_service.dart             # 导入服务（协调搜索匹配）
├── providers/
│   └── playlist_import_provider.dart            # 状态管理
└── ui/
    └── pages/
        └── playlist_import/
            ├── playlist_import_page.dart        # 主页面
            ├── import_preview_page.dart         # 预览/确认页面
            └── widgets/
                ├── import_track_tile.dart       # 单曲匹配结果
                └── search_result_selector.dart  # 搜索结果选择器
```

### 2.2 数据模型

```dart
/// 导入的歌曲信息（来自外部平台）
class ImportedTrack {
  final String title;           // 歌曲标题
  final List<String> artists;   // 艺术家列表
  final String? album;          // 专辑名（可选）
  final Duration? duration;     // 时长（可选，用于匹配验证）
  
  String get searchQuery => '$title ${artists.join(" ")}';
}

/// 导入的歌单信息
class ImportedPlaylist {
  final String name;            // 歌单名称
  final String sourceUrl;       // 原始链接
  final PlaylistSource source;  // 来源平台
  final List<ImportedTrack> tracks;
  final int totalCount;         // 原始歌曲总数
}

/// 匹配结果
class MatchedTrack {
  final ImportedTrack original;           // 原始歌曲
  final List<Track> searchResults;        // 搜索结果列表
  final Track? selectedTrack;             // 用户选择的匹配
  final bool isIncluded;                  // 是否包含在最终歌单
  final MatchStatus status;               // 匹配状态
}

enum MatchStatus {
  pending,      // 等待搜索
  searching,    // 搜索中
  matched,      // 已匹配
  noResult,     // 无结果
  userSelected, // 用户手动选择
  excluded,     // 用户排除
}

enum PlaylistSource {
  netease,
  qqMusic,
  spotify,
}
```

### 2.3 抽象接口

```dart
/// 歌单导入源抽象接口
abstract class PlaylistImportSource {
  /// 支持的平台
  PlaylistSource get source;
  
  /// 检查链接是否匹配此平台
  bool canHandle(String url);
  
  /// 从链接解析歌单ID
  String? extractPlaylistId(String url);
  
  /// 获取歌单信息
  Future<ImportedPlaylist> fetchPlaylist(String url);
}
```

---

## 3. 各平台 API 实现细节

### 3.1 网易云音乐

**API 端点：**
```
歌单信息: POST https://music.163.com/api/v6/playlist/detail
歌曲详情: POST https://music.163.com/api/v3/song/detail
```

**请求格式：**
```dart
// 获取歌单基本信息
final response = await dio.post(
  'https://music.163.com/api/v6/playlist/detail',
  data: 'id=$playlistId',
  options: Options(
    contentType: 'application/x-www-form-urlencoded',
  ),
);

// 批量获取歌曲详情（每次最多400首）
final songIds = trackIds.map((id) => {'id': id}).toList();
final response = await dio.post(
  'https://music.163.com/api/v3/song/detail',
  data: 'c=${jsonEncode(songIds)}',
);
```

**响应结构：**
```json
{
  "code": 200,
  "playlist": {
    "name": "歌单名称",
    "trackCount": 100,
    "trackIds": [{"id": 123}, {"id": 456}]
  }
}
```

**链接格式支持：**
- 标准链接: `https://music.163.com/#/playlist?id=2829896389`
- 短链接: `http://163cn.tv/zoIxm3` (需要重定向获取真实ID)
- 分享链接: `https://y.music.163.com/m/playlist?id=xxx`

### 3.2 QQ音乐

**API 端点：**
```
https://u6.y.qq.com/cgi-bin/musics.fcg?sign={sign}&_={timestamp}
```

**签名算法（Dart 实现）：**
```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

class QQMusicSign {
  static const _l1 = [212, 45, 80, 68, 195, 163, 163, 203, 157, 220, 254, 91, 204, 79, 104, 6];
  static const _t = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
  static const _k1 = {
    '0': 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9,
    'A': 10, 'B': 11, 'C': 12, 'D': 13, 'E': 14, 'F': 15,
  };

  static String encrypt(String param) {
    // 1. 计算 MD5
    final md5Hash = md5.convert(utf8.encode(param));
    final md5Str = md5Hash.toString().toUpperCase();
    
    // 2. 提取特定位置字符
    final t1 = _selectChars(md5Str, [21, 4, 9, 26, 16, 20, 27, 30]);
    final t3 = _selectChars(md5Str, [18, 11, 3, 2, 1, 7, 6, 25]);
    
    // 3. XOR 运算
    final ls2 = <int>[];
    for (var i = 0; i < 16; i++) {
      final x1 = _k1[md5Str[i * 2]]!;
      final x2 = _k1[md5Str[i * 2 + 1]]!;
      final x3 = (x1 * 16 ^ x2) ^ _l1[i];
      ls2.add(x3);
    }
    
    // 4. Base64 变换
    final ls3 = <String>[];
    for (var i = 0; i < 6; i++) {
      if (i == 5) {
        ls3.add('${_t[ls2[ls2.length - 1] >> 2]}${_t[(ls2[ls2.length - 1] & 3) << 4]}');
      } else {
        final x4 = ls2[i * 3] >> 2;
        final x5 = (ls2[i * 3 + 1] >> 4) ^ ((ls2[i * 3] & 3) << 4);
        final x6 = (ls2[i * 3 + 2] >> 6) ^ ((ls2[i * 3 + 1] & 15) << 2);
        final x7 = 63 & ls2[i * 3 + 2];
        ls3.add('${_t[x4]}${_t[x5]}${_t[x6]}${_t[x7]}');
      }
    }
    
    final t2 = ls3.join('').replaceAll(RegExp(r'[\\/+]'), '');
    return 'zzb${(t1 + t2 + t3).toLowerCase()}';
  }
  
  static String _selectChars(String str, List<int> indices) {
    return indices.map((i) => str[i]).join('');
  }
}
```

**请求体结构：**
```dart
Map<String, dynamic> buildRequest(int playlistId, {int songBegin = 0, int songNum = 1000}) {
  return {
    'req_0': {
      'module': 'music.srfDissInfo.aiDissInfo',
      'method': 'uniform_get_Dissinfo',
      'param': {
        'disstid': playlistId,
        'enc_host_uin': '',
        'tag': 1,
        'userinfo': 1,
        'song_begin': songBegin,
        'song_num': songNum,
      },
    },
    'comm': {
      'g_tk': 5381,
      'uin': 0,
      'format': 'json',
      'platform': 'android',  // 可尝试: android, iphone, h5
    },
  };
}
```

**链接格式支持：**
- 新版链接: `https://y.qq.com/n/ryqq/playlist/8407701300`
- 旧版链接: `https://y.qq.com/n/yqq/playlist/xxx`
- 详情页: `https://i.y.qq.com/n2/m/share/details/taoge.html?id=xxx`
- 短链接: 需要重定向获取真实链接

### 3.3 Spotify

**方案选择：**

由于 Spotify 官方 API 需要认证，有两种方案：

**方案 A: 官方 API (Client Credentials Flow)**
- 需要用户在 Spotify Developer 注册应用
- 获取 client_id 和 client_secret
- 适合高级用户

**方案 B: 模拟浏览器请求 (参考 Spotifly)**
- 无需认证
- 可能不稳定
- 需要逆向 Spotify 网页端 API

**推荐方案 A 的实现：**
```dart
class SpotifyPlaylistSource implements PlaylistImportSource {
  final String? clientId;
  final String? clientSecret;
  String? _accessToken;
  
  Future<String> _getAccessToken() async {
    if (_accessToken != null) return _accessToken!;
    
    final credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));
    final response = await dio.post(
      'https://accounts.spotify.com/api/token',
      data: 'grant_type=client_credentials',
      options: Options(
        headers: {'Authorization': 'Basic $credentials'},
        contentType: 'application/x-www-form-urlencoded',
      ),
    );
    
    _accessToken = response.data['access_token'];
    return _accessToken!;
  }
  
  @override
  Future<ImportedPlaylist> fetchPlaylist(String url) async {
    final playlistId = extractPlaylistId(url);
    final token = await _getAccessToken();
    
    final response = await dio.get(
      'https://api.spotify.com/v1/playlists/$playlistId',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    
    // 解析响应...
  }
}
```

---

## 4. UI 设计

### 4.1 导入外部歌单弹窗

参考现有的 `ImportUrlDialog` 样式，使用 AlertDialog：

```dart
/// 外部歌单导入对话框
class ExternalPlaylistImportDialog extends ConsumerStatefulWidget {
  // 参考 lib/ui/pages/library/widgets/import_url_dialog.dart
}
```

**UI 结构：**
```
┌─────────────────────────────────────────────┐
│  导入外部歌单                                │
├─────────────────────────────────────────────┤
│                                             │
│  支持导入网易云音乐、QQ音乐、Spotify 歌单     │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │ 🔗  粘贴歌单链接...                  │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │ ✏️  歌单名称（可选）                  │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  搜索来源：                                  │
│  ┌──────────┐ ┌──────────┐                  │
│  │ Bilibili │ │ YouTube  │  (ChoiceChip)    │
│  └──────────┘ └──────────┘                  │
│                                             │
│  // 导入进度（导入中显示）                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  正在解析歌单...                             │
│                                             │
│           [ 取消 ]    [ 导入 ]               │
│                                             │
└─────────────────────────────────────────────┘
```

**关键代码参考：**
```dart
AlertDialog(
  title: const Text('导入外部歌单'),
  content: SizedBox(
    width: 400,
    child: Form(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '支持导入网易云音乐、QQ音乐、Spotify 歌单',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: '粘贴歌单链接',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '歌单名称（可选）',
              hintText: '留空则使用原名称',
              prefixIcon: Icon(Icons.edit),
            ),
          ),
          const SizedBox(height: 16),
          // 搜索来源选择
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: Text('Bilibili'), selected: ...),
              ChoiceChip(label: Text('YouTube'), selected: ...),
            ],
          ),
          // 进度显示（同 ImportUrlDialog）
          if (_isImporting) ...[
            const SizedBox(height: 24),
            LinearProgressIndicator(value: _progress.percentage),
            // ...
          ],
        ],
      ),
    ),
  ),
  actions: [
    TextButton(onPressed: ..., child: const Text('取消')),
    FilledButton(onPressed: ..., child: const Text('导入')),
  ],
)
```

### 4.2 匹配预览页面

导入成功后跳转到全屏预览页面，展示匹配结果。

**页面结构：**
```
┌─────────────────────────────────────────────────────────┐
│  ←  导入预览                           [ 创建歌单 ]     │
├─────────────────────────────────────────────────────────┤
│  歌单名称：我的收藏                                      │
│  来源：网易云音乐  •  共 100 首  •  已匹配 95 首         │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │  ⚠️ 未匹配 (5)                              ▼   │    │
│  ├─────────────────────────────────────────────────┤    │
│  │  • 某首找不到的歌 - 歌手A                        │    │
│  │  • 另一首找不到的歌 - 歌手B                      │    │
│  │  • ...                                          │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  已匹配 (95)                                            │
│  ┌─────────────────────────────────────────────────┐    │
│  │ ┌────┐                                          │    │
│  │ │ 🖼️ │ 晴天 - 周杰伦【高清MV】                   │    │
│  │ │    │ 周杰伦  ▶ 1.2万  🅱️            03:45    │    │
│  │ └────┘                                      ▼   │    │
│  │         ┌ 原曲：晴天 - 周杰伦 ─────────────────┐ │    │
│  │         └─────────────────────────────────────┘ │    │
│  └─────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────┐    │
│  │ ┌────┐                                          │    │
│  │ │ 🖼️ │ 七里香 完整版                            │    │
│  │ │    │ 周杰伦  ▶ 8.5千  🅱️            04:12    │    │
│  │ └────┘                                      ▼   │    │
│  └─────────────────────────────────────────────────┘    │
│  ...                                                    │
└─────────────────────────────────────────────────────────┘
```

### 4.3 匹配结果 Tile 组件

参考现有的 `_SearchResultTile` 样式（`lib/ui/pages/search/search_page.dart:920`）：

```dart
/// 匹配结果项 - 显示搜索到的歌曲，可展开选择其他结果
class ImportMatchTile extends ConsumerWidget {
  final MatchedTrack matchedTrack;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final void Function(Track) onSelectAlternative;
  final void Function(bool) onToggleInclude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = matchedTrack.selectedTrack;
    final original = matchedTrack.original;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Column(
      children: [
        // 主行：显示当前选中的搜索结果
        ListTile(
          leading: TrackThumbnail(
            track: track,
            size: 48,
            borderRadius: 4,
          ),
          title: Text(
            track.title,  // 搜索结果的标题在上面
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              // 艺术家
              Flexible(
                child: Text(
                  track.artist ?? '未知艺术家',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 播放数
              if (track.viewCount != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.play_arrow, size: 14, color: colorScheme.outline),
                const SizedBox(width: 2),
                Text(
                  _formatViewCount(track.viewCount!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
              // 音源标识
              const SizedBox(width: 8),
              _SourceBadge(sourceType: track.sourceType),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 时长
              if (track.durationMs != null)
                SizedBox(
                  width: 48,
                  child: Text(
                    DurationFormatter.formatMs(track.durationMs!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              // 展开按钮（有多个搜索结果时显示）
              if (matchedTrack.searchResults.length > 1)
                IconButton(
                  icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: onToggleExpand,
                ),
              // 包含/排除勾选框
              Checkbox(
                value: matchedTrack.isIncluded,
                onChanged: (v) => onToggleInclude(v ?? false),
              ),
            ],
          ),
        ),
        
        // 原曲信息提示（折叠状态下显示）
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '原曲：${original.title} - ${original.artists.join(" / ")}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        
        // 展开的其他搜索结果列表
        if (isExpanded)
          ...matchedTrack.searchResults.map((altTrack) => _AlternativeTrackTile(
            track: altTrack,
            isSelected: altTrack == matchedTrack.selectedTrack,
            onSelect: () => onSelectAlternative(altTrack),
          )),
      ],
    );
  }
}

/// 备选搜索结果项（展开时显示）
class _AlternativeTrackTile extends StatelessWidget {
  final Track track;
  final bool isSelected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: ListTile(
        leading: isSelected
            ? Icon(Icons.check_circle, color: colorScheme.primary)
            : Icon(Icons.radio_button_unchecked, color: colorScheme.outline),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isSelected ? colorScheme.primary : null,
          ),
        ),
        subtitle: Row(
          children: [
            Text(track.artist ?? ''),
            if (track.viewCount != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.play_arrow, size: 14, color: colorScheme.outline),
              Text(_formatViewCount(track.viewCount!)),
            ],
          ],
        ),
        trailing: track.durationMs != null
            ? Text(DurationFormatter.formatMs(track.durationMs!))
            : null,
        onTap: onSelect,
      ),
    );
  }
}
```

### 4.4 未匹配歌曲区域

未匹配的歌曲显示在列表最上方，使用可折叠的 ExpansionTile：

```dart
/// 未匹配歌曲列表
class UnmatchedTracksSection extends StatelessWidget {
  final List<ImportedTrack> unmatchedTracks;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    if (unmatchedTracks.isEmpty) return const SizedBox.shrink();
    
    return Card(
      color: colorScheme.errorContainer.withOpacity(0.3),
      child: ExpansionTile(
        leading: Icon(Icons.warning_amber, color: colorScheme.error),
        title: Text(
          '未匹配 (${unmatchedTracks.length})',
          style: TextStyle(color: colorScheme.error),
        ),
        initiallyExpanded: true,
        children: unmatchedTracks.map((track) => ListTile(
          dense: true,
          leading: Icon(Icons.music_off, size: 20, color: colorScheme.outline),
          title: Text(
            '${track.title} - ${track.artists.join(" / ")}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.search, size: 20),
            tooltip: '手动搜索',
            onPressed: () => _openManualSearch(context, track),
          ),
        )).toList(),
      ),
    );
  }
}
```

### 4.5 交互设计总结

1. **导入流程**：
   - 用户粘贴链接 → 点击导入 → 显示进度 → 跳转预览页

2. **预览页布局**：
   - 顶部：歌单信息 + 统计
   - 未匹配区域（最上方，可折叠，默认展开）
   - 已匹配列表（主体）

3. **匹配项交互**：
   - 默认显示搜索结果（封面、标题、作者、播放数、时长）
   - 下方小字显示原曲信息
   - 点击展开箭头显示其他搜索结果
   - 点击备选项切换选中
   - 勾选框控制是否包含在最终歌单

4. **未匹配项交互**：
   - 显示原曲信息
   - 提供"手动搜索"按钮，打开搜索页面

---

## 5. 实现计划

### Phase 1: 基础架构 (优先级: 高)
- [ ] 创建 `PlaylistImportSource` 抽象接口
- [ ] 实现 `ImportedTrack`, `ImportedPlaylist`, `MatchedTrack` 数据模型
- [ ] 创建 `PlaylistImportService` 服务类

### Phase 2: 网易云音乐支持 (优先级: 高)
- [ ] 实现 `NeteasePlaylistSource`
- [ ] 链接解析（标准链接、短链接）
- [ ] API 调用和响应解析
- [ ] 单元测试

### Phase 3: QQ音乐支持 (优先级: 高)
- [ ] 移植签名算法到 Dart (`QQMusicSign`)
- [ ] 实现 `QQMusicPlaylistSource`
- [ ] 链接解析（多种格式）
- [ ] 分页获取大歌单
- [ ] 单元测试

### Phase 4: 搜索匹配服务 (优先级: 高)
- [ ] 实现 `PlaylistImportService.matchTracks()`
- [ ] 集成现有的 `BilibiliSource` 和 `YouTubeSource` 搜索
- [ ] 匹配算法优化（标题相似度、时长匹配）
- [ ] 并发搜索控制（避免请求过快）

### Phase 5: UI 实现 (优先级: 中)
- [ ] 创建 `PlaylistImportPage` 主页面
- [ ] 创建 `ImportPreviewPage` 预览页面
- [ ] 实现 `playlist_import_provider.dart` 状态管理
- [ ] 进度显示和错误处理

### Phase 6: Spotify 支持 (优先级: 低)
- [ ] 实现 `SpotifyPlaylistSource`
- [ ] 设置页面添加 Spotify API 配置
- [ ] OAuth 认证流程

### Phase 7: 优化和测试 (优先级: 中)
- [ ] 缓存已匹配的结果
- [ ] 离线支持（保存导入历史）
- [ ] 性能优化
- [ ] 完整测试覆盖

---

## 6. 风险和注意事项

### 6.1 API 稳定性
- 网易云和 QQ 音乐的 API 是非官方的，可能随时变化
- 建议添加版本检测和错误上报机制
- 保持关注 GoMusic 项目的更新

### 6.2 请求频率限制
- 搜索匹配时需要控制并发数量
- 建议添加请求间隔（如 200-500ms）
- 大歌单分批处理

### 6.3 匹配准确性
- 歌曲标题可能有差异（如括号内容、版本标注）
- 建议实现模糊匹配算法
- 允许用户手动调整

### 6.4 法律合规
- 仅获取公开歌单信息
- 不存储或传输原始音频
- 遵守各平台的使用条款

---

## 7. 参考资源

- GoMusic 项目: https://github.com/Bistutu/GoMusic
- 歌单无界: https://github.com/Winnie0408/LocalMusicHelper
- Spotifly: https://github.com/tr1ckydev/spotifly
- SpotAPI: https://github.com/Aran404/SpotAPI
