import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upi_split/kirana/kirana_root.dart';
import 'package:web/web.dart' as web;

import 'firebase_options.dart';

/// Kirana Mitra Shop as a web app, for iPhones and any phone without the
/// Android app. Added to the home screen from Safari, it opens full screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(KiranaRoot(prefs: prefs, options: kiranaWebOptions));
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => web.document.getElementById('loading')?.remove(),
  );
}
