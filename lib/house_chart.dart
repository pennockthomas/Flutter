import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'house_models.dart';
import 'house_stats.dart';

/// How far back the graph looks.
enum ChartRange {
  week('7 days', 7),
  month('30 days', 30),
  all('All time', null);

  final String label;
  final int? days;

  const ChartRange(this.label, this.days);
}

/// One colour per member, in a fixed order so a person keeps theirs.
const List<Color> memberColors = [
  Color(0xFF69F0AE),
  Color(0xFF64B5F6),
  Color(0xFFFFB74D),
  Color(0xFFF06292),
  Color(0xFFBA68C8),
  Color(0xFFFFF176),
  Color(0xFF4DD0E1),
  Color(0xFFE57373),
];

/// First and last day shown for [range]: the last 7 or 30 days up to
/// [today], or from the earliest swap anyone ticked (at least a week).
({DateTime from, DateTime to}) chartSpan(
  List<HouseMember> members,
  ChartRange range, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final to = DateTime(now.year, now.month, now.day);
  final days = range.days;
  if (days != null) {
    return (from: DateTime(to.year, to.month, to.day - (days - 1)), to: to);
  }
  var from = DateTime(to.year, to.month, to.day - 6);
  for (final member in members) {
    for (final key in member.days.keys) {
      final parts = key.split('-').map(int.parse).toList();
      final day = DateTime(parts[0], parts[1], parts[2]);
      if (day.isBefore(from)) from = day;
    }
  }
  return (from: from, to: to);
}

/// Swaps done over time: one line per member, the running total per day.
class HouseChart extends StatelessWidget {
  const HouseChart({
    super.key,
    required this.members,
    required this.range,
    this.today,
  });

  /// In the order that decides each person's colour.
  final List<HouseMember> members;
  final ChartRange range;

  /// For tests: the day to treat as today.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final span = chartSpan(members, range, today: today);
    final lines = <LineChartBarData>[];
    var highest = 0;
    for (var i = 0; i < members.length; i++) {
      final series = cumulativeSeries(members[i], from: span.from, to: span.to);
      final color = memberColors[i % memberColors.length];
      for (final point in series) {
        if (point.total > highest) highest = point.total;
      }
      lines.add(
        LineChartBarData(
          spots: [
            for (var d = 0; d < series.length; d++)
              FlSpot(d.toDouble(), series[d].total.toDouble()),
          ],
          isCurved: false,
          color: color,
          barWidth: 3,
          dotData: FlDotData(show: series.length <= 14),
        ),
      );
    }
    final dayCount = span.to.difference(span.from).inDays;
    final top = (highest < 5 ? 5 : highest + (highest ~/ 10) + 1).toDouble();
    final labelEvery = dayCount <= 7 ? 1 : (dayCount / 5).ceil();

    return AspectRatio(
      aspectRatio: 1.5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: dayCount.toDouble(),
            minY: 0,
            maxY: top,
            lineBarsData: lines,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: Colors.white12, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  getTitlesWidget: (value, meta) {
                    if (value != value.roundToDouble()) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (value != index.toDouble() ||
                        index < 0 ||
                        index > dayCount ||
                        (dayCount - index) % labelEvery != 0) {
                      return const SizedBox.shrink();
                    }
                    final day = DateTime(
                      span.from.year,
                      span.from.month,
                      span.from.day + index,
                    );
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        '${day.day}/${day.month}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => const Color(0xE6101510),
                getTooltipItems: (spots) => [
                  for (final spot in spots)
                    LineTooltipItem(
                      '${members[spot.barIndex].name}: ${spot.y.toInt()}',
                      TextStyle(
                        color:
                            memberColors[spot.barIndex % memberColors.length],
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
