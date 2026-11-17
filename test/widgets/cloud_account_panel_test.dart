import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/services/spokenlog_cloud_service.dart';
import 'package:voice_transcriber/widgets/cloud_account_panel.dart';

void main() {
  CloudAccount account(int credit, int ads) => CloudAccount(
        creditSeconds: credit, adsToday: ads, adsDailyLimit: 2, adRewardSeconds: 600);

  testWidgets('signs in, shows cloud time and adds time from an ad', (tester) async {
    var signedIn = false;
    var credit = 600;
    var ads = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CloudAccountPanel(
          signIn: ({required interactive}) async {
            if (interactive) signedIn = true;
            return signedIn ? 'me@example.com' : null;
          },
          loadAccount: () async => account(credit, ads),
          signOut: () async => signedIn = false,
          watchAd: () async {
            credit += 600;
            ads += 1;
            return account(credit, ads);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cloud-sign-in')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cloud-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('남은 클라우드 시간 10분'), findsOneWidget);
    expect(find.text('오늘 0/2회'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cloud-watch-ad')));
    await tester.pumpAndSettle();
    expect(find.text('남은 클라우드 시간 20분'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cloud-watch-ad')));
    await tester.pumpAndSettle();
    final button = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('광고 보고 10분 받기'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
    expect(button.onPressed, isNull, reason: 'daily ad limit reached');

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cloud-sign-in')), findsOneWidget);
  });

  testWidgets('desktop explains that ads come from the phone app', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CloudAccountPanel(
          signIn: ({required interactive}) async => 'me@example.com',
          loadAccount: () async => account(0, 0),
          signOut: () async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cloud-watch-ad')), findsNothing);
    expect(find.textContaining('폰 앱에서 같은 Google 계정'), findsOneWidget);
  });
}
