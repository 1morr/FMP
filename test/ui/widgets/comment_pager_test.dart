import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/video_detail.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/widgets/panels/comment_pager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LocaleSettings.setLocale(AppLocale.en));

  testWidgets('the page buttons are labelled and big enough to tap', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: CommentPager(
                title: 'Top Comments',
                comments: [_comment(1), _comment(2), _comment(3)],
              ),
            ),
          ),
        ),
      ),
    );

    // 以前是 InkWell 包 24dp 的 SizedBox：觸控區 24dp、沒有 tooltip。
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.tap(find.byTooltip(t.trackDetail.nextComment));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);

    handle.dispose();
  });
}

VideoComment _comment(int id) => VideoComment(
  id: id,
  content: 'comment $id',
  memberName: 'member $id',
  memberAvatar: '',
  likeCount: id,
  createTime: DateTime(2026, 9, 1),
);
