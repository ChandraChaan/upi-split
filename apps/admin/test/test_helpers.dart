import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_admin/app.dart';
import 'package:kirana_admin/store_scope.dart';
import 'package:kirana_admin/strings.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The fake lacks this one call, which SyncMonitor makes at construction.
class TestFirestore extends FakeFirebaseFirestore {
  @override
  Future<void> waitForPendingWrites() async {}
}

const businessId = 'b1';

class Harness {
  Harness(this.db, this.session, this.sync, this.scope);
  final TestFirestore db;
  final SessionController session;
  final SyncMonitor sync;
  final StoreScope scope;

  Widget get app => KiranaAdminApp(session: session, sync: sync, scope: scope);
}

/// A signed-in member of a two-store business.
Future<Harness> buildHarness({
  required MemberRole role,
  List<String> storeIds = const ['s1'],
  bool active = true,
  String language = 'en',
  bool signedIn = true,
  Future<void> Function(TestFirestore db)? seed,
}) async {
  Tr.register(en: adminEn, te: adminTe);
  SharedPreferences.setMockInitialValues({'language': language});
  final prefs = await SharedPreferences.getInstance();
  final db = TestFirestore();
  const uid = 'u1';
  await db.doc('users/$uid').set({'businessId': businessId});
  await db.doc('businesses/$businessId').set({'name': 'Lakshmi Traders', 'ownerUid': 'owner'});
  await db.doc('businesses/$businessId/members/$uid').set({
    'name': 'Ravi',
    'email': 'ravi@example.com',
    'role': role.name,
    'storeIds': storeIds,
    'active': active,
  });
  await db.doc('businesses/$businessId/stores/s1').set({'name': 'Main Road'});
  await db.doc('businesses/$businessId/stores/s2').set({'name': 'Market'});
  if (seed != null) await seed(db);
  final auth = MockFirebaseAuth(
    signedIn: signedIn,
    mockUser: MockUser(uid: uid, email: 'ravi@example.com'),
  );
  final sync = SyncMonitor(db, watchNetwork: false);
  final session = SessionController(auth: auth, db: db, prefs: prefs, sync: sync);
  return Harness(db, session, sync, StoreScope(prefs));
}

/// Pumps the app until streams have delivered and the session has settled.
Future<void> pumpApp(WidgetTester tester, Harness harness) async {
  await tester.pumpWidget(harness.app);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 1));
}

void useViewport(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Seeds today's sales in store [storeId].
Future<void> seedSales(
  FirebaseFirestore db,
  String storeId, {
  int sales = 150000,
  int cogs = 90000,
}) async {
  final store = db.doc('businesses/$businessId/stores/$storeId');
  await store.collection('days').doc(dayKey(DateTime.now())).set({
    'dayKey': dayKey(DateTime.now()),
    'salesPaise': sales,
    'cogsPaise': cogs,
    'billCount': 3,
    'cashSalesPaise': sales - 50000,
    'upiSalesPaise': 30000,
    'creditSalesPaise': 20000,
    'collectionCashPaise': 10000,
    'collectionUpiPaise': 5000,
    'expensePaise': 8000,
    'expenseCashPaise': 8000,
    'items': {
      'p1': {'q': 2000, 'r': 40000, 'c': 30000},
      'p2': {'q': 1000, 'r': 80000, 'c': 50000},
    },
  });
  await store.collection('products').doc('p1').set({
    'name': 'Toor Dal',
    'nameTe': 'కందిపప్పు',
    'pricePaise': 20000,
    'costPaise': 15000,
    'stockMilli': 1000,
    'lowStockMilli': 5000,
    'unit': 'kg',
    'active': true,
  });
  await store.collection('products').doc('p2').set({
    'name': 'Sunflower Oil',
    'pricePaise': 80000,
    'costPaise': 50000,
    'stockMilli': 10000,
    'unit': 'litre',
    'active': true,
  });
  await store.collection('customers').doc('c1').set({
    'name': 'Sita',
    'phone': '9876543210',
    'balancePaise': 45000,
    'archived': false,
  });
}
