import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'store_scope.dart';
import 'strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Tr.register(en: adminEn, te: adminTe);
  await initKiranaFirebase(kiranaAdminOptions);
  final prefs = await SharedPreferences.getInstance();
  final db = FirebaseFirestore.instance;
  final sync = SyncMonitor(db);
  final session = SessionController(
    auth: FirebaseAuth.instance,
    db: db,
    prefs: prefs,
    sync: sync,
  );
  runApp(KiranaAdminApp(session: session, sync: sync, scope: StoreScope(prefs)));
}
