import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/allowed_hosts.dart';

void main() {
  final hosts = AllowedHosts(['bilibili.com', 'HDSLB.com.', '']);

  bool allows(String url) => hosts.allows(Uri.parse(url));

  test('the same host and its subdomains are allowed', () {
    expect(allows('https://bilibili.com/'), isTrue);
    expect(allows('https://api.bilibili.com/x/web-interface/search'), isTrue);
    expect(allows('https://a.b.bilibili.com/'), isTrue);
    // 清單項目與網址都不分大小寫、忽略結尾的點。
    expect(allows('https://i0.hdslb.com/bfs/a.jpg'), isTrue);
    expect(allows('https://API.Bilibili.COM./'), isTrue);
  });

  test('a lookalike without the dot boundary is not a subdomain', () {
    expect(allows('https://evil-bilibili.com/'), isFalse);
    expect(allows('https://bilibili.com.evil.net/'), isFalse);
    expect(allows('https://notbilibili.com/'), isFalse);
  });

  test('only https', () {
    expect(allows('http://api.bilibili.com/'), isFalse);
    expect(allows('ftp://api.bilibili.com/'), isFalse);
    expect(allows('api.bilibili.com/x'), isFalse);
  });

  test('the host is what counts, not userinfo, fragment or port', () {
    // userinfo 與 fragment 裡的允許網域不算：真正連的是 evil.com。
    expect(allows('https://bilibili.com@evil.com/'), isFalse);
    expect(allows('https://api.bilibili.com:x@evil.com/'), isFalse);
    expect(allows('https://evil.com#@api.bilibili.com'), isFalse);
    expect(allows('https://evil.com/?next=https://api.bilibili.com/'), isFalse);
    // 連接埠不在比對範圍內。
    expect(allows('https://api.bilibili.com:8443/'), isTrue);
  });

  test('non-ASCII and percent-encoded hosts are refused', () {
    // Dart 的 Uri 不做 IDNA，非 ASCII 與保留字元留成百分比編碼。
    expect(
      Uri.parse('https://evil.com%2F.bilibili.com/').host,
      'evil.com%2F.bilibili.com',
    );
    expect(allows('https://evil.com%2F.bilibili.com/'), isFalse);
    expect(allows('https://evil.com%00.bilibili.com/'), isFalse);
    expect(allows('https://bücher.bilibili.com/'), isFalse);
    // 相鄰案例：punycode 的子網域照常允許。
    expect(allows('https://xn--bcher-kva.bilibili.com/'), isTrue);
  });

  test('allowsHost and isSameOrSubdomain use the dot boundary', () {
    expect(hosts.allowsHost('bilibili.com'), isTrue);
    expect(hosts.allowsHost('com'), isFalse);
    expect(hosts.allowsHost(''), isFalse);
    expect(
      AllowedHosts.isSameOrSubdomain('api.bilibili.com', 'bilibili.com'),
      isTrue,
    );
    expect(
      AllowedHosts.isSameOrSubdomain('evil-bilibili.com', 'bilibili.com'),
      isFalse,
    );
    expect(AllowedHosts.isSameOrSubdomain('bilibili.com', ''), isFalse);
  });

  test('an empty entry does not allow everything', () {
    expect(allows('https://example.org/'), isFalse);
    expect(
      AllowedHosts([]).allows(Uri.parse('https://bilibili.com/')),
      isFalse,
    );
  });

  test('sameHost compares normalized hosts only', () {
    expect(
      AllowedHosts.sameHost(
        Uri.parse('https://API.bilibili.com./a'),
        Uri.parse('https://api.bilibili.com/b?c=d'),
      ),
      isTrue,
    );
    expect(
      AllowedHosts.sameHost(
        Uri.parse('https://api.bilibili.com/'),
        Uri.parse('https://www.bilibili.com/'),
      ),
      isFalse,
    );
  });
}
