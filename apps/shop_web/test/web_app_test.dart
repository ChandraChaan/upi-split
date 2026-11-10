import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_shop_web/firebase_options.dart';

/// Guards what makes "Add to Home Screen" on an iPhone open a full-screen
/// app with the right icon, and what keeps it on the production project.
void main() {
  test('the manifest opens full screen with its own icons', () {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(manifest['display'], 'standalone');
    expect(manifest['start_url'], '.');
    expect(manifest['scope'], '.');
    for (final icon in manifest['icons'] as List) {
      final src = (icon as Map)['src'] as String;
      expect(File('web/$src').existsSync(), isTrue, reason: src);
    }
  });

  test('Safari gets its home-screen icon and title', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains(r'<base href="$FLUTTER_BASE_HREF">'));
    expect(html, contains('apple-mobile-web-app-capable'));
    expect(html, contains('apple-mobile-web-app-title'));
    final icon = RegExp(
      r'rel="apple-touch-icon" href="([^"]+)"',
    ).firstMatch(html)!.group(1)!;
    expect(File('web/$icon').existsSync(), isTrue);
  });

  test('it signs in to the same project as the Android app', () {
    expect(kiranaWebOptions.projectId, 'kirana-mitra-chandra');
    expect(kiranaWebOptions.authDomain, 'kirana-mitra-chandra.firebaseapp.com');
  });
}
