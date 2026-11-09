import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_admin/strings.dart';
import 'package:kirana_admin/utils/product_import.dart';
import 'package:kirana_core/kirana_core.dart';

Set<String> placeholders(String text) =>
    RegExp(r'\{([a-zA-Z_]+)\}').allMatches(text).map((m) => m.group(1)!).toSet();

List<File> dartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  test('admin en and te have identical keys', () {
    expect(adminTe.keys.toSet().difference(adminEn.keys.toSet()), isEmpty);
    expect(adminEn.keys.toSet().difference(adminTe.keys.toSet()), isEmpty);
  });

  test('admin en and te have identical placeholders', () {
    final mismatched = <String>[];
    adminEn.forEach((key, en) {
      if (placeholders(en).length != placeholders(adminTe[key]!).length ||
          !placeholders(en).containsAll(placeholders(adminTe[key]!))) {
        mismatched.add(key);
      }
    });
    expect(mismatched, isEmpty);
  });

  test('no empty translations', () {
    expect(adminEn.entries.where((e) => e.value.trim().isEmpty), isEmpty);
    expect(adminTe.entries.where((e) => e.value.trim().isEmpty), isEmpty);
  });

  test('admin strings do not silently replace shared ones', () {
    expect(adminEn.keys.toSet().intersection(commonEn.keys.toSet()), isEmpty);
  });

  test('every key used in lib exists in both languages', () {
    Tr.register(en: adminEn, te: adminTe);
    final used = <String>{};
    final pattern = RegExp('\\btr\\(\\s*[\'"]([a-z0-9_]+)[\'"]');
    for (final file in dartFiles()) {
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        used.add(match.group(1)!);
      }
    }
    expect(used.length, greaterThan(100), reason: 'the scan should find the app\'s keys');
    used.addAll(importIssueKeys);
    used.addAll(productCsvHeaderKeys.values);
    final missing = used.where((k) => !Tr.english.containsKey(k) || !Tr.telugu.containsKey(k));
    expect(missing, isEmpty);
  });

  test('translation keys are never built at runtime', () {
    final offenders = <String>[];
    final pattern = RegExp(r'''\btr\(\s*['"][^'"]*\$''');
    for (final file in dartFiles()) {
      if (pattern.hasMatch(file.readAsStringSync())) offenders.add(file.path);
    }
    expect(offenders, isEmpty);
  });
}
