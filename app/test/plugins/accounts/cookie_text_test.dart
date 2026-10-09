import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/plugins/accounts/cookie_text.dart';

// 「貼上 cookie」的兩種格式（ADR 0029 §決定 10）。值都是假的。

void main() {
  group('a Cookie header', () {
    test('name=value pairs separated by semicolons', () {
      expect(parseCookieText('SID=FAKE_SID_1; HSID=FAKE_HSID_1;PREF=f6=8'), {
        'SID': 'FAKE_SID_1',
        'HSID': 'FAKE_HSID_1',
        // 值裡的 `=` 原樣保留（只在第一個 `=` 分開）。
        'PREF': 'f6=8',
      });
    });

    test('with a Cookie: prefix, over several lines, with spaces', () {
      expect(
        parseCookieText(
          '  cookie: SID=FAKE_SID_1 ;\n'
          'Cookie:HSID = FAKE_HSID_1\r\n'
          '\n'
          '  LOGIN_INFO=AFmm:QUQ="  \n',
        ),
        {
          'SID': 'FAKE_SID_1',
          'HSID': 'FAKE_HSID_1',
          // 值不去引號、不解碼。
          'LOGIN_INFO': 'AFmm:QUQ="',
        },
      );
    });

    test('pieces it cannot read are skipped; the later one of a name wins', () {
      expect(
        parseCookieText(
          'SID=FAKE_OLD; just text; =no-name; bad name=x; ;SID=FAKE_NEW; '
          'EMPTY=',
        ),
        {'SID': 'FAKE_NEW', 'EMPTY': ''},
      );
    });
  });

  group('a Netscape cookies.txt', () {
    test('tab-separated lines, comments, and #HttpOnly_ lines', () {
      const file =
          '# Netscape HTTP Cookie File\n'
          '# https://curl.se/docs/http-cookies.html\n'
          '\n'
          '.example.test\tTRUE\t/\tTRUE\t1893456000\tSID\tFAKE_SID_1\n'
          '#HttpOnly_.example.test\tTRUE\t/\tTRUE\t1893456000\t__Secure-1PSID\tFAKE_PSID_1\n'
          'www.example.test\tFALSE\t/\tFALSE\t0\tPREF\tf6=8\n';
      expect(parseCookieText(file), {
        'SID': 'FAKE_SID_1',
        '__Secure-1PSID': 'FAKE_PSID_1',
        'PREF': 'f6=8',
      });
    });

    test('tabs turned into spaces by the copy still read', () {
      expect(
        parseCookieText(
          '.example.test  TRUE  /  TRUE  1893456000  SID  FAKE_SID_1\r\n'
          '.example.test TRUE / TRUE 1893456000 LOGIN_INFO AFmm:QUQ=',
        ),
        {'SID': 'FAKE_SID_1', 'LOGIN_INFO': 'AFmm:QUQ='},
      );
    });

    test('malformed lines are skipped', () {
      const file =
          // 少一欄
          '.example.test\tTRUE\t/\tTRUE\tSID\tFAKE_SID_1\n'
          // 旗標不是 TRUE／FALSE
          '.example.test\tyes\t/\tTRUE\t0\tA\tFAKE_A\n'
          // 到期不是整數
          '.example.test\tTRUE\t/\tTRUE\tsoon\tB\tFAKE_B\n'
          // 多一欄
          '.example.test\tTRUE\t/\tTRUE\t0\tC\tFAKE_C\textra\n'
          // 註解裡的 cookie 不算
          '# .example.test\tTRUE\t/\tTRUE\t0\tD\tFAKE_D\n'
          '.example.test\tTRUE\t/\tTRUE\t0\tOK\tFAKE_OK\n';
      expect(parseCookieText(file), {'OK': 'FAKE_OK'});
    });

    test('mixed with a header line', () {
      expect(
        parseCookieText(
          '.example.test\tTRUE\t/\tTRUE\t0\tSID\tFAKE_SID_1\n'
          'HSID=FAKE_HSID_1\n',
        ),
        {'SID': 'FAKE_SID_1', 'HSID': 'FAKE_HSID_1'},
      );
    });
  });

  test('nothing readable is an empty map', () {
    for (final text in ['', '  \n\t\n', '# only a comment', 'hello world']) {
      expect(parseCookieText(text), isEmpty, reason: text);
    }
  });
}
