import 'challenge_model.dart';

/// Completed/total swaps for one top-level area (Kitchen, Bathroom, ...),
/// counting every challenge reachable beneath it in the unlock tree.
class AreaProgress {
  final String label;
  final int completed;
  final int total;

  const AreaProgress({
    required this.label,
    required this.completed,
    required this.total,
  });

  double get progress => total == 0 ? 0 : completed / total;

  Map<String, dynamic> toJson() => {
    'label': label,
    'completed': completed,
    'total': total,
  };
}

/// One entry per area unlocked directly by the `Start` challenge, in that
/// order. Areas with no checklist items anywhere beneath them are skipped.
List<AreaProgress> progressByArea(Map<String, Challenge> challenges) {
  final start = challenges['Start'];
  if (start == null) return [];

  final areas = <AreaProgress>[];
  for (final rootLabel in start.unlocks) {
    final visited = <String>{};
    var completed = 0;
    var total = 0;

    void visit(String label) {
      final challenge = challenges[label];
      // `visited` also guards against cycles, which Playground edits allow.
      if (challenge == null || !visited.add(label)) return;
      total += challenge.checklist.length;
      completed += challenge.checklist.where((item) => item.isCompleted).length;
      challenge.unlocks.forEach(visit);
    }

    visit(rootLabel);
    if (total > 0) {
      areas.add(
        AreaProgress(label: rootLabel, completed: completed, total: total),
      );
    }
  }
  return areas;
}

/// The shareable summary uploaded to Firestore (`users/{uid}/progress/summary`)
/// for friends to read. Deliberately counts only — no item names — until the
/// "Share Checked Items" privacy toggle exists (Phase 3e).
Map<String, dynamic> buildProgressSummary(Map<String, Challenge> challenges) {
  var completed = 0;
  var total = 0;
  for (final challenge in challenges.values) {
    total += challenge.checklist.length;
    completed += challenge.checklist.where((item) => item.isCompleted).length;
  }
  return {
    'completed': completed,
    'total': total,
    'areas': progressByArea(challenges).map((area) => area.toJson()).toList(),
  };
}
