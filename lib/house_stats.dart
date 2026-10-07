import 'challenge_model.dart';
import 'house_models.dart';

/// The numbers behind a house's stats page: swaps per day, the running total
/// over time, and who is ahead. Pure functions, no Firebase.

/// `yyyy-MM-dd` for [date] (the device's local day).
String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _dayFromKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

/// How many swaps were ticked on each day, from the timestamps on the swaps
/// that are done right now. A swap with no timestamp (ticked before they
/// existed) has no known day and isn't counted here; it shows up in the
/// total instead (see [baselineOf]). Only the last [maxDays] days are kept.
Map<String, int> dailyCounts(
  Map<String, Challenge> challenges, {
  DateTime? now,
  int maxDays = 400,
}) {
  final today = now ?? DateTime.now();
  final oldest = DateTime(
    today.year,
    today.month,
    today.day,
  ).subtract(Duration(days: maxDays));
  final days = <String, int>{};
  for (final challenge in challenges.values) {
    for (final item in challenge.checklist) {
      final at = item.updatedAt;
      if (!item.isCompleted || at == null || at <= 0) continue;
      final when = DateTime.fromMillisecondsSinceEpoch(at);
      if (when.isBefore(oldest)) continue;
      final key = dayKey(when);
      days[key] = (days[key] ?? 0) + 1;
    }
  }
  return days;
}

/// Each member's share of a house's shared tree, from its swaps: the swaps
/// they were the last to tick (`done` and `by` them), in total and per day.
/// [names] maps a member's id to their name; [totalSwaps] is how many swaps
/// the tree has. Members are in [memberUids] order; anyone who isn't a
/// member any more is left out.
List<HouseMember> deriveMembers({
  required List<String> memberUids,
  required Map<String, String> names,
  required List<HouseSwap> swaps,
  required int totalSwaps,
}) {
  final done = <String, int>{};
  final days = <String, Map<String, int>>{};
  for (final swap in swaps) {
    if (!swap.done || swap.at <= 0) continue;
    done[swap.by] = (done[swap.by] ?? 0) + 1;
    final key = dayKey(DateTime.fromMillisecondsSinceEpoch(swap.at));
    final perDay = days.putIfAbsent(swap.by, () => {});
    perDay[key] = (perDay[key] ?? 0) + 1;
  }
  return [
    for (final uid in memberUids)
      HouseMember(
        uid: uid,
        name: (names[uid]?.isNotEmpty ?? false)
            ? names[uid]!
            : 'EcoSteps friend',
        completed: done[uid] ?? 0,
        total: totalSwaps,
        days: days[uid] ?? const {},
      ),
  ];
}

/// Swaps done that have no day on record (before tracking, or older than the
/// kept history): the level the graph starts from.
int baselineOf(HouseMember member) {
  final dated = member.days.values.fold(0, (sum, n) => sum + n);
  final base = member.completed - dated;
  return base < 0 ? 0 : base;
}

/// One point on a graph: the running total on [day].
class SeriesPoint {
  final DateTime day;
  final int total;

  const SeriesPoint(this.day, this.total);
}

/// The running total of swaps done for [member], one point per day from
/// [from] to [to] (both inclusive, as dates). Everything done before [from]
/// is already in the first point.
List<SeriesPoint> cumulativeSeries(
  HouseMember member, {
  required DateTime from,
  required DateTime to,
}) {
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  var running = baselineOf(member);
  for (final entry in member.days.entries) {
    if (_dayFromKey(entry.key).isBefore(start)) running += entry.value;
  }

  final points = <SeriesPoint>[];
  for (
    var day = start;
    !day.isAfter(end);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    running += member.days[dayKey(day)] ?? 0;
    points.add(SeriesPoint(day, running));
  }
  return points;
}

/// Swaps done in the last 7 days up to and including [now]'s day.
int doneThisWeek(HouseMember member, {DateTime? now}) {
  final today = now ?? DateTime.now();
  var total = 0;
  for (var i = 0; i < 7; i++) {
    final day = DateTime(today.year, today.month, today.day - i);
    total += member.days[dayKey(day)] ?? 0;
  }
  return total;
}

/// One row of a ranking.
class RankedMember {
  final int rank;
  final HouseMember member;
  final int value;

  const RankedMember(this.rank, this.member, this.value);
}

/// Members ordered by [value], highest first, ties broken by name. Members
/// with the same value share a rank (1, 1, 3).
List<RankedMember> rankMembers(
  List<HouseMember> members,
  int Function(HouseMember) value,
) {
  final sorted = [...members]
    ..sort((a, b) {
      final byValue = value(b).compareTo(value(a));
      return byValue != 0 ? byValue : a.name.compareTo(b.name);
    });
  final ranked = <RankedMember>[];
  for (var i = 0; i < sorted.length; i++) {
    final v = value(sorted[i]);
    final rank = i > 0 && v == ranked[i - 1].value ? ranked[i - 1].rank : i + 1;
    ranked.add(RankedMember(rank, sorted[i], v));
  }
  return ranked;
}
