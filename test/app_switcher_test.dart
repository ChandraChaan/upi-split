import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upi_split/app_switcher.dart';
import 'package:upi_split/split/split_controller.dart';

const _shopButton = Key('open-shop');

Widget _fakeShop(SharedPreferences prefs, VoidCallback onExit) => MaterialApp(
  home: Scaffold(
    body: TextButton(onPressed: onExit, child: const Text('Leave shop')),
  ),
);

Future<(Widget, SharedPreferences)> _app({
  Map<String, Object> saved = const {},
  bool enabled = true,
}) async {
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await SharedPreferences.getInstance();
  final widget = ProviderScope(
    overrides: [preferencesProvider.overrideWithValue(prefs)],
    child: AppSwitcher(prefs: prefs, enabled: enabled, shopBuilder: _fakeShop),
  );
  return (widget, prefs);
}

void main() {
  testWidgets('existing users still open on bill splitting', (tester) async {
    final (app, _) = await _app();
    await tester.pumpWidget(app);

    expect(find.text('UPI Split'), findsOneWidget);
    expect(find.text('Leave shop'), findsNothing);
  });

  testWidgets('opens the shop and comes back with the bill intact', (
    tester,
  ) async {
    final (app, prefs) = await _app();
    await tester.pumpWidget(app);
    await tester.enterText(find.byKey(const Key('total')), '2400');

    await tester.tap(find.byKey(_shopButton));
    await tester.pumpAndSettle();
    expect(find.text('Leave shop'), findsOneWidget);
    expect(prefs.getBool('open_in_shop'), isTrue);

    await tester.tap(find.text('Leave shop'));
    await tester.pumpAndSettle();
    expect(find.text('UPI Split'), findsOneWidget);
    expect(prefs.getBool('open_in_shop'), isFalse);
    expect(find.text('2400'), findsOneWidget);
  });

  testWidgets('a shopkeeper lands back in the shop', (tester) async {
    final (app, _) = await _app(saved: {'open_in_shop': true});
    await tester.pumpWidget(app);

    expect(find.text('Leave shop'), findsOneWidget);
  });

  testWidgets('the web build has no shop button and never opens the shop', (
    tester,
  ) async {
    final (app, _) = await _app(saved: {'open_in_shop': true}, enabled: false);
    await tester.pumpWidget(app);

    expect(find.byKey(_shopButton), findsNothing);
    expect(find.text('Leave shop'), findsNothing);
  });
}
