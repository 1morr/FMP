import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:async';

import '../../../i18n/strings.g.dart';

/// YouTube 音频流测试页面
/// 用于测试不同类型的 YouTube 流在 Windows 和 Android 上的播放情况
class YouTubeStreamTestPage extends StatefulWidget {
  const YouTubeStreamTestPage({super.key});

  @override
  State<YouTubeStreamTestPage> createState() => _YouTubeStreamTestPageState();
}

/// 可用的 YouTube API 客户端类型
final Map<String, List<yt.YoutubeApiClient>> _clientCombinations = {
  'ios+safari+android': [yt.YoutubeApiClient.ios, yt.YoutubeApiClient.safari, yt.YoutubeApiClient.android],
  'tv+safari': [yt.YoutubeApiClient.tv, yt.YoutubeApiClient.safari],
  'tv only': [yt.YoutubeApiClient.tv],
  'safari only': [yt.YoutubeApiClient.safari],
  'ios only': [yt.YoutubeApiClient.ios],
  'mediaConnect': [yt.YoutubeApiClient.mediaConnect],
  'mweb': [yt.YoutubeApiClient.mweb],
  'androidVr': [yt.YoutubeApiClient.androidVr],
};

/// 不同客户端对应的 headers
const Map<String, Map<String, String>> _clientHeaders = {
  'none': {},
  'browser': {
    'Origin': 'https://www.youtube.com',
    'Referer': 'https://www.youtube.com/',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  },
  'android': {
    'User-Agent': 'com.google.android.youtube/19.09.37 (Linux; U; Android 14) gzip',
  },
  'ios': {
    'User-Agent': 'com.google.ios.youtube/19.09.3 (iPhone; CPU iPhone OS 17_2 like Mac OS X)',
  },
};

class _YouTubeStreamTestPageState extends State<YouTubeStreamTestPage> {
  final _videoIdController = TextEditingController(text: 'dQw4w9WgXcQ');
  final _youtube = yt.YoutubeExplode();
  late final Player _player;
  final List<String> _logs = [];
  final _scrollController = ScrollController();

  bool _isLoading = false;
  String _status = t.debug.waitingForTest;
  List<StreamInfo> _availableStreams = [];
  StreamInfo? _currentStream;
  String _selectedHeaderType = 'none';
  String _selectedApiClient = 'ios+safari+android';
  
  // 播放状态
  bool _isPlaying = false;
  // ignore: unused_field
  bool _isBuffering = false;
  // ignore: unused_field
  bool _isCompleted = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;
  
  // 订阅
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _player = Player();
    _setupPlayerListeners();
  }

  void _setupPlayerListeners() {
    _subscriptions.add(_player.stream.playing.listen((playing) {
      _log('事件 playing=$playing');
      if (mounted) setState(() => _isPlaying = playing);
    }));
    
    _subscriptions.add(_player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    }));
    
    _subscriptions.add(_player.stream.duration.listen((dur) {
      _log('事件 duration=$dur');
      if (mounted) setState(() => _duration = dur);
    }));
    
    _subscriptions.add(_player.stream.buffering.listen((buffering) {
      _log('事件 buffering=$buffering');
      if (mounted) setState(() => _isBuffering = buffering);
    }));
    
    _subscriptions.add(_player.stream.completed.listen((completed) {
      _log('事件 completed=$completed');
      if (mounted) setState(() => _isCompleted = completed);
    }));
    
    _subscriptions.add(_player.stream.error.listen((error) {
      _log('❌ 错误: $error');
      if (mounted) setState(() => _error = error);
    }));
    
    _subscriptions.add(_player.stream.audioParams.listen((params) {
      _log('音频参数: format=${params.format}, sampleRate=${params.sampleRate}, channels=${params.channels}');
    }));
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _player.dispose();
    _youtube.close();
    _videoIdController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 从 URL 的查询参数中检测客户端类型
  String _detectClientFromUrl(String url) {
    final uri = Uri.parse(url);
    final c = uri.queryParameters['c'] ?? '';
    return c.isNotEmpty ? c : 'unknown';
  }

  Future<void> _fetchStreams() async {
    setState(() {
      _isLoading = true;
      _status = '正在获取流信息...';
      _availableStreams.clear();
      _logs.clear();
    });

    try {
      final videoId = _videoIdController.text.trim();
      _log('获取视频: $videoId');
      
      final video = await _youtube.videos.get(videoId);
      _log('标题: ${video.title}');
      _log('时长: ${video.duration}');

      _log('获取流清单... (API客户端: $_selectedApiClient)');
      final ytClients = _clientCombinations[_selectedApiClient] ?? [yt.YoutubeApiClient.ios];
      final manifest = await _youtube.videos.streams.getManifest(
        videoId,
        ytClients: ytClients,
      );

      final streams = <StreamInfo>[];

      // Audio-only 流
      _log('=== Audio-only (${manifest.audioOnly.length}) ===');
      for (final audio in manifest.audioOnly) {
        final client = _detectClientFromUrl(audio.url.toString());
        _log('  ${audio.audioCodec} | ${audio.container.name} | ${audio.bitrate} | client=$client');
        streams.add(StreamInfo(
          type: StreamType.audioOnly,
          url: audio.url.toString(),
          codec: audio.audioCodec,
          bitrate: audio.bitrate.bitsPerSecond,
          container: audio.container.name,
          client: client,
          label: '[$client] ${audio.audioCodec} ${audio.container.name} (${_formatBitrate(audio.bitrate.bitsPerSecond)})',
          rawInfo: 'codec=${audio.audioCodec}, container=${audio.container.name}, '
              'bitrate=${audio.bitrate}, size=${audio.size}, client=$client',
        ));
      }

      // Muxed 流
      _log('=== Muxed (${manifest.muxed.length}) ===');
      for (final muxed in manifest.muxed) {
        final client = _detectClientFromUrl(muxed.url.toString());
        _log('  ${muxed.qualityLabel} | ${muxed.container.name} | ${muxed.bitrate} | client=$client');
        streams.add(StreamInfo(
          type: StreamType.muxed,
          url: muxed.url.toString(),
          codec: '${muxed.videoCodec}+${muxed.audioCodec}',
          bitrate: muxed.bitrate.bitsPerSecond,
          container: muxed.container.name,
          client: client,
          label: '[$client] Muxed ${muxed.qualityLabel} ${muxed.container.name} (${_formatBitrate(muxed.bitrate.bitsPerSecond)})',
          rawInfo: 'quality=${muxed.qualityLabel}, vCodec=${muxed.videoCodec}, '
              'aCodec=${muxed.audioCodec}, client=$client',
        ));
      }

      // HLS 流
      _log('=== HLS (${manifest.hls.length}) ===');
      for (final hls in manifest.hls) {
        final client = _detectClientFromUrl(hls.url.toString());
        _log('  ${hls.qualityLabel} | ${hls.bitrate} | client=$client');
        streams.add(StreamInfo(
          type: StreamType.hls,
          url: hls.url.toString(),
          codec: 'HLS',
          bitrate: hls.bitrate.bitsPerSecond,
          container: 'm3u8',
          client: client,
          label: '[$client] HLS ${hls.qualityLabel} (${_formatBitrate(hls.bitrate.bitsPerSecond)})',
          rawInfo: 'quality=${hls.qualityLabel}, client=$client',
        ));
      }

      setState(() {
        _availableStreams = streams;
        _status = '找到 ${streams.length} 个流:\n'
            '- Audio-only: ${manifest.audioOnly.length}\n'
            '- Muxed: ${manifest.muxed.length}\n'
            '- HLS: ${manifest.hls.length}';
      });
    } catch (e) {
      _log('❌ 错误: $e');
      setState(() => _status = '获取流失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _playStream(StreamInfo stream) async {
    setState(() {
      _isLoading = true;
      _currentStream = stream;
      _error = null;
      _isCompleted = false;
    });

    final headers = _clientHeaders[_selectedHeaderType] ?? {};

    _log('');
    _log('========================================');
    _log('播放: ${stream.label}');
    _log('平台: ${Platform.operatingSystem}');
    _log('Headers模式: $_selectedHeaderType');
    _log('流client: ${stream.client}');
    if (headers.isNotEmpty) {
      _log('发送Headers: ${headers.keys.join(", ")}');
    } else {
      _log('不发送任何Headers');
    }
    _log('========================================');

    try {
      await _player.stop();
      await Future.delayed(const Duration(milliseconds: 200));
      
      final media = headers.isNotEmpty
          ? Media(stream.url, httpHeaders: headers)
          : Media(stream.url);
      
      _log('player.open()...');
      await _player.open(media);
      _log('player.open() 完成');

      // 等待并检查状态
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        
        if (_error != null) {
          throw Exception(_error);
        }
        if (_isPlaying && _duration.inMilliseconds > 0) {
          break;
        }
      }

      // 最终状态
      _log('最终: playing=$_isPlaying, duration=${_duration.inMilliseconds}ms, error=$_error');
      
      if (_isPlaying && _duration.inMilliseconds > 0) {
        setState(() {
          _status = '✅ 播放成功!\n'
              '类型: ${stream.type.name} | Headers: $_selectedHeaderType\n'
              '编解码器: ${stream.codec} | 容器: ${stream.container}\n'
              '比特率: ${_formatBitrate(stream.bitrate)}\n'
              '时长: ${_formatDuration(_duration)}';
        });
        _log('✅ 成功!');
      } else if (_error != null) {
        setState(() {
          _status = '❌ 失败! Headers=$_selectedHeaderType\n'
              '类型: ${stream.type.name}\n'
              '错误: $_error';
        });
      } else {
        setState(() {
          _status = '⚠️ 不确定\n'
              'playing=$_isPlaying, duration=$_duration';
        });
      }
    } catch (e) {
      _log('❌ 异常: $e');
      setState(() {
        _status = '❌ 失败! Headers=$_selectedHeaderType\n'
            '类型: ${stream.type.name} | 编解码器: ${stream.codec}\n'
            '错误: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// HTTP 级别验证 URL 是否可访问
  Future<Map<String, dynamic>> _verifyUrlAccess(String url, Map<String, String> headers) async {
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 10);
    dio.options.validateStatus = (status) => true; // 接受所有状态码
    
    try {
      // 先尝试 HEAD 请求
      final headResponse = await dio.head(
        url,
        options: Options(headers: headers),
      );
      
      final result = <String, dynamic>{
        'method': 'HEAD',
        'statusCode': headResponse.statusCode,
        'contentType': headResponse.headers.value('content-type'),
        'contentLength': headResponse.headers.value('content-length'),
        'accessible': headResponse.statusCode == 200,
      };
      
      // 如果 HEAD 成功，再尝试获取一小部分数据验证
      if (headResponse.statusCode == 200) {
        try {
          final rangeResponse = await dio.get(
            url,
            options: Options(
              headers: {...headers, 'Range': 'bytes=0-1023'},
              responseType: ResponseType.bytes,
            ),
          );
          result['rangeStatus'] = rangeResponse.statusCode;
          result['bytesReceived'] = (rangeResponse.data as List<int>?)?.length ?? 0;
        } catch (e) {
          result['rangeError'] = e.toString();
        }
      }
      
      return result;
    } catch (e) {
      return {
        'method': 'HEAD',
        'error': e.toString(),
        'accessible': false,
      };
    } finally {
      dio.close();
    }
  }

  /// 验证单个流的 URL 可访问性
  Future<void> _verifyStream(StreamInfo stream) async {
    _log('');
    _log('========================================');
    _log('验证 URL 可访问性: ${stream.label}');
    _log('========================================');
    
    for (final headerType in _clientHeaders.keys) {
      final headers = _clientHeaders[headerType] ?? {};
      final result = await _verifyUrlAccess(stream.url, headers);
      
      final status = result['accessible'] == true ? '✅' : '❌';
      _log('Headers=$headerType: $status');
      _log('  HTTP ${result['statusCode']} | ${result['contentType']}');
      if (result['contentLength'] != null) {
        _log('  Content-Length: ${result['contentLength']}');
      }
      if (result['bytesReceived'] != null) {
        _log('  Range请求收到: ${result['bytesReceived']} bytes');
      }
      if (result['error'] != null) {
        _log('  错误: ${result['error']}');
      }
      if (result['rangeError'] != null) {
        _log('  Range错误: ${result['rangeError']}');
      }
    }
    
    setState(() {
      _status = 'URL验证完成，请查看日志';
    });
  }

  /// 自动批量测试：对第一个 audio-only 流依次尝试所有 header 类型
  Future<void> _runAutoTest() async {
    final audioStreams = _availableStreams.where((s) => s.type == StreamType.audioOnly).toList();
    if (audioStreams.isEmpty) {
      _log('没有 audio-only 流可测试');
      return;
    }

    // 选一个 mp4a 流和一个 opus 流
    final testStreams = <StreamInfo>[];
    final mp4a = audioStreams.where((s) => s.codec.startsWith('mp4a')).toList();
    final opus = audioStreams.where((s) => s.codec == 'opus').toList();
    if (mp4a.isNotEmpty) testStreams.add(mp4a.first);
    if (opus.isNotEmpty) testStreams.add(opus.first);

    _log('');
    _log('╔══════════════════════════════════╗');
    _log('║      自动批量测试开始             ║');
    _log('╚══════════════════════════════════╝');

    final results = <String>[];
    final httpResults = <String, String>{}; // URL -> HTTP验证结果

    for (final stream in testStreams) {
      // 先进行 HTTP 验证
      _log('');
      _log('--- HTTP 验证: ${stream.codec}/${stream.container} ---');
      final httpVerify = await _verifyUrlAccess(stream.url, {});
      final httpOk = httpVerify['accessible'] == true;
      final httpStatus = httpOk 
          ? '✅ HTTP ${httpVerify['statusCode']}, ${httpVerify['bytesReceived'] ?? 0} bytes'
          : '❌ HTTP ${httpVerify['statusCode'] ?? httpVerify['error']}';
      httpResults['${stream.codec}/${stream.container}'] = httpStatus;
      _log('HTTP无Headers: $httpStatus');
      _log('Content-Type: ${httpVerify['contentType']}');

      for (final headerType in _clientHeaders.keys) {
        _log('');
        _log('--- 测试: ${stream.codec}/${stream.container} + headers=$headerType ---');
        
        setState(() {
          _selectedHeaderType = headerType;
          _error = null;
          _isCompleted = false;
        });

        final headers = _clientHeaders[headerType] ?? {};

        try {
          await _player.stop();
          await Future.delayed(const Duration(milliseconds: 300));

          final media = headers.isNotEmpty
              ? Media(stream.url, httpHeaders: headers)
              : Media(stream.url);

          setState(() => _error = null);
          await _player.open(media);

          // 等待结果
          bool success = false;
          for (int i = 0; i < 30; i++) {
            await Future.delayed(const Duration(milliseconds: 100));
            if (_error != null) break;
            if (_isPlaying && _duration.inMilliseconds > 0) {
              success = true;
              break;
            }
          }

          final result = success ? '✅' : '❌ ${_error ?? "timeout"}';
          results.add('${stream.codec}/${stream.container} [${stream.client}] + $headerType = $result');
          _log(results.last);
          
          await _player.stop();
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          results.add('${stream.codec}/${stream.container} [${stream.client}] + $headerType = ❌ $e');
          _log(results.last);
        }
      }
    }

    _log('');
    _log('╔══════════════════════════════════╗');
    _log('║          测试结果汇总             ║');
    _log('╚══════════════════════════════════╝');

    _log('');
    _log('=== HTTP 可访问性 ===');
    for (final entry in httpResults.entries) {
      _log('${entry.key}: ${entry.value}');
    }

    _log('');
    _log('=== media_kit 播放测试 ===');
    for (final r in results) {
      _log(r);
    }

    _log('');
    _log('=== 结论 ===');
    final allHttpOk = httpResults.values.every((v) => v.contains('✅'));
    final allPlayFailed = results.every((r) => r.contains('❌'));
    if (allHttpOk && allPlayFailed) {
      _log('⚠️ URL 可通过 HTTP 访问，但 media_kit 无法播放');
      _log('   可能是 libmpv 解码器/demuxer 问题');
    } else if (!allHttpOk) {
      _log('⚠️ URL 在 HTTP 级别就无法访问');
      _log('   可能是 YouTube CDN 限制或 URL 过期');
    }

    setState(() {
      _status = '批量测试完成:\n${results.join('\n')}';
    });
  }

  /// 扫描所有 API 客户端，检查哪些能产生可访问的 audio-only 流
  Future<void> _scanAllClients() async {
    final videoId = _videoIdController.text.trim();
    if (videoId.isEmpty) {
      _log('请输入 Video ID');
      return;
    }

    setState(() => _isLoading = true);

    _log('');
    _log('╔══════════════════════════════════════════════╗');
    _log('║   扫描所有 API 客户端的 Audio-Only 可访问性    ║');
    _log('╚══════════════════════════════════════════════╝');
    _log('Video ID: $videoId');

    final clientResults = <String, String>{};

    for (final entry in _clientCombinations.entries) {
      final clientName = entry.key;
      final clients = entry.value;

      _log('');
      _log('--- 测试客户端: $clientName ---');

      try {
        final manifest = await _youtube.videos.streams.getManifest(
          videoId,
          ytClients: clients,
        );

        if (manifest.audioOnly.isEmpty) {
          _log('  无 audio-only 流');
          clientResults[clientName] = '❌ 无 audio-only 流';
          continue;
        }

        // 测试第一个 audio-only 流
        final stream = manifest.audioOnly.first;
        final urlClient = _detectClientFromUrl(stream.url.toString());
        _log('  找到 ${manifest.audioOnly.length} 个 audio-only 流');
        _log('  测试: ${stream.audioCodec}/${stream.container.name} [c=$urlClient]');

        // HTTP 验证
        final httpResult = await _verifyUrlAccess(stream.url.toString(), {});
        final httpOk = httpResult['accessible'] == true;

        if (httpOk) {
          _log('  ✅ HTTP 可访问! Content-Type: ${httpResult['contentType']}');
          clientResults[clientName] = '✅ HTTP OK (c=$urlClient)';
        } else {
          _log('  ❌ HTTP ${httpResult['statusCode'] ?? httpResult['error']}');
          clientResults[clientName] = '❌ HTTP ${httpResult['statusCode'] ?? 'error'} (c=$urlClient)';
        }
      } catch (e) {
        _log('  ❌ 异常: $e');
        clientResults[clientName] = '❌ 异常: ${e.toString().substring(0, 50.clamp(0, e.toString().length))}';
      }
    }

    _log('');
    _log('╔══════════════════════════════════════════════╗');
    _log('║              客户端扫描结果                   ║');
    _log('╚══════════════════════════════════════════════╝');
    for (final entry in clientResults.entries) {
      _log('${entry.key}: ${entry.value}');
    }

    final workingClients = clientResults.entries.where((e) => e.value.contains('✅')).toList();
    if (workingClients.isNotEmpty) {
      _log('');
      _log('🎉 可用的客户端: ${workingClients.map((e) => e.key).join(', ')}');

      // 自动测试第一个可用客户端的播放
      final firstWorking = workingClients.first.key;
      _log('');
      _log('>>> 自动测试 $firstWorking 的 media_kit 播放...');

      try {
        final clients = _clientCombinations[firstWorking]!;
        final manifest = await _youtube.videos.streams.getManifest(videoId, ytClients: clients);
        if (manifest.audioOnly.isNotEmpty) {
          final stream = manifest.audioOnly.first;
          _log('播放: ${stream.audioCodec}/${stream.container.name}');
          _log('URL: ${stream.url.toString().substring(0, 100)}...');

          await _player.stop();
          await Future.delayed(const Duration(milliseconds: 200));

          final media = Media(stream.url.toString());
          await _player.open(media);

          // 等待播放状态
          for (int i = 0; i < 30; i++) {
            await Future.delayed(const Duration(milliseconds: 100));
            if (_error != null) {
              _log('❌ media_kit 播放失败: $_error');
              break;
            }
            if (_isPlaying && _duration.inMilliseconds > 0) {
              _log('✅ media_kit 播放成功! duration=${_duration.inSeconds}s');
              _log('');
              _log('🎊 结论: $firstWorking 客户端的 audio-only 流可以播放!');
              break;
            }
          }
        }
      } catch (e) {
        _log('❌ 播放测试异常: $e');
      }
    } else {
      _log('');
      _log('⚠️ 所有客户端的 audio-only 流都无法访问');
    }

    setState(() {
      _isLoading = false;
      _status = '客户端扫描完成:\n${clientResults.entries.map((e) => '${e.key}: ${e.value}').join('\n')}';
    });
  }

  void _log(String message) {
    debugPrint('[YouTubeStreamTest] $message');
    if (mounted) {
      setState(() {
        _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
      });
    }
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

  String _formatBitrate(int bps) {
    if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
    if (bps >= 1000) return '${(bps / 1000).toStringAsFixed(0)} kbps';
    return '$bps bps';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${t.debug.streamTest} (${Platform.operatingSystem})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: t.debug.clearLogs,
            onPressed: () => setState(() => _logs.clear()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 上半部分
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 输入
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _videoIdController,
                            decoration: InputDecoration(
                              labelText: 'YouTube Video ID',
                              hintText: t.debug.videoIdHint,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading ? null : _fetchStreams,
                                  icon: _isLoading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.search, size: 18),
                                  label: Text(t.debug.fetchStreams),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading || _availableStreams.isEmpty ? null : _runAutoTest,
                                  icon: const Icon(Icons.science, size: 18),
                                  label: Text(t.debug.batchTest),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.tertiary,
                                    foregroundColor: Theme.of(context).colorScheme.onTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // API 客户端选择
                          Row(
                            children: [
                              Text('API客户端:', style: Theme.of(context).textTheme.labelMedium),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _selectedApiClient,
                                  items: _clientCombinations.keys.map((key) {
                                    return DropdownMenuItem(value: key, child: Text(key, style: const TextStyle(fontSize: 12)));
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) setState(() => _selectedApiClient = value);
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // 扫描所有客户端按钮
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _scanAllClients,
                              icon: const Icon(Icons.radar, size: 18),
                              label: Text(t.debug.scanAllClients),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Headers 选择 + 播放控制
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Headers 选择
                          Text(t.debug.playbackHeaders, style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            children: _clientHeaders.keys.map((type) {
                              return ChoiceChip(
                                label: Text(type, style: const TextStyle(fontSize: 12)),
                                selected: _selectedHeaderType == type,
                                onSelected: (selected) {
                                  if (selected) setState(() => _selectedHeaderType = type);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                          // 播放控制
                          if (_currentStream != null) ...[
                            Row(
                              children: [
                                IconButton.filled(
                                  onPressed: () => _player.playOrPause(),
                                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                                  iconSize: 20,
                                ),
                                IconButton.filled(
                                  onPressed: () => _player.stop(),
                                  icon: const Icon(Icons.stop),
                                  iconSize: 20,
                                ),
                                const SizedBox(width: 12),
                                Text('${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: _duration.inMilliseconds > 0
                                  ? _position.inMilliseconds / _duration.inMilliseconds : 0,
                            ),
                          ],
                          const SizedBox(height: 8),
                          SelectableText(
                            _status,
                            style: TextStyle(
                              fontFamily: 'monospace', fontSize: 11,
                              color: _status.contains('✅') ? Colors.green
                                  : _status.contains('❌') ? Colors.red : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 流列表
                  if (_availableStreams.isNotEmpty) ...[
                    _buildStreamSection('Audio-only', StreamType.audioOnly),
                    _buildStreamSection('Muxed', StreamType.muxed),
                    _buildStreamSection('HLS', StreamType.hls),
                  ],
                ],
              ),
            ),
          ),
          
          // 日志区
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: Colors.black87,
              border: Border(top: BorderSide(color: Colors.grey.shade700)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  color: Colors.grey.shade800,
                  child: Row(
                    children: [
                      const Icon(Icons.terminal, color: Colors.white70, size: 14),
                      const SizedBox(width: 6),
                      Text('${t.debug.logs} (${_logs.length})',
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(6),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      Color color = Colors.white70;
                      if (log.contains('❌')) color = Colors.red.shade300;
                      if (log.contains('✅')) color = Colors.green.shade300;
                      if (log.contains('===') || log.contains('═')) color = Colors.cyan.shade300;
                      if (log.contains('---')) color = Colors.yellow.shade300;
                      return Text(log, style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: color));
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamSection(String title, StreamType type) {
    final streams = _availableStreams.where((s) => s.type == type).toList();
    if (streams.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        title: Text('$title (${streams.length})', style: const TextStyle(fontSize: 13)),
        initiallyExpanded: type == StreamType.audioOnly,
        childrenPadding: EdgeInsets.zero,
        children: streams.map((stream) => ListTile(
          dense: true,
          title: Text(stream.label, style: const TextStyle(fontSize: 12)),
          subtitle: Text(stream.rawInfo, style: const TextStyle(fontSize: 9)),
          trailing: SizedBox(
            width: 100,
            height: 28,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _verifyStream(stream),
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(t.debug.verify, style: TextStyle(fontSize: 10)),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 44,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _playStream(stream),
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(t.debug.play, style: TextStyle(fontSize: 10)),
                  ),
                ),
              ],
            ),
          ),
          selected: _currentStream == stream,
        )).toList(),
      ),
    );
  }
}

enum StreamType { audioOnly, muxed, hls }

class StreamInfo {
  final StreamType type;
  final String url;
  final String codec;
  final int bitrate;
  final String container;
  final String client;
  final String label;
  final String rawInfo;

  StreamInfo({
    required this.type,
    required this.url,
    required this.codec,
    required this.bitrate,
    required this.container,
    required this.client,
    required this.label,
    required this.rawInfo,
  });
}