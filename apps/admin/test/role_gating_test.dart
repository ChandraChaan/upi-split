import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_admin/router.dart';
import 'package:kirana_core/kirana_core.dart';

import 'test_helpers.dart';

void main() {
  group('adminRedirect', () {
    String? go(SessionStage stage, String path, [MemberRole? role]) =>
        adminRedirect(stage: stage, role: role, path: path);

    test('loading holds the current URL', () {
      expect(go(SessionStage.loading, '/customers'), isNull);
    });

    test('signed out can only reach the sign-in pages', () {
      expect(go(SessionStage.signedOut, '/dashboard'), '/sign-in');
      expect(go(SessionStage.signedOut, '/forgot-password'), isNull);
    });

    test('onboarding and deactivated are forced', () {
      expect(go(SessionStage.needsOnboarding, '/dashboard'), '/onboarding');
      expect(go(SessionStage.deactivated, '/reports'), '/deactivated');
    });

    test('a cashier is confined to the use-the-app page', () {
      expect(go(SessionStage.ready, '/dashboard', MemberRole.cashier), '/cashier');
      expect(go(SessionStage.ready, '/reports', MemberRole.cashier), '/cashier');
      expect(go(SessionStage.ready, '/cashier', MemberRole.cashier), isNull);
    });

    test('a manager cannot open the stores page', () {
      expect(go(SessionStage.ready, '/stores', MemberRole.manager), '/dashboard');
      expect(go(SessionStage.ready, '/staff', MemberRole.manager), isNull);
    });

    test('an owner goes from auth pages to the dashboard', () {
      expect(go(SessionStage.ready, '/sign-in', MemberRole.owner), '/dashboard');
      expect(go(SessionStage.ready, '/stores', MemberRole.owner), isNull);
    });
  });

  group('app', () {
    testWidgets('a cashier sees the mobile-app message and can sign out', (tester) async {
      useViewport(tester, 1280, 800);
      final harness = await buildHarness(role: MemberRole.cashier);
      await pumpApp(tester, harness);

      expect(find.text('Please use the mobile app'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Sign out'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(harness.session.stage, SessionStage.signedOut);
      expect(find.text('Forgot password?'), findsOneWidget);
    });

    testWidgets('a manager sees only assigned stores and no Stores link', (tester) async {
      useViewport(tester, 1280, 1000);
      final harness = await buildHarness(
        role: MemberRole.manager,
        storeIds: const ['s1'],
        seed: (db) async {
          await seedSales(db, 's1');
          await seedSales(db, 's2', sales: 999900);
        },
      );
      await pumpApp(tester, harness);

      expect(harness.session.stores.map((s) => s.id), ['s1']);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Stores'), findsNothing);
      expect(find.text('₹1,500'), findsWidgets);
      expect(find.text('₹9,999'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an owner gets the Stores link', (tester) async {
      useViewport(tester, 1280, 1000);
      final harness = await buildHarness(role: MemberRole.owner);
      await pumpApp(tester, harness);
      expect(find.text('Stores'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a deactivated member sees that state', (tester) async {
      useViewport(tester, 1280, 800);
      final harness = await buildHarness(role: MemberRole.manager, active: false);
      await pumpApp(tester, harness);
      expect(find.text('Account deactivated'), findsOneWidget);
    });

    testWidgets('signed out lands on the sign-in page', (tester) async {
      useViewport(tester, 1280, 800);
      final harness = await buildHarness(role: MemberRole.owner, signedIn: false);
      await pumpApp(tester, harness);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(FirebaseAuth, isNotNull);
    });

    testWidgets('the sign-in page can switch language', (tester) async {
      useViewport(tester, 1280, 800);
      final harness = await buildHarness(role: MemberRole.owner, signedIn: false);
      await pumpApp(tester, harness);
      await tester.tap(find.text('తెలుగు'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(harness.session.language, 'te');
      expect(find.text('లాగిన్'), findsWidgets);
    });
  });
}
