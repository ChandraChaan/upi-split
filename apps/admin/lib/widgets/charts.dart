import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import 'common.dart';

/// Categorical slots, in fixed order, from the validated data-viz palette
/// (checked against this theme's card surface). Text never wears these.
const Color chartSlot1 = Color(0xFF2A78D6);
const Color chartSlot2 = Color(0xFFEB6834);
const Color chartSlot3 = Color(0xFF1BAF7A);

const double _rowHeight = 40;

/// Largest round axis value at or above [value]: 1, 2, 2.5, 5 or 10 times a power of ten.
double niceCeiling(double value) {
  if (value <= 0) return 1;
  final power = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
  for (final step in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (value <= step * power) return step * power;
  }
  return 10 * power;
}

/// Chart card with a switch to read the same numbers as a table.
class ChartCard extends StatefulWidget {
  const ChartCard({super.key, required this.title, required this.chart, required this.table});
  final String title;
  final Widget chart;
  final Widget table;
  @override
  State<ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<ChartCard> {
  bool _showTable = false;
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return SectionCard(
      title: widget.title,
      trailing: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: _showTable ? tr('show_chart') : tr('show_table'),
        icon: Icon(_showTable ? Icons.show_chart : Icons.table_rows_outlined, size: 20),
        onPressed: () => setState(() => _showTable = !_showTable),
      ),
      child: _showTable ? widget.table : widget.chart,
    );
  }
}

/// A small two-or-more column list for a chart's table view.
class ChartTable extends StatelessWidget {
  const ChartTable({super.key, required this.rows, this.maxHeight = 260});
  final List<List<String>> rows;
  final double maxHeight;
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    for (var i = 0; i < row.length; i++)
                      Expanded(
                        flex: i == 0 ? 3 : 2,
                        child: Text(row[i], style: style, textAlign: i == 0 ? TextAlign.start : TextAlign.end),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LegendEntry {
  const LegendEntry(this.color, this.label, {this.value});
  final Color color;
  final String label;
  final String? value;
}

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.entries});
  final List<LegendEntry> entries;
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final e in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(e.value == null ? e.label : '${e.label}  ${e.value}', style: style),
              ),
            ],
          ),
      ],
    );
  }
}

class TrendSeries {
  const TrendSeries(this.label, this.color, this.valuesPaise);
  final String label;
  final Color color;
  final List<int> valuesPaise;
}

/// Two or more rupee series against the same axis, over consecutive days.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.dayLabels, required this.series});
  final List<String> dayLabels;
  final List<TrendSeries> series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.bodySmall?.copyWith(color: muted, fontSize: 11);
    final all = series.expand((s) => s.valuesPaise).map((v) => v / 100);
    final top = niceCeiling(math.max(1, all.isEmpty ? 1 : all.reduce(math.max)));
    final lowest = all.isEmpty ? 0.0 : all.reduce(math.min);
    final bottom = lowest >= 0 ? 0.0 : -niceCeiling(-lowest);
    final interval = (top - bottom) / 4;
    final grid = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChartLegend(entries: [for (final s in series) LegendEntry(s.color, s.label)]),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              minY: bottom,
              maxY: top,
              minX: 0,
              maxX: math.max(1, dayLabels.length - 1).toDouble(),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 68,
                    interval: interval,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(formatRupees((value * 100).round()), style: labelStyle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      final last = dayLabels.length - 1;
                      // Weekly labels counted back from today, so the last
                      // label is always the latest day and none collide.
                      if (i < 0 || i > last || (last - i) % 7 != 0) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(dayLabels[i], style: labelStyle),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  maxContentWidth: 220,
                  getTooltipItems: (spots) => [
                    for (final spot in spots)
                      LineTooltipItem(
                        '${spot.barIndex == 0 ? '${dayLabels[spot.x.toInt()]}\n' : ''}'
                        '${series[spot.barIndex].label}: '
                        '${formatRupees(series[spot.barIndex].valuesPaise[spot.x.toInt()])}',
                        TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < s.valuesPaise.length; i++)
                        FlSpot(i.toDouble(), s.valuesPaise[i] / 100),
                    ],
                    color: s.color,
                    barWidth: 2,
                    isCurved: false,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class RankedValue {
  const RankedValue(this.label, this.paise);
  final String label;
  final int paise;
}

/// Horizontal bars with the name on the left and the amount on the right.
/// Bars are drawn by fl_chart; names are ordinary text so long ones can wrap.
class RankedBars extends StatelessWidget {
  const RankedBars({super.key, required this.items, this.color = chartSlot1});
  final List<RankedValue> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    final peak = items.map((e) => e.paise).fold<int>(1, math.max) / 100;
    final height = _rowHeight * items.length;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              children: [
                for (final item in items)
                  SizedBox(
                    height: _rowHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(item.label, style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: BarChart(
              BarChartData(
                rotationQuarterTurns: 1,
                alignment: BarChartAlignment.spaceAround,
                minY: 0,
                maxY: peak,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                      '${items[groupIndex].label}\n${formatRupees(items[groupIndex].paise)}',
                      TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < items.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: items[i].paise / 100,
                          color: color,
                          width: 14,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final item in items)
                  SizedBox(
                    height: _rowHeight,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(formatRupees(item.paise), style: style),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MixPart {
  const MixPart(this.label, this.color, this.paise);
  final String label;
  final Color color;
  final int paise;
}

/// One whole split into parts: a single segmented bar, with the amount and
/// share of each part listed beside its colour key.
class SegmentedMix extends StatelessWidget {
  const SegmentedMix({super.key, required this.parts});
  final List<MixPart> parts;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surfaceContainerLow;
    final total = parts.fold<int>(0, (t, p) => t + math.max(0, p.paise));
    var from = 0.0;
    final stack = <BarChartRodStackItem>[];
    for (final part in parts) {
      if (part.paise <= 0) continue;
      final to = from + part.paise / 100;
      stack.add(BarChartRodStackItem(
        from,
        to,
        part.color,
        borderSide: BorderSide(color: surface, width: 2),
      ));
      from = to;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 32,
          child: BarChart(
            BarChartData(
              rotationQuarterTurns: 1,
              alignment: BarChartAlignment.center,
              minY: 0,
              maxY: math.max(from, 1),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              barTouchData: BarTouchData(enabled: false),
              barGroups: [
                BarChartGroupData(
                  x: 0,
                  barRods: [
                    BarChartRodData(
                      toY: from,
                      width: 24,
                      borderRadius: BorderRadius.circular(4),
                      rodStackItems: stack,
                      color: Colors.transparent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: kGap),
        ChartLegend(entries: [
          for (final p in parts)
            LegendEntry(
              p.color,
              p.label,
              value: '${formatRupees(p.paise)} (${total == 0 ? 0 : (p.paise * 100 / total).round()}%)',
            ),
        ]),
      ],
    );
  }
}
