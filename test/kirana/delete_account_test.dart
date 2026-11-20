import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:upi_split/kirana/screens/settings_screen.dart';

import 'support/harness.dart';

// MockUser keeps mutable profile fields; this double only overrides one call.
// ignore: must_be_immutable
class _WrongPasswordUser extends MockUser {
  _WrongPasswordUser() : super(uid: 'u1', email: 'ravi@example.com');

  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential? credential,
  ) async {
    throw FirebaseAuthException(code: 'invalid-credential');
  }
}

void main() {
  setUpAll(setUpStrings);

  Future<void> deleteWithPassword(WidgetTester t, Harness h) async {
    await h.open(const SettingsScreen());
    await t.ensureVisible(find.byKey(const Key('delete_account')));
    await t.tap(find.byKey(const Key('delete_account')));
    await settle(t);
    await t.enterText(find.byKey(const Key('delete_password')), 'secret1');
    await t.tap(find.byKey(const Key('delete_confirm')));
    await settle(t);
    // The "Delete your account permanently?" dialog.
    await t.tap(find.widgetWithText(FilledButton, 'Delete account').last);
    await settle(t);
  }

  testWidgets('an owner deletes their login and flags the shop for erasure', (
    t,
  ) async {
    final h = await pumpApp(
      t,
      beforeStart: (db) => db.doc(businessPath).update({'ownerUid': 'u1'}),
    );

    await deleteWithPassword(t, h);

    final business = (await h.db.doc(businessPath).get()).data()!;
    expect(business['deletionRequestedBy'], 'u1');
    expect(business['deletionRequestedAt'], isNotNull);
    expect((await h.db.doc('users/u1').get()).exists, isFalse);
    expect(h.session.stage, SessionStage.signedOut);
  });

  testWidgets('a cashier deletes their login and the shop is left alone', (
    t,
  ) async {
    final h = await pumpApp(t, role: MemberRole.cashier);

    await deleteWithPassword(t, h);

    final business = (await h.db.doc(businessPath).get()).data()!;
    expect(business.containsKey('deletionRequestedAt'), isFalse);
    expect((await h.db.doc('users/u1').get()).exists, isFalse);
    expect(h.session.stage, SessionStage.signedOut);
  });

  testWidgets('a wrong password deletes nothing and says why', (t) async {
    final h = await pumpApp(
      t,
      auth: MockFirebaseAuth(signedIn: true, mockUser: _WrongPasswordUser()),
      beforeStart: (db) => db.doc(businessPath).update({'ownerUid': 'u1'}),
    );

    await deleteWithPassword(t, h);

    expect(find.text('Wrong email or password'), findsOneWidget);
    final business = (await h.db.doc(businessPath).get()).data()!;
    expect(business.containsKey('deletionRequestedAt'), isFalse);
    expect((await h.db.doc('users/u1').get()).exists, isTrue);
    expect(h.session.stage, SessionStage.ready);
  });

  testWidgets('settings links to the privacy policy', (t) async {
    final h = await pumpApp(t);
    await h.open(const SettingsScreen());
    expect(find.byKey(const Key('privacy_policy')), findsOneWidget);
    expect(privacyPolicyUrl, startsWith('https://'));
  });
}
