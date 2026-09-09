// ignore_for_file: avoid_print
/// Bilibili 直播 API 測試腳本
/// 測試不同 API 獲取觀眾數據的能力
///
/// 運行方式: dart run test/demo/bilibili_live_api_demo.dart [房間號]
/// 例如: dart run test/demo/bilibili_live_api_demo.dart 21452505
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

// 測試房間號（可通過命令行參數覆蓋）
const defaultRoomId = '21452505';

late Dio dio;

void main(List<String> args) async {
  final roomId = args.isNotEmpty ? args[0] : defaultRoomId;

  print('=' * 60);
  print('Bilibili 直播 API 測試');
  print('測試房間號: $roomId');
  print('=' * 60);

  dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://live.bilibili.com/',
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  // 先獲取真實房間號
  final realRoomId = await getRealRoomId(roomId);
  print('\n真實房間號: $realRoomId');

  print('\n${'=' * 60}');
  print('測試 1: room/v1/Room/get_info (當前使用的 API)');
  print('=' * 60);
  await testRoomV1GetInfo(realRoomId);

  print('\n${'=' * 60}');
  print('測試 2: xlive/web-room/v1/index/getInfoByRoom');
  print('=' * 60);
  await testXliveGetInfoByRoom(realRoomId);

  print('\n${'=' * 60}');
  print('測試 3: xlive/web-room/v2/index/getRoomPlayInfo');
  print('=' * 60);
  await testXliveGetRoomPlayInfo(realRoomId);

  print('\n${'=' * 60}');
  print('測試 4: xlive/general-interface/v1/rank/getOnlineGoldRank');
  print('=' * 60);
  await testOnlineGoldRank(realRoomId);

  print('\n${'=' * 60}');
  print('測試 5: xlive/web-room/v1/index/getRoomBaseInfo');
  print('=' * 60);
  await testGetRoomBaseInfo(realRoomId);

  print('\n${'=' * 60}');
  print('測試 6: WebSocket 彈幕連接 (使用 room/v1/Danmu/getConf)');
  print('=' * 60);
  await testWebSocket(realRoomId);

  dio.close();
  print('\n測試完成！');
}

/// 獲取真實房間號（短號轉長號）
Future<String> getRealRoomId(String roomId) async {
  try {
    final response = await dio.get(
      'https://api.live.bilibili.com/room/v1/Room/room_init',
      queryParameters: {'id': roomId},
    );
    if (response.data['code'] == 0) {
      return response.data['data']['room_id'].toString();
    }
  } catch (e) {
    print('獲取真實房間號失敗: $e');
  }
  return roomId;
}

/// 測試 1: room/v1/Room/get_info
Future<void> testRoomV1GetInfo(String roomId) async {
  try {
    final response = await dio.get(
      'https://api.live.bilibili.com/room/v1/Room/get_info',
      queryParameters: {'room_id': roomId},
    );

    print('響應碼: ${response.data['code']}');

    if (response.data['code'] == 0) {
      final data = response.data['data'];
      print('✅ 成功獲取數據');
      print('  - 房間標題: ${data['title']}');
      print('  - 直播狀態: ${data['live_status'] == 1 ? '直播中' : '未開播'}');
      print('  - online (人氣值): ${data['online']}');
      print('  - 分區: ${data['area_name']}');
      print('  - 開播時間: ${data['live_time']}');

      print('\n📋 完整 data 字段:');
      _printJson(data);
    } else {
      print('❌ 請求失敗: ${response.data['message']}');
    }
  } catch (e) {
    print('❌ 請求異常: $e');
  }
}

/// 測試 2: xlive/web-room/v1/index/getInfoByRoom
Future<void> testXliveGetInfoByRoom(String roomId) async {
  try {
    final response = await dio.get(
      'https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom',
      queryParameters: {'room_id': roomId},
    );

    print('響應碼: ${response.data['code']}');

    if (response.data['code'] == 0) {
      final data = response.data['data'];
      print('✅ 成功獲取數據');

      // room_info
      if (data['room_info'] != null) {
        final roomInfo = data['room_info'];
        print('  - 房間標題: ${roomInfo['title']}');
        print('  - online (人氣值): ${roomInfo['online']}');
      }

      // watched_show - 這可能是真實觀看數
      if (data['watched_show'] != null) {
        final watchedShow = data['watched_show'];
        print('  - watched_show.num: ${watchedShow['num']}');
        print('  - watched_show.text_small: ${watchedShow['text_small']}');
        print('  - watched_show.text_large: ${watchedShow['text_large']}');
        print('  ⭐ watched_show 可能是真實觀看人數！');
      }

      print('\n📋 關鍵字段:');
      print('  room_info.online: ${data['room_info']?['online']}');
      print('  watched_show: ${data['watched_show']}');
    } else {
      print('❌ 請求失敗: ${response.data['message']}');
      print('  (這個 API 可能需要登錄或 WBI 簽名)');
    }
  } catch (e) {
    print('❌ 請求異常: $e');
  }
}

/// 測試 3: xlive/web-room/v2/index/getRoomPlayInfo
Future<void> testXliveGetRoomPlayInfo(String roomId) async {
  try {
    final response = await dio.get(
      'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo',
      queryParameters: {
        'room_id': roomId,
        'protocol': '0,1',
        'format': '0,1,2',
        'codec': '0,1',
        'qn': 10000,
        'platform': 'web',
        'ptype': 8,
      },
    );

    print('響應碼: ${response.data['code']}');

    if (response.data['code'] == 0) {
      final data = response.data['data'];
      print('✅ 成功獲取數據');
      print('  - room_id: ${data['room_id']}');
      print('  - uid: ${data['uid']}');
      print('  - live_status: ${data['live_status']}');
      print('  - live_time: ${data['live_time']}');

      // 這個 API 主要用於獲取播放地址，可能沒有觀眾數
      if (data['playurl_info'] != null) {
        print('  - 有播放地址信息');
      }

      print('\n📋 完整 data 字段:');
      _printJson(data);
    } else {
      print('❌ 請求失敗: ${response.data['message']}');
    }
  } catch (e) {
    print('❌ 請求異常: $e');
  }
}

/// 測試 4: 在線排行榜 API
Future<void> testOnlineGoldRank(String roomId) async {
  try {
    // 先獲取主播 uid
    final roomResponse = await dio.get(
      'https://api.live.bilibili.com/room/v1/Room/get_info',
      queryParameters: {'room_id': roomId},
    );

    if (roomResponse.data['code'] != 0) {
      print('❌ 無法獲取房間信息');
      return;
    }

    final uid = roomResponse.data['data']['uid'];

    final response = await dio.get(
      'https://api.live.bilibili.com/xlive/general-interface/v1/rank/getOnlineGoldRank',
      queryParameters: {
        'ruid': uid,
        'roomId': roomId,
        'page': 1,
        'pageSize': 50,
      },
    );

    print('響應碼: ${response.data['code']}');

    if (response.data['code'] == 0) {
      final data = response.data['data'];
      print('✅ 成功獲取數據');
      print('  - onlineNum (高能用戶數): ${data['onlineNum']}');

      if (data['OnlineRankItem'] != null) {
        final items = data['OnlineRankItem'] as List;
        print('  - 排行榜人數: ${items.length}');
      }
      print('  注意: onlineNum 是高能用戶數，不是總觀眾數');
    } else {
      print('❌ 請求失敗: ${response.data['message']}');
    }
  } catch (e) {
    print('❌ 請求異常: $e');
  }
}

/// 測試 5: getRoomBaseInfo (批量獲取房間信息)
Future<void> testGetRoomBaseInfo(String roomId) async {
  try {
    final response = await dio.get(
      'https://api.live.bilibili.com/xlive/web-room/v1/index/getRoomBaseInfo',
      queryParameters: {'room_ids': roomId, 'req_biz': 'link-center'},
    );

    print('響應碼: ${response.data['code']}');

    if (response.data['code'] == 0) {
      final data = response.data['data'];
      print('✅ 成功獲取數據');

      if (data['by_room_ids'] != null && data['by_room_ids'][roomId] != null) {
        final roomData = data['by_room_ids'][roomId];
        print('  - 房間標題: ${roomData['title']}');
        print('  - live_status: ${roomData['live_status']}');
        print('  - online: ${roomData['online']}');
        print('  - watched_show: ${roomData['watched_show']}');

        if (roomData['watched_show'] != null) {
          print('  ⭐ watched_show 詳情:');
          print('     - num: ${roomData['watched_show']['num']}');
          print('     - text_small: ${roomData['watched_show']['text_small']}');
        }
      }

      print('\n📋 完整數據:');
      _printJson(data);
    } else {
      print('❌ 請求失敗: ${response.data['message']}');
    }
  } catch (e) {
    print('❌ 請求異常: $e');
  }
}

/// 測試 6: WebSocket 彈幕連接
Future<void> testWebSocket(String roomId) async {
  print('正在獲取彈幕服務器信息...');

  try {
    // 嘗試使用 room/v1/Danmu/getConf (舊 API，可能不需要認證)
    Response confResponse;
    Map<String, dynamic> confData;
    String token;
    List hostList;

    // 方法 1: 嘗試舊 API
    try {
      confResponse = await dio.get(
        'https://api.live.bilibili.com/room/v1/Danmu/getConf',
        queryParameters: {'room_id': roomId},
      );

      if (confResponse.data['code'] == 0) {
        confData = confResponse.data['data'];
        token = confData['token'] ?? '';
        hostList = confData['host_server_list'] ?? [];
        print('使用 room/v1/Danmu/getConf API');
      } else {
        throw Exception('舊 API 失敗');
      }
    } catch (_) {
      // 方法 2: 嘗試新 API
      confResponse = await dio.get(
        'https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo',
        queryParameters: {'id': roomId},
      );

      if (confResponse.data['code'] != 0) {
        print('❌ 獲取彈幕配置失敗: ${confResponse.data['message']}');
        return;
      }

      confData = confResponse.data['data'];
      token = confData['token'] ?? '';
      hostList = confData['host_list'] ?? [];
      print('使用 xlive/web-room/v1/index/getDanmuInfo API');
    }

    if (hostList.isEmpty) {
      print('❌ 沒有可用的彈幕服務器');
      return;
    }

    final host = hostList[0];
    // 舊 API 和新 API 的字段名相同
    final wsHost = host['host'] ?? host['wss_host'];
    final wsPort = host['wss_port'] ?? 443;
    final wsUrl = 'wss://$wsHost:$wsPort/sub';

    print('彈幕服務器: $wsUrl');
    if (token.isNotEmpty) {
      print('Token: ${token.length > 20 ? token.substring(0, 20) : token}...');
    } else {
      print('Token: (空)');
    }

    print('\n正在連接 WebSocket...');

    final ws = await WebSocket.connect(wsUrl);
    print('✅ WebSocket 連接成功');

    // 發送認證包
    final authPacket = _buildAuthPacket(int.parse(roomId), token);
    ws.add(authPacket);
    print('已發送認證包');

    // 設置心跳定時器
    Timer? heartbeatTimer;

    // 監聽消息
    int messageCount = 0;
    final completer = Completer<void>();

    ws.listen(
      (data) {
        if (data is List<int>) {
          final packets = _parsePackets(Uint8List.fromList(data));
          for (final packet in packets) {
            messageCount++;

            if (packet['op'] == 8) {
              // 認證成功
              print('✅ 認證成功');

              // 立即發送一次心跳獲取人氣值
              ws.add(_buildHeartbeatPacket());
              print('  [心跳] 已發送初始心跳');

              // 開始定時心跳
              heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
                ws.add(_buildHeartbeatPacket());
                print('  [心跳] 已發送');
              });
            } else if (packet['op'] == 3) {
              // 心跳回應，包含人氣值
              final popularity = packet['body'];
              print('  [人氣值] $popularity');
            } else if (packet['op'] == 5) {
              // 普通消息
              final body = packet['body'];
              if (body is Map) {
                final cmd = body['cmd'];

                if (cmd == 'DANMU_MSG') {
                  // 彈幕消息
                  final info = body['info'];
                  final text = info[1];
                  final uname = info[2][1];
                  print('  [彈幕] $uname: $text');
                } else if (cmd == 'SEND_GIFT') {
                  // 禮物
                  final data = body['data'];
                  print(
                    '  [禮物] ${data['uname']} 送出 ${data['giftName']} x${data['num']}',
                  );
                } else if (cmd == 'INTERACT_WORD') {
                  // 用戶進入
                  final data = body['data'];
                  print('  [進入] ${data['uname']} 進入直播間');
                } else if (cmd == 'ONLINE_RANK_COUNT') {
                  // 在線排名人數
                  final data = body['data'];
                  print('  ⭐ [在線人數] count: ${data['count']}');
                } else if (cmd == 'ONLINE_RANK_V2') {
                  // 在線排名
                  final data = body['data'];
                  print(
                    '  ⭐ [在線排名] online_list 人數: ${(data['online_list'] as List?)?.length}',
                  );
                } else if (cmd == 'WATCHED_CHANGE') {
                  // 觀看人數變化
                  final data = body['data'];
                  print(
                    '  ⭐ [觀看人數] num: ${data['num']}, text_small: ${data['text_small']}',
                  );
                } else if (cmd == 'LIKE_INFO_V3_UPDATE') {
                  // 點讚數更新
                  final data = body['data'];
                  print('  [點讚] count: ${data['click_count']}');
                } else if (cmd?.startsWith('ONLINE') == true ||
                    cmd?.contains('WATCH') == true ||
                    cmd?.contains('RANK') == true) {
                  // 其他可能包含觀眾數的命令
                  print('  ⭐ [$cmd] ${_truncateJson(body)}');
                }
              }
            }
          }
        }
      },
      onError: (e) {
        print('WebSocket 錯誤: $e');
        completer.complete();
      },
      onDone: () {
        print('WebSocket 連接關閉');
        completer.complete();
      },
    );

    // 等待 15 秒收集數據
    print('\n監聽消息中（15秒）...');
    await Future.any([
      completer.future,
      Future.delayed(const Duration(seconds: 15)),
    ]);

    heartbeatTimer?.cancel();
    await ws.close();

    print('\n收到 $messageCount 個數據包');
  } catch (e) {
    print('❌ WebSocket 測試失敗: $e');
  }
}

/// 構建認證包
Uint8List _buildAuthPacket(int roomId, String token) {
  final body = jsonEncode({
    'uid': 0, // 未登錄
    'roomid': roomId,
    'protover': 2, // 使用 zlib 壓縮（更容易解壓）
    'platform': 'web',
    'type': 2,
    'key': token,
  });

  return _buildPacket(7, utf8.encode(body));
}

/// 構建心跳包
Uint8List _buildHeartbeatPacket() {
  return _buildPacket(2, Uint8List(0));
}

/// 構建數據包
Uint8List _buildPacket(int operation, List<int> body) {
  const headerLength = 16;
  final totalLength = headerLength + body.length;

  final packet = ByteData(totalLength);
  packet.setUint32(0, totalLength, Endian.big); // 總長度
  packet.setUint16(4, headerLength, Endian.big); // 頭部長度
  packet.setUint16(6, 1, Endian.big); // 協議版本
  packet.setUint32(8, operation, Endian.big); // 操作碼
  packet.setUint32(12, 1, Endian.big); // 序列號

  final result = Uint8List(totalLength);
  result.setRange(0, headerLength, packet.buffer.asUint8List());
  result.setRange(headerLength, totalLength, body);

  return result;
}

/// 解析數據包
List<Map<String, dynamic>> _parsePackets(Uint8List data) {
  final packets = <Map<String, dynamic>>[];
  var offset = 0;

  while (offset < data.length) {
    if (offset + 16 > data.length) break;

    final view = ByteData.view(data.buffer, offset);
    final totalLength = view.getUint32(0, Endian.big);
    final headerLength = view.getUint16(4, Endian.big);
    final protocolVersion = view.getUint16(6, Endian.big);
    final operation = view.getUint32(8, Endian.big);

    if (offset + totalLength > data.length) break;

    final bodyData = data.sublist(offset + headerLength, offset + totalLength);

    dynamic body;

    if (operation == 3) {
      // 心跳回應，body 是 4 字節的人氣值
      if (bodyData.length >= 4) {
        body = ByteData.view(
          bodyData.buffer,
          bodyData.offsetInBytes,
        ).getUint32(0, Endian.big);
      }
    } else if (operation == 5) {
      // 普通消息
      if (protocolVersion == 0 || protocolVersion == 1) {
        // 未壓縮
        try {
          body = jsonDecode(utf8.decode(bodyData));
        } catch (_) {}
      } else if (protocolVersion == 2) {
        // zlib 壓縮
        try {
          final decompressed = zlib.decode(bodyData);
          // 遞歸解析
          packets.addAll(_parsePackets(Uint8List.fromList(decompressed)));
          offset += totalLength;
          continue;
        } catch (_) {}
      } else if (protocolVersion == 3) {
        // brotli 壓縮 - 需要額外庫支持，這裡跳過
        // 實際項目中可以使用 brotli 包
      }
    } else if (operation == 8) {
      // 認證成功
      body = 'AUTH_SUCCESS';
    }

    packets.add({'op': operation, 'ver': protocolVersion, 'body': body});

    offset += totalLength;
  }

  return packets;
}

void _printJson(dynamic data) {
  const encoder = JsonEncoder.withIndent('  ');
  final lines = encoder.convert(data).split('\n');
  for (final line in lines.take(30)) {
    print('  $line');
  }
  if (lines.length > 30) {
    print('  ... (${lines.length - 30} more lines)');
  }
}

String _truncateJson(dynamic data) {
  final str = jsonEncode(data);
  if (str.length > 100) {
    return '${str.substring(0, 100)}...';
  }
  return str;
}
