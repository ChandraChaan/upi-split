import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:upi_split/kirana/strings.dart';

Set<String> placeholders(String text) =>
    RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)!).toSet();

void main() {
  test('en and te maps have identical keys', () {
    expect(mobileTe.keys.toSet(), mobileEn.keys.toSet());
  });

  test('en and te strings use the same placeholders', () {
    final mismatched = [
      for (final key in mobileEn.keys)
        if (placeholders(mobileEn[key]!).length !=
                placeholders(mobileTe[key] ?? '').length ||
            !placeholders(
              mobileEn[key]!,
            ).containsAll(placeholders(mobileTe[key] ?? '')))
          key,
    ];
    expect(mismatched, isEmpty);
  });

  test('no translation is empty', () {
    expect(
      [
        ...mobileEn.entries,
        ...mobileTe.entries,
      ].where((e) => e.value.trim().isEmpty),
      isEmpty,
    );
  });

  test('every tr key used in lib/ exists in both languages', () {
    Tr.register(en: mobileEn, te: mobileTe);
    final keyPattern = RegExp(r'''\btr\(\s*['"]([^'"]+)['"]''');
    final missing = <String>[];
    var found = 0;
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final match in keyPattern.allMatches(file.readAsStringSync())) {
        found++;
        final key = match.group(1)!;
        if (!Tr.english.containsKey(key) || !Tr.telugu.containsKey(key)) {
          missing.add('${file.path}: $key');
        }
      }
    }
    expect(
      found,
      greaterThan(300),
      reason: 'The scan should see the whole app',
    );
    expect(missing, isEmpty);
  });

  test('tr keys are never built dynamically, so the scan sees them all', () {
    final dynamicKey = RegExp(r'''\btr\(\s*['"][^'"]*\$''');
    final offenders = [
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') &&
            dynamicKey.hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
