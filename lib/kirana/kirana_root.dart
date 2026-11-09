import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'strings.dart';

const bool shopAvailable = true;

Widget buildShop(SharedPreferences prefs, VoidCallback onExit) =>
    KiranaRoot(prefs: prefs, onExit: onExit);

class _ShopServices {
  const _ShopServices(this.session, this.sync);

  final SessionController session;
  final SyncMonitor sync;
}

/// Started once and kept, so queued sales keep syncing after the user goes
/// back to bill splitting. Firebase stays untouched until the shop is opened.
Future<_ShopServices>? _services;

Future<_ShopServices> _start(SharedPreferences prefs) async {
  Tr.register(en: mobileEn, te: mobileTe);
  await initializeDateFormatting();
  await initKiranaFirebase(kiranaMobileOptions);
  await _chooseFirstLanguage(prefs);

  final db = FirebaseFirestore.instance;
  final sync = SyncMonitor(db);
  final session = SessionController(
    auth: FirebaseAuth.instance,
    db: db,
    prefs: prefs,
    sync: sync,
  );
  return _ShopServices(session, sync);
}

/// The session defaults to Telugu, and the sign-in screen has no language
/// switch, so people arriving from the English UPI Split follow their device.
Future<void> _chooseFirstLanguage(SharedPreferences prefs) async {
  const key = 'language';
  if (prefs.containsKey(key)) return;
  final device = PlatformDispatcher.instance.locale.languageCode;
  await prefs.setString(key, device == 'te' ? 'te' : 'en');
}

class KiranaRoot extends StatefulWidget {
  const KiranaRoot({super.key, required this.prefs, required this.onExit});

  final SharedPreferences prefs;
  final VoidCallback onExit;

  @override
  State<KiranaRoot> createState() => _KiranaRootState();
}

class _KiranaRootState extends State<KiranaRoot> {
  late Future<_ShopServices> _ready = _services ??= _start(widget.prefs);

  void _retry() {
    setState(() => _ready = _services = _start(widget.prefs));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ShopServices>(
      future: _ready,
      builder: (context, snapshot) {
        final services = snapshot.data;
        if (services != null) {
          return KiranaApp(
            session: services.session,
            sync: services.sync,
            onExit: widget.onExit,
          );
        }
        if (snapshot.hasError) {
          return _StartupFailed(onRetry: _retry, onExit: widget.onExit);
        }
        return const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }
}

class _StartupFailed extends StatelessWidget {
  const _StartupFailed({required this.onRetry, required this.onExit});

  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('The shop could not start.'),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
              TextButton(
                onPressed: onExit,
                child: const Text('Back to UPI Split'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
