// Bilibili 直播间 API 测试 Demo
// 运行方式: dart run test/bilibili_live_api_test.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

/// 测试 Bilibili 直播相关 API
class BilibiliLiveApiTest {
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
  static const String _referer = 'https://www.bilibili.com';

  static String _generateBuvid3() {
    final random = DateTime.now().millisecondsSinceEpoch;
    String randomHex(int length) {
      const chars = '0123456789ABCDEF';
      return List.generate(length, (i) => chars[(random + i) % 16]).join();
    }
    return '${randomHex(8)}-${randomHex(4)}-${randomHex(4)}-${randomHex(4)}-${randomHex(12)}infoc';
  }

  static Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Referer': _referer,
        'Cookie': 'buvid3=${_generateBuvid3()}',
      };

  /// 1. 搜索用户 API
  /// search_type=bili_user 搜索用户
  /// 返回用户列表，包含 mid (用户ID)、uname (用户名)、room_id (直播间ID，如果有)
  static Future<void> testSearchUser(String keyword) async {
    print('\n=== 测试搜索用户 API ===');
    print('关键词: $keyword');

    final url = Uri.parse(
      'https://api.bilibili.com/x/web-interface/search/type'
      '?search_type=bili_user&keyword=${Uri.encodeComponent(keyword)}&page=1&page_size=10',
    );

    try {
      final response = await http.get(url, headers: _headers);
      final data = jsonDecode(response.body);

      if (data['code'] != 0) {
        print('错误: ${data['message']}');
        return;
      }

      final results = data['data']['result'] as List? ?? [];
      print('找到 ${results.length} 个用户:');

      for (final user in results) {
        print('---');
        print('  用户名: ${user['uname']}');
        print('  UID: ${user['mid']}');
        print('  粉丝数: ${user['fans']}');
        print('  直播间ID: ${user['room_id']}'); // 0 表示没有直播间
        print('  头像: ${user['upic']}');
        print('  签名: ${user['usign']}');
      }
    } catch (e) {
      print('请求失败: $e');
    }
  }

  /// 2. 通过 UID 获取直播间状态
  /// 返回直播间基本信息，包括 roomid、直播状态、标题、封面等
  static Future<Map<String, dynamic>?> testGetRoomInfoByUid(int uid) async {
    print('\n=== 测试通过 UID 获取直播间信息 ===');
    print('UID: $uid');

    final url = Uri.parse(
      'https://api.live.bilibili.com/room/v1/Room/getRoomInfoOld?mid=$uid',
    );

    try {
      final response = await http.get(url, headers: _headers);
      final data = jsonDecode(response.body);

      if (data['code'] != 0) {
        print('错误: ${data['message']}');
        return null;
      }

      final roomData = data['data'];
      print('直播间信息:');
      print('  房间状态: ${roomData['roomStatus']} (0=无房间, 1=有房间)');
      print('  直播状态: ${roomData['liveStatus']} (0=未开播, 1=直播中)');
      print('  轮播状态: ${roomData['roundStatus']} (0=未轮播, 1=轮播中)');
      print('  直播间ID: ${roomData['roomid']}');
      print('  标题: ${roomData['title']}');
      print('  封面: ${roomData['cover']}');
      print('  人气: ${roomData['online']}');
      print('  URL: ${roomData['url']}');

      return roomData;
    } catch (e) {
      print('请求失败: $e');
      return null;
    }
  }

  /// 3. 获取直播间详细信息
  /// 通过 room_id 获取更详细的直播间信息
  static Future<Map<String, dynamic>?> testGetRoomInfo(int roomId) async {
    print('\n=== 测试获取直播间详细信息 ===');
    print('Room ID: $roomId');

    final url = Uri.parse(
      'https://api.live.bilibili.com/room/v1/Room/get_info?room_id=$roomId',
    );

    try {
      final response = await http.get(url, headers: _headers);
      final data = jsonDecode(response.body);

      if (data['code'] != 0) {
        print('错误: ${data['message']}');
        return null;
      }

      final roomData = data['data'];
      print('直播间详细信息:');
      print('  真实房间ID: ${roomData['room_id']}');
      print('  短号: ${roomData['short_id']}');
      print('  主播UID: ${roomData['uid']}');
      print('  标题: ${roomData['title']}');
      print('  直播状态: ${roomData['live_status']} (0=未开播, 1=直播中, 2=轮播中)');
      print('  分区: ${roomData['parent_area_name']} > ${roomData['area_name']}');
      print('  封面: ${roomData['user_cover']}');
      print('  关键帧: ${roomData['keyframe']}');
      print('  描述: ${roomData['description']}');
      print('  标签: ${roomData['tags']}');
      print('  开播时间: ${roomData['live_time']}');
      print('  在线人数: ${roomData['online']}');

      return roomData;
    } catch (e) {
      print('请求失败: $e');
      return null;
    }
  }

  /// 4. 获取主播信息
  /// 通过 room_id 获取主播的用户信息
  static Future<void> testGetAnchorInfo(int roomId) async {
    print('\n=== 测试获取主播信息 ===');
    print('Room ID: $roomId');

    final url = Uri.parse(
      'https://api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room?roomid=$roomId',
    );

    try {
      final response = await http.get(url, headers: _headers);
      final data = jsonDecode(response.body);

      if (data['code'] != 0) {
        print('错误: ${data['message']}');
        return;
      }

      final info = data['data']['info'];
      print('主播信息:');
      print('  UID: ${info['uid']}');
      print('  用户名: ${info['uname']}');
      print('  头像: ${info['face']}');
      print('  性别: ${info['gender']}');
    } catch (e) {
      print('请求失败: $e');
    }
  }

  /// 5. 获取直播流地址
  /// 获取直播间的音视频流地址
  static Future<void> testGetLiveStream(int roomId) async {
    print('\n=== 测试获取直播流地址 ===');
    print('Room ID: $roomId');

    // 使用 H5 平台获取 HLS 流
    final url = Uri.parse(
      'https://api.live.bilibili.com/room/v1/Room/playUrl'
      '?cid=$roomId&platform=h5&quality=4',
    );

    try {
      final response = await http.get(url, headers: _headers);
      final data = jsonDecode(response.body);

      if (data['code'] != 0) {
        print('错误: ${data['message']}');
        return;
      }

      final playData = data['data'];
      print('直播流信息:');
      print('  当前画质: ${playData['current_quality']}');
      print('  可用画质: ${playData['accept_quality']}');

      final durls = playData['durl'] as List? ?? [];
      for (int i = 0; i < durls.length; i++) {
        final durl = durls[i];
        print('  流 $i:');
        print('    URL: ${durl['url']}');
        print('    长度: ${durl['length']}');
        print('    大小: ${durl['size']}');
      }
    } catch (e) {
      print('请求失败: $e');
    }
  }

  /// 6. 搜索直播间 (仅能搜索正在直播的)
  /// search_type=live_room 搜索直播间
  static Future<void> testSearchLiveRoom(String keyword) async {
    print('\n=== 测试搜索直播间 API (仅正在直播) ===');
    print('关键词: $keyword');

    final url = Uri.parse(
      'https://api.bilibili.com/x/web-interface/search/type'
      '?search_type=live_room&keyword=${Uri.encodeComponent(keyword)}&page=1&page_size=10',
    );

    try {
      final response = await http.get(url, headers: _headers);
      final data = jsonDecode(response.body);

      if (data['code'] != 0) {
        print('错误: ${data['message']}');
        return;
      }

      final results = data['data']['result'] as List? ?? [];
      print('找到 ${results.length} 个正在直播的直播间:');

      for (final room in results) {
        print('---');
        print('  房间ID: ${room['roomid']}');
        print('  主播: ${room['uname']}');
        print('  UID: ${room['uid']}');
        print('  标题: ${room['title']}');
        print('  分区: ${room['cate_name']}');
        print('  人气: ${room['online']}');
        print('  封面: ${room['user_cover']}');
      }
    } catch (e) {
      print('请求失败: $e');
    }
  }

  /// 7. 搜索主播 (包括未开播的)
  /// search_type=live_user 搜索主播
  static Future<void> testSearchLiveUser(String keyword) async {
    print('\n=== 测试搜索主播 API (包括未开播) ===');
    print('关键词: $keyword');

    final url = Uri.parse(
      'https://api.bilibili.com/x/web-interface/search/type'
      '?search_type=live_user&keyword=${Uri.encodeComponent(keyword)}&page=1&page_size=10',
    );

    try {
      final response = await http.get(url, headers: _headers);
      final data = jsonDecode(response.body);

      if (data['code'] != 0) {
        print('错误: ${data['message']}');
        return;
      }

      final results = data['data']['result'] as List? ?? [];
      print('找到 ${results.length} 个主播:');

      for (final user in results) {
        print('---');
        print('  主播: ${user['uname']}');
        print('  UID: ${user['uid']}');
        print('  房间ID: ${user['roomid']}');
        print('  直播状态: ${user['is_live']} (true=直播中)');
        print('  分区: ${user['cate_name']}');
        print('  标签: ${user['tags']}');
        print('  头像: ${user['uface']}');
      }
    } catch (e) {
      print('请求失败: $e');
    }
  }
}

void main() async {
  print('========================================');
  print('Bilibili 直播 API 测试');
  print('========================================');

  // 测试搜索用户
  await BilibiliLiveApiTest.testSearchUser('洛天依');

  // 测试搜索主播 (包括未开播的) - 这是我们需要的 API!
  await BilibiliLiveApiTest.testSearchLiveUser('洛天依');

  // 测试搜索直播间 (仅正在直播)
  await BilibiliLiveApiTest.testSearchLiveRoom('音乐');

  // 测试通过 UID 获取直播间信息
  // 使用一个知名主播的 UID 进行测试
  final roomInfo = await BilibiliLiveApiTest.testGetRoomInfoByUid(36081646); // 示例 UID

  // 如果有直播间，获取详细信息
  if (roomInfo != null && roomInfo['roomid'] != null && roomInfo['roomid'] != 0) {
    final roomId = roomInfo['roomid'] as int;
    await BilibiliLiveApiTest.testGetRoomInfo(roomId);
    await BilibiliLiveApiTest.testGetAnchorInfo(roomId);

    // 如果正在直播或轮播，获取直播流
    if (roomInfo['liveStatus'] == 1 || roomInfo['roundStatus'] == 1) {
      await BilibiliLiveApiTest.testGetLiveStream(roomId);
    }
  }

  // 测试一个正在直播的房间的流地址
  print('\n=== 测试正在直播的房间流地址 ===');
  // 从搜索结果中找一个正在直播的房间 (LofiGirl 通常 24/7 直播)
  await BilibiliLiveApiTest.testGetLiveStream(27519423);

  print('\n========================================');
  print('测试完成');
  print('========================================');
}
