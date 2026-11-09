import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Used by the web build, so the pay page ships without the shop or Firebase.
const bool shopAvailable = false;

Widget buildShop(SharedPreferences prefs, VoidCallback onExit) =>
    throw UnsupportedError('The shop is only available in the Android app.');
