// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Referer': 'https://live.bilibili.com/',
    },
  ));

  const roomId = '2388053';

  // 1. room_init
  final initResp = await dio.get(
    'https://api.live.bilibili.com/room/v1/Room/room_init',
    queryParameters: {'id': roomId},
  );
  final realRoomId = initResp.data['data']['room_id'].toString();
  final uid = initResp.data['data']['uid'].toString();
  print('realRoomId: $realRoomId, uid: $uid');

  // 2. room/v1/Room/get_info
  final roomResp = await dio.get(
    'https://api.live.bilibili.com/room/v1/Room/get_info',
    queryParameters: {'room_id': realRoomId},
  );
  final roomData = roomResp.data['data'] as Map;
  print('\n=== room/v1/Room/get_info ===');
  print('title: ${roomData['title']}');
  final desc = roomData['description']?.toString() ?? '';
  print('description (前200字): ${desc.substring(0, desc.length.clamp(0, 200))}');
  print('tags: ${roomData['tags']}');
  print('area_name: ${roomData['area_name']}');
  print('parent_area_name: ${roomData['parent_area_name']}');
  print('所有頂層 key: ${roomData.keys.toList()}');

  // 3. anchor info
  final anchorResp = await dio.get(
    'https://api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room',
    queryParameters: {'roomid': realRoomId},
  );
  if (anchorResp.data['code'] == 0) {
    print('\n=== anchor info ===');
    print(const JsonEncoder.withIndent('  ').convert(anchorResp.data['data']));
  }

  // 4. space/acc/info (個人簡介) - 可能需要 WBI
  try {
    final spaceResp = await dio.get(
      'https://api.bilibili.com/x/space/wbi/acc/info',
      queryParameters: {'mid': uid},
    );
    print('\n=== space/acc/info ===');
    print('code: ${spaceResp.data['code']}');
    if (spaceResp.data['code'] == 0) {
      final d = spaceResp.data['data'];
      print('sign: ${d['sign']}');
    } else {
      print('message: ${spaceResp.data['message']}');
    }
  } catch (e) {
    print('space info error: $e');
  }

  // 5. room_news (主播公告)
  try {
    final newsResp = await dio.get(
      'https://api.live.bilibili.com/room_ex/v1/RoomNews/get',
      queryParameters: {'roomid': realRoomId},
    );
    print('\n=== RoomNews/get (主播公告) ===');
    print('code: ${newsResp.data['code']}');
    if (newsResp.data['code'] == 0) {
      print(const JsonEncoder.withIndent('  ').convert(newsResp.data['data']));
    } else {
      print('message: ${newsResp.data['message']}');
    }
  } catch (e) {
    print('room news error: $e');
  }

  // 6. 嘗試舊版 space API
  try {
    final spaceResp2 = await dio.get(
      'https://api.bilibili.com/x/space/acc/info',
      queryParameters: {'mid': uid},
    );
    print('\n=== x/space/acc/info (舊版) ===');
    print('code: ${spaceResp2.data['code']}');
    if (spaceResp2.data['code'] == 0) {
      final d = spaceResp2.data['data'];
      print('sign: ${d['sign']}');
    } else {
      print('message: ${spaceResp2.data['message']}');
    }
  } catch (e) {
    print('old space info error: $e');
  }

  dio.close();
}
