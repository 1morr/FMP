# 同步功能严重 Bug 修复

## 问题描述

用户报告：在已下载页面点击同步按钮后，已有下载的歌曲的 `playlistInfo` 会变成 `playlistId=0`，`allPlaylistIds` 变成 `[0]`。导致在下次打开程序时会被认为是孤儿 Track 被清理。

## 问题根源

`DownloadPathSyncService.syncLocalFiles()` 的逻辑错误：

```dart
// 错误的逻辑（第 130-138 行）
existingTrack.playlistInfo = [
  PlaylistDownloadInfo()
    ..playlistId = 0
    ..playlistName = folderName
    ..downloadPath = localPath,
];
```

这会**替换所有 `playlistInfo`**，导致：
1. 原本属于某个歌单的歌曲被标记为 `playlistId = 0`（未分类）
2. `allPlaylistIds` 变成 `[0]`
3. 下次启动时，这些歌曲会被认为是孤儿 Track 被清理

## 修复方案

**保留原有的歌单关联，只更新下载路径**：

```dart
// 正确的逻辑
if (existingTrack.playlistInfo.isNotEmpty) {
  // 更新所有歌单关联的下载路径
  for (final info in existingTrack.playlistInfo) {
    info.downloadPath = localPath;
  }
} else {
  // 如果没有歌单关联，添加为未分类（playlistId = 0）
  final folderName = folder.path.split(RegExp(r'[/\\]')).last;
  existingTrack.playlistInfo = [
    PlaylistDownloadInfo()
      ..playlistId = 0
      ..playlistName = folderName
      ..downloadPath = localPath,
  ];
}
```

## 修复后的行为

1. **已有歌单关联的 Track**：保留原有的 `playlistId`，只更新 `downloadPath`
2. **没有歌单关联的 Track**：添加为未分类（`playlistId = 0`）

## 影响范围

- **修复文件**：`lib/services/download/download_path_sync_service.dart`
- **影响功能**：已下载页面的"同步本地文件"按钮
- **严重程度**：P0（会导致数据丢失）

## 验证步骤

1. 下载一些歌曲到某个歌单
2. 点击"同步本地文件"按钮
3. 检查 Track 的 `playlistInfo`，应该保留原有的 `playlistId`
4. 重启应用，歌曲不应该被清理

## 相关问题

这个 bug 是在 2026-02 的下载系统重构中引入的，当时的设计文档中提到：

> C3: 同步时 REPLACE 所有 DB 路径（本地文件是权威来源）

但这个设计是错误的，应该是"更新下载路径，保留歌单关联"。
