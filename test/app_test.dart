import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upi_split/split/pay_request.dart';
import 'package:upi_split/split/split_controller.dart';
import 'package:upi_split/ui/home_page.dart';
import 'package:upi_split/ui/pay_page.dart';

Future<Widget> app(Widget home, {Map<String, Object> saved = const {}}) async {
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [preferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(home: home),
  );
}

void main() {
  testWidgets('splits a bill and lists who owes what', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app(const HomePage()));

    expect(find.text('Add your UPI ID to send requests.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('my-name')), 'Chandra');
    await tester.enterText(find.byKey(const Key('my-vpa')), 'chandra@okicici');
    await tester.enterText(find.byKey(const Key('total')), '2400');
    for (final name in ['Ravi', 'Sita', 'Arjun']) {
      await tester.enterText(find.byKey(const Key('friend-name')), name);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    expect(
      find.text('You get back ₹1,800 from 3 friends · your share ₹600'),
      findsOneWidget,
    );
    expect(find.text('Ravi · ₹600'), findsOneWidget);

    // Paid for others only: the whole bill is split between friends.
    await tester.tap(find.text('I had a share too'));
    await tester.pump();
    expect(find.text('You get back ₹2,400 from 3 friends'), findsOneWidget);

    // Mark one as paid.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('1 of 3 paid'), findsOneWidget);
  });

  testWidgets('remembers your UPI ID and the bill', (tester) async {
    await tester.pumpWidget(await app(const HomePage()));
    await tester.enterText(find.byKey(const Key('my-vpa')), 'chandra@okicici');
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('my_vpa'), 'chandra@okicici');
  });

  testWidgets('flags an invalid UPI ID', (tester) async {
    await tester.pumpWidget(await app(const HomePage()));
    await tester.enterText(find.byKey(const Key('my-vpa')), 'chandra');
    await tester.pump();
    expect(find.text('Check the UPI ID (name@bank)'), findsOneWidget);
  });

  testWidgets('pay page shows the amount and who to pay', (tester) async {
    const request = PayRequest(
      payeeVpa: 'chandra@okicici',
      payeeName: 'Chandra',
      amountPaise: 61250,
      note: 'Dinner',
      friendName: 'Ravi',
    );
    await tester.pumpWidget(await app(const PayPage(request: request)));
    expect(find.text('Ravi, your share'), findsOneWidget);
    expect(find.text('₹612.50'), findsOneWidget);
    expect(find.text('to Chandra'), findsOneWidget);
    expect(find.text('Pay with a UPI app'), findsOneWidget);
  });

  testWidgets('pay page explains a broken link', (tester) async {
    await tester.pumpWidget(await app(const PayPage(request: null)));
    expect(find.text('This payment link is incomplete'), findsOneWidget);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      await app(
        const HomePage(),
        saved: {
          'my_name': 'Chandra',
          'my_vpa': 'chandra@okicici',
          'bill':
              '{"title":"Dinner","totalPaise":240000,"friends":[{"id":"1","name":"Ravi"},{"id":"2","name":"Sita"}]}',
        },
      ),
    );
    await tester.pump();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('fits a small phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      await app(
        const HomePage(),
        saved: {
          'my_vpa': 'chandra@okicici',
          'bill':
              '{"totalPaise":240000,"friends":[{"id":"1","name":"Ravi Kumar Reddy"}]}',
        },
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      await app(
        const PayPage(
          request: PayRequest(
            payeeVpa: 'chandra@okicici',
            payeeName: 'Chandra ObulaReddy',
            amountPaise: 12345650,
            friendName: 'Ravi',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
