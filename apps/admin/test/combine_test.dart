import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_admin/utils/combine.dart';
import 'package:kirana_admin/utils/rollups.dart';
import 'package:kirana_core/kirana_core.dart';

void main() {
  group('combineLatestMap', () {
    test('waits for every source, then emits on each change', () async {
      final a = StreamController<int>();
      final b = StreamController<int>();
      final out = <Map<String, int>>[];
      final sub = combineLatestMap<String, int>({'a': a.stream, 'b': b.stream}).listen(out.add);
      a.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(out, isEmpty);
      b.add(2);
      await Future<void>.delayed(Duration.zero);
      a.add(3);
      await Future<void>.delayed(Duration.zero);
      expect(out, [
        {'a': 1, 'b': 2},
        {'a': 3, 'b': 2},
      ]);
      await sub.cancel();
    });

    test('an empty input emits an empty map', () async {
      expect(await combineLatestMap<String, int>({}).first, isEmpty);
    });

    test('forwards errors and cancels its sources', () async {
      var cancelled = false;
      final a = StreamController<int>(onCancel: () => cancelled = true);
      final errors = <Object>[];
      final sub = combineLatestMap<String, int>({'a': a.stream}).listen((_) {}, onError: errors.add);
      a.addError('boom');
      await Future<void>.delayed(Duration.zero);
      expect(errors, ['boom']);
      await sub.cancel();
      expect(cancelled, isTrue);
    });
  });

  group('dues ageing', () {
    final now = DateTime(2026, 11, 9, 15);
    Customer due(DateTime? date, [int balance = 1000]) =>
        Customer(id: 'c', name: 'c', balancePaise: balance, dueDate: date);

    test('buckets by calendar days past due', () {
      expect(ageBucket(due(null), now), AgeBucket.noDueDate);
      expect(ageBucket(due(DateTime(2026, 11, 9, 23, 59)), now), AgeBucket.notYetDue);
      expect(ageBucket(due(DateTime(2026, 11, 8)), now), AgeBucket.days1to30);
      expect(ageBucket(due(DateTime(2026, 10, 10)), now), AgeBucket.days1to30);
      expect(ageBucket(due(DateTime(2026, 10, 9)), now), AgeBucket.days31to60);
      expect(ageBucket(due(DateTime(2026, 8, 11)), now), AgeBucket.days61to90);
      expect(ageBucket(due(DateTime(2026, 8, 10)), now), AgeBucket.over90);
    });

    test('totals ignore advances and archived customers', () {
      final totals = duesAgeing([
        due(null),
        due(null, -500),
        Customer(id: 'x', name: 'x', balancePaise: 900, archived: true),
        due(DateTime(2026, 11, 1), 700),
      ], now);
      expect(totals[AgeBucket.noDueDate], 1000);
      expect(totals[AgeBucket.days1to30], 700);
    });
  });

  test('product sales join on name across stores', () {
    const days = {
      's1': [
        DayRollup(dayKey: 'd', items: {'p1': DayItem(qtyMilli: 1000, revenuePaise: 100, cogsPaise: 60)}),
      ],
      's2': [
        DayRollup(dayKey: 'd', items: {'q9': DayItem(qtyMilli: 2000, revenuePaise: 300, cogsPaise: 100)}),
      ],
    };
    const products = {
      's1': [Product(id: 'p1', name: 'Soap')],
      's2': [Product(id: 'q9', name: 'soap')],
    };
    final rows = aggregateProductSales(days, products, 'en');
    expect(rows.length, 1);
    expect(rows.single.revenuePaise, 400);
    expect(rows.single.qtyMilli, 3000);
    expect(rows.single.marginPercent, 60);
  });
}
