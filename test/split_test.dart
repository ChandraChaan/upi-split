import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:upi_split/split/pay_request.dart';
import 'package:upi_split/split/split.dart';

Friend friend(String id, {int shares = 1, int custom = 0}) =>
    Friend(id: id, name: id, shares: shares, customPaise: custom);

void main() {
  group('allocate', () {
    test('splits evenly when it can', () {
      expect(allocate(1000, [1, 1, 1, 1]), [250, 250, 250, 250]);
    });

    test('never loses or invents a paisa', () {
      expect(allocate(100, [1, 1, 1]), [34, 33, 33]);
      expect(allocate(1, [1, 1, 1]), [1, 0, 0]);
      final random = Random(7);
      for (var i = 0; i < 500; i++) {
        final total = random.nextInt(10000000);
        final weights = List.generate(
          1 + random.nextInt(12),
          (_) => random.nextInt(5),
        );
        final parts = allocate(total, weights);
        final weightSum = weights.fold(0, (a, b) => a + b);
        expect(parts.fold(0, (a, b) => a + b), weightSum == 0 ? 0 : total);
        for (var j = 0; j < weights.length; j++) {
          if (weightSum == 0) continue;
          final exact = total * weights[j] / weightSum;
          expect(
            (parts[j] - exact).abs(),
            lessThan(1),
            reason: '$total $weights',
          );
        }
      }
    });

    test('respects weights', () {
      expect(allocate(1500, [2, 1]), [1000, 500]);
    });

    test('handles nobody sharing', () {
      expect(allocate(1000, [0, 0]), [0, 0]);
      expect(allocate(1000, []), isEmpty);
    });

    test('rejects negatives', () {
      expect(() => allocate(-1, [1]), throwsArgumentError);
      expect(() => allocate(1, [-1]), throwsArgumentError);
    });
  });

  group('split', () {
    test('equal split including me', () {
      final result = split(
        Bill(
          totalPaise: 240000,
          friends: [friend('a'), friend('b'), friend('c')],
        ),
      );
      expect(result.perFriend, {'a': 60000, 'b': 60000, 'c': 60000});
      expect(result.myPaise, 60000);
      expect(result.owedToMePaise, 180000);
    });

    test('odd paise go to friends, not to me', () {
      final result = split(
        Bill(totalPaise: 1000, friends: [friend('a'), friend('b')]),
      );
      expect(result.perFriend, {'a': 334, 'b': 333});
      expect(result.myPaise, 333);
    });

    test('paid for others only', () {
      final result = split(
        Bill(
          totalPaise: 90000,
          includeMe: false,
          friends: [friend('a'), friend('b')],
        ),
      );
      expect(result.perFriend, {'a': 45000, 'b': 45000});
      expect(result.myPaise, 0);
    });

    test('shares, with a couple counting as two', () {
      final result = split(
        Bill(
          totalPaise: 400000,
          mode: SplitMode.shares,
          myShares: 1,
          friends: [friend('couple', shares: 2), friend('solo')],
        ),
      );
      expect(result.perFriend, {'couple': 200000, 'solo': 100000});
      expect(result.myPaise, 100000);
    });

    test('typed amounts with the rest left to me', () {
      final result = split(
        Bill(
          totalPaise: 100000,
          mode: SplitMode.amounts,
          friends: [friend('a', custom: 30000), friend('b', custom: 45000)],
        ),
      );
      expect(result.perFriend, {'a': 30000, 'b': 45000});
      expect(result.myPaise, 25000);
      expect(result.unassignedPaise, 25000);
    });

    test('typed amounts that add up to more than the bill', () {
      final result = split(
        Bill(
          totalPaise: 10000,
          mode: SplitMode.amounts,
          friends: [friend('a', custom: 8000), friend('b', custom: 5000)],
        ),
      );
      expect(result.unassignedPaise, -3000);
      expect(result.myPaise, 0);
    });

    test('a bill survives a JSON round trip', () {
      final bill = Bill(
        title: 'Dinner',
        totalPaise: 245000,
        mode: SplitMode.shares,
        includeMe: false,
        myShares: 2,
        friends: [friend('a', shares: 3, custom: 10).copyWith(paid: true)],
      );
      final copy = Bill.fromJson(bill.toJson());
      expect(copy.toJson(), bill.toJson());
      expect(copy.friends.single.paid, isTrue);
    });
  });

  group('PayRequest', () {
    const request = PayRequest(
      payeeVpa: 'chandra@okicici',
      payeeName: 'Chandra',
      amountPaise: 61250,
      note: 'Dinner at Meghana\'s & dessert',
      friendName: 'Ravi Kumar',
    );

    test('share URL round-trips through the fragment', () {
      final url = request.shareUrl();
      expect(
        url,
        startsWith(
          'https://chandrachaan.github.io/upi-split/#/pay?pa=chandra%40okicici',
        ),
      );
      final fragment = Uri.parse(url).fragment;
      expect(PayRequest.fromFragment(fragment), request);
      expect(PayRequest.fromFragment('#$fragment'), request);
    });

    test('builds the UPI link with the amount and note', () {
      expect(
        request.upiLink.toLink(),
        'upi://pay?pa=chandra@okicici&pn=Chandra&tn=Dinner%20at%20Meghana%27s%20%26%20dessert&am=612.50&cu=INR',
      );
    });

    test('rejects broken or missing details', () {
      for (final bad in [
        '',
        '/settings',
        '/pay?pa=not-a-vpa&am=10',
        '/pay?pa=a1@ybl',
        '/pay?pa=a1@ybl&am=0',
        '/pay?pa=a1@ybl&am=1,000',
        '/pay?pa=a1@ybl&am=%E0%A4',
      ]) {
        expect(PayRequest.fromFragment(bad), isNull, reason: bad);
      }
    });

    test('message is ready to paste into WhatsApp', () {
      expect(
        messageFor(request),
        startsWith(
          "Hi Ravi Kumar, your share for Dinner at Meghana's & dessert is ₹612.50. "
          'Pay Chandra with any UPI app here: https://chandrachaan.github.io/upi-split/#/pay?',
        ),
      );
    });
  });

  test('formats rupees with Indian grouping', () {
    expect(formatRupees(0), '₹0');
    expect(formatRupees(61250), '₹612.50');
    expect(formatRupees(100000), '₹1,000');
    expect(formatRupees(12345650), '₹1,23,456.50');
    expect(formatRupees(1000000000), '₹1,00,00,000');
  });
}
