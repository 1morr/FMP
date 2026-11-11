import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../flutter_test_config.dart';

void main() {
  test('a plain test cannot open a real HTTP connection', () async {
    await expectLater(
      () async =>
          (await HttpClient().getUrl(Uri.parse('https://example.com'))).close(),
      throwsA(isA<NetworkAccessInTest>()),
    );
  });

  testWidgets('a widget test cannot open one either', (tester) async {
    // flutter_test 的 binding 自己會裝一個回 400 的假 HttpClient；
    // 我們要的是直接報錯，而不是讓程式拿到一個看似正常的回應。
    expect(() => HttpClient(), throwsA(isA<NetworkAccessInTest>()));
    await tester.pumpWidget(const SizedBox());
  });
}
