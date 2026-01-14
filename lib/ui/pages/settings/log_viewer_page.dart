import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/logger.dart';

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
          duration: const Duration(milliseconds: 100),
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
      const SnackBar(content: Text('日志已复制到剪贴板')),
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
        title: Text('实时日志 (${filteredLogs.length})'),
        actions: [
          // 自动滚动开关
          IconButton(
            icon: Icon(_autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center),
            tooltip: _autoScroll ? '自动滚动: 开' : '自动滚动: 关',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          // 复制日志
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制全部',
            onPressed: filteredLogs.isEmpty ? null : _copyAllLogs,
          ),
          // 清空日志
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空',
            onPressed: _logs.isEmpty ? null : _clearLogs,
          ),
          // 更多选项
          PopupMenuButton<LogLevel>(
            icon: const Icon(Icons.filter_list),
            tooltip: '过滤级别',
            initialValue: _filterLevel,
            onSelected: (level) => setState(() => _filterLevel = level),
            itemBuilder: (context) => [
              const PopupMenuItem(value: LogLevel.debug, child: Text('全部 (Debug+)')),
              const PopupMenuItem(value: LogLevel.info, child: Text('Info+')),
              const PopupMenuItem(value: LogLevel.warning, child: Text('Warning+')),
              const PopupMenuItem(value: LogLevel.error, child: Text('仅 Error')),
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
                hintText: '搜索日志...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
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
                      _logs.isEmpty ? '暂无日志' : '没有匹配的日志',
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
          const SnackBar(
            content: Text('已复制'),
            duration: Duration(seconds: 1),
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
                  borderRadius: BorderRadius.circular(4),
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
        title: const Text('日志详情'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('时间: ${entry.formattedTime}'),
              Text('级别: ${entry.level.name}'),
              if (entry.tag != null) Text('标签: ${entry.tag}'),
              const SizedBox(height: 8),
              const Text('消息:', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(entry.message),
              if (entry.error != null) ...[
                const SizedBox(height: 8),
                const Text('错误:', style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(entry.error.toString()),
              ],
              if (entry.stackTrace != null) ...[
                const SizedBox(height: 8),
                const Text('堆栈:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                ..writeln('时间: ${entry.formattedTime}')
                ..writeln('级别: ${entry.level.name}')
                ..writeln('标签: ${entry.tag ?? "无"}')
                ..writeln('消息: ${entry.message}');
              if (entry.error != null) {
                text.writeln('错误: ${entry.error}');
              }
              if (entry.stackTrace != null) {
                text.writeln('堆栈:\n${entry.stackTrace}');
              }
              Clipboard.setData(ClipboardData(text: text.toString()));
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板')),
              );
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
