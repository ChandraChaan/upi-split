import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Build with --dart-define=USE_EMULATOR=true for local work. Emulator builds
/// use a demo project and a fake key so they can never reach production.
const bool useFirebaseEmulator = bool.fromEnvironment('USE_EMULATOR');
const String _emulatorHostOverride = String.fromEnvironment('EMULATOR_HOST');

const FirebaseOptions _emulatorOptions = FirebaseOptions(
  apiKey: 'fake-api-key-emulator-only',
  appId: '1:000000000000:web:0000000000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-kirana',
);

/// Initialises Firebase with unlimited offline persistence.
Future<void> initKiranaFirebase(FirebaseOptions productionOptions) async {
  await Firebase.initializeApp(
    options: useFirebaseEmulator ? _emulatorOptions : productionOptions,
  );
  final db = FirebaseFirestore.instance;
  db.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  if (useFirebaseEmulator) {
    final host = _emulatorHostOverride.isNotEmpty
        ? _emulatorHostOverride
        : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? '10.0.2.2'
            : 'localhost');
    db.useFirestoreEmulator(host, 8080);
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  }
}
