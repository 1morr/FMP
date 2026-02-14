import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/logger.dart';
import '../../../i18n/strings.g.dart';
import '../../../core/constants/ui_constants.dart';

/// 实时日志查看页面
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<LogEntry>? _logSubscription;
  List<LogEntry> _logs = [];
  bool _autoScroll = true;
  LogLevel _filterLevel = LogLevel.debug;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _logs = List.from(AppLogger.logs);
    _logSubscription = AppLogger.logStream.listen((entry) {
      setState(() {
        _logs.add(entry);
        // 限制显示数量
        if (_logs.length > 1000) {
          _logs.removeAt(0);
        }
      });
      if (_autoScroll) {
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AnimationDurations.fastest,
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<LogEntry> get _filteredLogs {
    return _logs.where((log) {
      // 级别过滤
      if (log.level.index < _filterLevel.index) return false;
      // 搜索过滤
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return log.message.toLowerCase().contains(query) ||
            (log.tag?.toLowerCase().contains(query) ?? false);
      }
      return true;
    }).toList();
  }

  Color _getLogColor(LogLevel level, ColorScheme colorScheme) {
    return switch (level) {
      LogLevel.debug => colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      LogLevel.info => colorScheme.primary,
      LogLevel.warning => Colors.orange,
      LogLevel.error => colorScheme.error,
    };
  }

  void _copyAllLogs() {
    final text = _filteredLogs.map((e) => e.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.logViewer.logsCopied)),
    );
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
      AppLogger.clearLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredLogs = _filteredLogs;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.logViewer.titleWithCount(count: filteredLogs.length.toString())),
        actions: [
          // 自动滚动开关
          IconButton(
            icon: Icon(_autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center),
            tooltip: _autoScroll ? t.logViewer.autoScrollOn : t.logViewer.autoScrollOff,
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          // 复制日志
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: t.logViewer.copyAll,
            onPressed: filteredLogs.isEmpty ? null : _copyAllLogs,
          ),
          // 清空日志
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: t.logViewer.clear,
            onPressed: _logs.isEmpty ? null : _clearLogs,
          ),
          // 更多选项
          PopupMenuButton<LogLevel>(
            icon: const Icon(Icons.filter_list),
            tooltip: t.logViewer.filterLevel,
            initialValue: _filterLevel,
            onSelected: (level) => setState(() => _filterLevel = level),
            itemBuilder: (context) => [
              PopupMenuItem(value: LogLevel.debug, child: Text(t.logViewer.allDebug)),
              const PopupMenuItem(value: LogLevel.info, child: Text('Info+')),
              const PopupMenuItem(value: LogLevel.warning, child: Text('Warning+')),
              PopupMenuItem(value: LogLevel.error, child: Text(t.logViewer.onlyError)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: t.logViewer.searchHint,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: AppRadius.borderRadiusMd,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          // 日志列表
          Expanded(
            child: filteredLogs.isEmpty
                ? Center(
                    child: Text(
                      _logs.isEmpty ? t.logViewer.noLogs : t.logViewer.noMatchingLogs,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: filteredLogs.length,
                    itemBuilder: (context, index) {
                      final log = filteredLogs[index];
                      return _LogEntryTile(
                        entry: log,
                        color: _getLogColor(log.level, colorScheme),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;
  final Color color;

  const _LogEntryTile({
    required this.entry,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasError = entry.error != null || entry.stackTrace != null;

    return InkWell(
      onTap: hasError
          ? () => _showDetailDialog(context)
          : null,
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: entry.toString()));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.logViewer.copied),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间和级别
            SizedBox(
              width: 100,
              child: Text(
                '${entry.formattedTime} ${entry.levelPrefix}',
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: color,
                ),
              ),
            ),
            // Tag（如果有）
            if (entry.tag != null)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                child: Text(
                  entry.tag!,
                  style: textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: color,
                    fontSize: 10,
                  ),
                ),
              ),
            // 消息
            Expanded(
              child: Text(
                entry.message,
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // 错误指示器
            if (hasError)
              Icon(Icons.error_outline, size: 14, color: color),
          ],
        ),
      ),
    );
  }

  void _showDetailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.logViewer.logDetail),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${t.logViewer.time}: ${entry.formattedTime}'),
              Text('${t.logViewer.level}: ${entry.level.name}'),
              if (entry.tag != null) Text('${t.logViewer.tag}: ${entry.tag}'),
              const SizedBox(height: 8),
              Text('${t.logViewer.message}:', style: const TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(entry.message),
              if (entry.error != null) ...[
                const SizedBox(height: 8),
                Text('${t.logViewer.error}:', style: const TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(entry.error.toString()),
              ],
              if (entry.stackTrace != null) ...[
                const SizedBox(height: 8),
                Text('${t.logViewer.stackTrace}:', style: const TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(
                  entry.stackTrace.toString(),
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final text = StringBuffer()
                ..writeln('${t.logViewer.time}: ${entry.formattedTime}')
                ..writeln('${t.logViewer.level}: ${entry.level.name}')
                ..writeln('${t.logViewer.tag}: ${entry.tag ?? t.logViewer.none}')
                ..writeln('${t.logViewer.message}: ${entry.message}');
              if (entry.error != null) {
                text.writeln('${t.logViewer.error}: ${entry.error}');
              }
              if (entry.stackTrace != null) {
                text.writeln('${t.logViewer.stackTrace}:\n${entry.stackTrace}');
              }
              Clipboard.setData(ClipboardData(text: text.toString()));
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.logViewer.copiedToClipboard)),
              );
            },
            child: Text(t.logViewer.copy),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.general.close),
          ),
        ],
      ),
    );
  }
}
