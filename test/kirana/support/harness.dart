import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upi_split/kirana/app.dart';
import 'package:upi_split/kirana/screens/shell.dart';
import 'package:upi_split/kirana/strings.dart';

const businessPath = 'businesses/b1';
const storePath = 'businesses/b1/stores/s1';

/// Lets a test decide what the server does with a commit.
class TestFirestore extends FakeFirebaseFirestore {
  Future<void> Function()? commitOutcome;

  @override
  Future<void> waitForPendingWrites() async {}

  @override
  WriteBatch batch() {
    final outcome = commitOutcome;
    return outcome == null
        ? super.batch()
        : _ScriptedBatch(super.batch(), outcome);
  }
}

class _ScriptedBatch implements WriteBatch {
  _ScriptedBatch(this._inner, this._outcome);
  final WriteBatch _inner;
  final Future<void> Function() _outcome;

  @override
  Future<void> commit() => _outcome();

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) =>
      _inner.set(document, data, options);

  @override
  void update<T>(DocumentReference<T> document, T data) =>
      _inner.update(document, data);

  @override
  void delete(DocumentReference<Object?> document) => _inner.delete(document);
}

class Harness {
  Harness(this.db, this.session, this.sync, this.tester);
  final TestFirestore db;
  final SessionController session;
  final SyncMonitor sync;
  final WidgetTester tester;

  Future<Map<String, dynamic>> doc(String relative) async =>
      (await db.doc('$storePath/$relative').get()).data() ?? {};

  Future<List<Map<String, dynamic>>> collection(String name) async =>
      (await db.collection('$storePath/$name').get()).docs
          .map((d) => d.data())
          .toList();

  /// Opens a screen above the shell, as a tile or button in the app would.
  Future<void> open(Widget screen) async {
    Navigator.of(
      tester.element(find.byType(Shell, skipOffstage: false)),
    ).push(MaterialPageRoute<void>(builder: (_) => screen)).ignore();
    await settle(tester);
  }

  Future<void> tab(String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await settle(tester);
  }
}

/// pumpAndSettle would never finish while a progress indicator is spinning.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> setUpStrings() async {
  Tr.register(en: mobileEn, te: mobileTe);
  await initializeDateFormatting();
}

Future<void> seed(FirebaseFirestore db, MemberRole role) async {
  await db.doc('users/u1').set({'businessId': 'b1'});
  await db.doc(businessPath).set({
    'name': 'Lakshmi Traders',
    'ownerUid': 'owner',
  });
  await db.doc('$businessPath/members/u1').set({
    'name': 'Ravi',
    'email': 'ravi@example.com',
    'role': role.name,
    'storeIds': ['s1'],
    'active': true,
  });
  await db
      .doc(storePath)
      .set(
        const Store(
          id: 's1',
          name: 'Lakshmi Kirana',
          address: 'Main Road, Guntur',
          phone: '9876543210',
          upiId: 'lakshmi@upi',
        ).toMap(),
      );
  final now = DateTime.now();
  Future<void> product(String id, Map<String, Object?> data) =>
      db.doc('$storePath/products/$id').set(data);
  await product('rice', {
    'name': 'Sona Rice',
    'nameTe': 'సోనా బియ్యం',
    'barcode': '8901000000011',
    'category': 'Grains',
    'unit': 'kg',
    'pricePaise': 6000,
    'costPaise': 5000,
    'stockMilli': 50000,
    'lowStockMilli': 5000,
    'active': true,
  });
  await product('soap', {
    'name': 'Lux Soap',
    'nameTe': 'లక్స్ సబ్బు',
    'barcode': '8901000000028',
    'category': 'Toiletries',
    'unit': 'piece',
    'pricePaise': 4000,
    'costPaise': 3200,
    'stockMilli': 10000,
    'lowStockMilli': 2000,
    'active': true,
  });
  await product('salt', {
    'name': 'Tata Salt',
    'nameTe': '',
    'barcode': '',
    'category': 'Grains',
    'unit': 'packet',
    'pricePaise': 2800,
    'costPaise': 2200,
    'stockMilli': -3000,
    'lowStockMilli': 0,
    'active': true,
  });
  await db.doc('$storePath/customers/c1').set({
    'name': 'Suresh',
    'phone': '9876500001',
    'address': '',
    'creditLimitPaise': 100000,
    'balancePaise': 80000,
    'dueDate': Timestamp.fromDate(now.subtract(const Duration(days: 2))),
    'archived': false,
  });
  await db.doc('$storePath/customers/c2').set({
    'name': 'Anitha',
    'phone': '123',
    'address': '',
    'creditLimitPaise': 0,
    'balancePaise': 0,
    'archived': false,
  });
  await db.doc('$storePath/suppliers/v1').set({
    'name': 'Sri Venkateswara Agencies',
    'phone': '9000000000',
    'address': '',
    'gstin': '',
    'balancePaise': 500000,
    'archived': false,
  });
  await db.doc('$storePath/days/${dayKey(now)}').set({
    'dayKey': dayKey(now),
    'salesPaise': 120000,
    'billCount': 3,
    'cogsPaise': 90000,
    'cashSalesPaise': 80000,
    'upiSalesPaise': 30000,
    'creditSalesPaise': 10000,
    'items': {
      'soap': {'q': 3000, 'r': 12000, 'c': 9600},
    },
  });
}

Future<Harness> pumpApp(
  WidgetTester tester, {
  MemberRole role = MemberRole.owner,
  String language = 'en',
  Size size = const Size(412, 915),
  bool signedIn = true,
  Future<void> Function(FirebaseFirestore db)? beforeStart,
  FirebaseAuth? auth,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({'language': language});
  final prefs = await SharedPreferences.getInstance();
  final db = TestFirestore();
  if (signedIn) await seed(db, role);
  await beforeStart?.call(db);
  final sync = SyncMonitor(db, watchNetwork: false);
  final session = SessionController(
    auth:
        auth ??
        MockFirebaseAuth(
          signedIn: signedIn,
          mockUser: MockUser(uid: 'u1', email: 'ravi@example.com'),
        ),
    db: db,
    prefs: prefs,
    sync: sync,
  );
  addTearDown(session.dispose);
  addTearDown(sync.dispose);

  await tester.pumpWidget(KiranaApp(session: session, sync: sync));
  await settle(tester);
  return Harness(db, session, sync, tester);
}
