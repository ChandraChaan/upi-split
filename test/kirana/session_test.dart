import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:upi_split/kirana/screens/auth_screen.dart';
import 'package:upi_split/kirana/screens/onboarding_screen.dart';
import 'package:upi_split/kirana/screens/receipt_screen.dart';
import 'package:upi_split/kirana/screens/reminders_screen.dart';
import 'package:upi_split/kirana/screens/shell.dart';
import 'package:upi_split/kirana/screens/status_screens.dart';

import 'support/harness.dart';

class _WrongPasswordAuth extends MockFirebaseAuth {
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    throw FirebaseAuthException(code: 'wrong-password');
  }
}

void main() {
  setUpAll(setUpStrings);

  Future<void> sellOneSoap(WidgetTester t, Harness h) async {
    await h.itemBilling();
    await t.tap(find.byKey(const ValueKey('product_soap')));
    await settle(t);
    await t.tap(find.byKey(const Key('billing_checkout')));
    await settle(t);
    await t.tap(find.byKey(const Key('checkout_save')));
    await settle(t);
  }

  group('writes never wait for the server', () {
    testWidgets('the receipt shows while the commit is still pending', (
      t,
    ) async {
      final h = await pumpApp(t);
      final never = Completer<void>();
      h.db.commitOutcome = () => never.future;

      await sellOneSoap(t, h);

      expect(find.byType(ReceiptView), findsOneWidget);
      expect(h.sync.pendingWrites, 1);
      expect(
        find.descendant(
          of: find.byKey(const Key('sync_badge')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a server rejection reaches the user wherever they are', (
      t,
    ) async {
      final h = await pumpApp(t);
      h.db.commitOutcome = () async {
        throw FirebaseException(plugin: 'firestore', code: 'permission-denied');
      };

      await sellOneSoap(t, h);

      expect(find.text('The server rejected a change: bill'), findsOneWidget);
    });
  });

  group('session stages', () {
    testWidgets('a new user lands on onboarding and can create a business', (
      t,
    ) async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u2', email: 'new@example.com'),
      );
      final h = await pumpApp(t, auth: auth);
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await t.tap(find.text('Start a new shop').last);
      await settle(t);
      expect(find.text('Required'), findsNWidgets(3));

      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), 'Padma');
      await t.enterText(fields.at(1), 'Padma Stores');
      await t.enterText(fields.at(2), 'Main Branch');
      await t.tap(find.text('Start a new shop').last);
      await settle(t);

      expect(find.byType(Shell), findsOneWidget);
      expect(h.session.store!.name, 'Main Branch');
      expect(h.session.member!.role, MemberRole.owner);
    });

    testWidgets('a bad invite code gets a clear message', (t) async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u2', email: 'new@example.com'),
      );
      await pumpApp(t, auth: auth);
      await t.tap(find.text('Join with a code').first);
      await settle(t);
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), 'Padma');
      await t.enterText(fields.at(1), 'ABCDEFGH');
      await t.tap(find.text('Join with a code').last);
      await settle(t);
      expect(find.text('That code is not valid'), findsOneWidget);
    });

    testWidgets('a deactivated member is told so', (t) async {
      await pumpApp(
        t,
        beforeStart: (db) async {
          await db.doc('$businessPath/members/u1').update({'active': false});
        },
      );
      expect(find.byType(DeactivatedScreen), findsOneWidget);
    });

    testWidgets('a member with no store is told so', (t) async {
      await pumpApp(
        t,
        role: MemberRole.cashier,
        beforeStart: (db) async {
          await db.doc('$businessPath/members/u1').update({
            'storeIds': <String>[],
          });
        },
      );
      expect(find.byType(NoStoreScreen), findsOneWidget);
    });

    testWidgets('signing out from a deep screen returns to sign in', (t) async {
      final h = await pumpApp(t);
      await h.tab('More');
      await t.tap(find.byKey(const Key('more_settings')));
      await settle(t);
      await t.tap(find.byKey(const Key('sign_out')));
      await settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await settle(t);
      expect(find.byType(AuthScreen), findsOneWidget);
    });
  });

  group('sign in', () {
    testWidgets('defaults to Telugu and the visible switch changes language', (
      t,
    ) async {
      await pumpApp(t, signedIn: false, language: 'te');
      expect(find.text('కిరాణా మిత్ర'), findsOneWidget);
      await t.tap(find.text('English'));
      await settle(t);
      expect(find.text('Kirana Mitra'), findsOneWidget);
    });

    testWidgets('Firebase errors read as plain words in the chosen language', (
      t,
    ) async {
      await pumpApp(
        t,
        signedIn: false,
        language: 'te',
        auth: _WrongPasswordAuth(),
      );
      await t.enterText(find.byKey(const Key('auth_email')), 'a@b.co');
      await t.enterText(find.byKey(const Key('auth_password')), 'secret1');
      await t.tap(find.byKey(const Key('auth_submit')));
      await settle(t);
      expect(find.text('ఈమెయిల్ లేదా పాస్‌వర్డ్ తప్పు'), findsOneWidget);
    });
  });

  group('platform hand-offs', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

    tearDown(() {
      messenger.setMockMethodCallHandler(urlChannel, null);
      messenger.setMockMethodCallHandler(pathChannel, null);
      messenger.setMockMethodCallHandler(shareChannel, null);
    });

    testWidgets('a WhatsApp reminder opens wa.me and is logged', (t) async {
      final launched = <String>[];
      messenger.setMockMethodCallHandler(urlChannel, (call) async {
        launched.add((call.arguments as Map)['url'] as String);
        return true;
      });
      final h = await pumpApp(t);
      await h.open(const RemindersScreen());

      await t.tap(find.byKey(const ValueKey('whatsapp_c1')));
      await settle(t);

      expect(launched.single, startsWith('https://wa.me/919876500001?text='));
      expect(
        Uri.parse(launched.single).queryParameters['text'],
        contains('lakshmi@upi'),
      );
      final reminder = (await h.collection('reminders')).single;
      expect(reminder['channel'], 'whatsapp');
      expect((await h.doc('customers/c1'))['lastReminderAt'], isA<Timestamp>());
    });

    testWidgets(
      'an invalid phone number gets a message and nothing is logged',
      (t) async {
        final h = await pumpApp(
          t,
          beforeStart: (db) async {
            await db.doc('$storePath/customers/c2').update({
              'balancePaise': 5000,
            });
          },
        );
        await h.open(const RemindersScreen());

        await t.tap(find.byKey(const ValueKey('sms_c2')));
        await settle(t);

        expect(
          find.text(
            'The phone number is not valid. Fix it in the customer details.',
          ),
          findsOneWidget,
        );
        expect(await h.collection('reminders'), isEmpty);
      },
    );

    testWidgets('sharing the receipt writes a real PNG and hands it over', (
      t,
    ) async {
      final dir = Directory.systemTemp.createTempSync('kirana_receipt_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final shared = <Map<dynamic, dynamic>>[];
      messenger.setMockMethodCallHandler(pathChannel, (_) async => dir.path);
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        shared.add(call.arguments as Map);
        return 'dev.fluttercommunity.plus/share/success';
      });
      final h = await pumpApp(t);
      await sellOneSoap(t, h);

      await t.tap(find.byKey(const Key('share_image')));
      // Image encoding and file writes finish on real time, and their
      // continuations only run when the test zone is pumped.
      for (var i = 0; i < 40 && shared.isEmpty; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump();
      }

      expect(
        shared,
        hasLength(1),
        reason: 'share_plus should receive the file',
      );
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();
      expect(files, hasLength(1));
      final bytes = files.single.readAsBytesSync();
      expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
      expect(bytes.length, greaterThan(1000));
    });
  });
}
