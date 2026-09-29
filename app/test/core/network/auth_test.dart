import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/auth.dart';

import '../../support/fake_http_adapter.dart';
import 'harness.dart';

/// ADR 0012 §如何確認：三種標記在「未登入／已登入且開關開／已登入且開關關」
/// 下的注入結果。
enum _State { loggedOut, loggedInOn, loggedInOff }

const _expected = {
  (_State.loggedOut, AuthRequirement.required): AuthDecision.refuse,
  (_State.loggedOut, AuthRequirement.userPreference): AuthDecision.omit,
  (_State.loggedOut, AuthRequirement.never): AuthDecision.omit,
  (_State.loggedInOn, AuthRequirement.required): AuthDecision.attach,
  (_State.loggedInOn, AuthRequirement.userPreference): AuthDecision.attach,
  (_State.loggedInOn, AuthRequirement.never): AuthDecision.omit,
  // 開關只管 userPreference；required 已登入就一定帶。
  (_State.loggedInOff, AuthRequirement.required): AuthDecision.attach,
  (_State.loggedInOff, AuthRequirement.userPreference): AuthDecision.omit,
  (_State.loggedInOff, AuthRequirement.never): AuthDecision.omit,
};

const _credential = {'Authorization': 'Bearer FAKE_TOKEN_123'};

void main() {
  test('the table covers every state and requirement', () {
    expect(_expected, hasLength(_State.values.length * 3));
  });

  group('decideAuth', () {
    for (final MapEntry(key: (state, requirement), value: decision)
        in _expected.entries) {
      test('${requirement.name} when ${state.name} → ${decision.name}', () {
        expect(
          decideAuth(
            requirement,
            loggedIn: state != _State.loggedOut,
            browseAsLoggedIn: state != _State.loggedInOff,
          ),
          decision,
        );
      });
    }
  });

  group('the auth interceptor injects only by the decision', () {
    for (final MapEntry(key: (state, requirement), value: decision)
        in _expected.entries) {
      test('${requirement.name} when ${state.name}', () async {
        final harness = Harness(
          (_) => reply(200),
          credentials: FakeCredentials(
            headers: state == _State.loggedOut ? null : _credential,
            browseAsLoggedInValue: state != _State.loggedInOff,
          ),
        );
        final send = harness.get('https://example.test/a', auth: requirement);

        switch (decision) {
          case AuthDecision.refuse:
            final error = await send.then<Object?>(
              (_) => null,
              onError: (Object error) => error,
            );
            expect(error, isA<AuthRequired>());
            expect((error! as AuthRequired).pluginId, pluginId);
            // 不發請求。
            expect(harness.adapter.requests, isEmpty);
          case AuthDecision.attach:
            await send;
            expect(
              harness.adapter.requests.single.headers['authorization'],
              'Bearer FAKE_TOKEN_123',
            );
          case AuthDecision.omit:
            await send;
            expect(
              harness.adapter.requests.single.headers['authorization'],
              isNull,
            );
        }
        final record = harness.records.single;
        expect(record.fields['credentials'], decision == AuthDecision.attach);
      });
    }
  });

  test('M1 has no credentials: nothing is attached', () async {
    final harness = Harness((_) => reply(200));
    await harness.get(
      'https://example.test/a',
      auth: AuthRequirement.userPreference,
    );
    expect(harness.adapter.requests.single.headers['authorization'], isNull);
    await expectLater(
      harness.get('https://example.test/a', auth: AuthRequirement.required),
      throwsA(isA<AuthRequired>()),
    );
  });
}
