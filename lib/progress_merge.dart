import 'challenge_model.dart';

/// One swap's state as stored in the cloud: whether it's done and when that
/// last changed (milliseconds since the epoch). Unticking is a stamp too
/// ([done] false), so an untick on one device isn't undone by a stale tick
/// on another.
class ItemStamp {
  final String id;
  final bool done;
  final int at;

  const ItemStamp({required this.id, required this.done, required this.at});

  factory ItemStamp.fromJson(Map<String, dynamic> json) => ItemStamp(
    id: json['id'] as String,
    done: json['done'] as bool,
    at: (json['at'] as num).toInt(),
  );

  Map<String, dynamic> toJson() => {'id': id, 'done': done, 'at': at};

  @override
  bool operator ==(Object other) =>
      other is ItemStamp &&
      other.id == id &&
      other.done == done &&
      other.at == at;

  @override
  int get hashCode => Object.hash(id, done, at);

  @override
  String toString() => 'ItemStamp($id, $done, $at)';
}

/// Stamps every item whose completion changed between [before] and [after]
/// with [now]. An item that's new and already ticked counts as changed.
/// Everything else keeps the timestamp it had.
Map<String, Challenge> stampChanges(
  Map<String, Challenge> before,
  Map<String, Challenge> after,
  int now,
) {
  final previous = <String, ChecklistItem>{
    for (final challenge in before.values)
      for (final item in challenge.checklist) item.id: item,
  };
  return {
    for (final entry in after.entries)
      entry.key: entry.value.copyWith(
        checklist: [
          for (final item in entry.value.checklist)
            _stamped(previous[item.id], item, now),
        ],
      ),
  };
}

ChecklistItem _stamped(ChecklistItem? before, ChecklistItem after, int now) {
  final changed = before == null
      ? after.isCompleted && after.updatedAt == null
      : before.isCompleted != after.isCompleted;
  return changed ? after.copyWith(updatedAt: now) : after;
}

class MergeResult {
  /// The local data after merging in the remote state.
  final Map<String, Challenge> challenges;

  /// Whether [challenges] differs from what was passed in.
  final bool localChanged;

  /// The full state that should now be stored in the cloud, sorted by id.
  final List<ItemStamp> remote;

  /// Whether [remote] differs from the remote state that was passed in.
  final bool remoteChanged;

  const MergeResult({
    required this.challenges,
    required this.localChanged,
    required this.remote,
    required this.remoteChanged,
  });
}

/// Merges the cloud state into the local data, swap by swap: the newer
/// change wins, and when both changed at the very same instant a tick beats
/// an untick. Nothing is lost when two devices changed different swaps.
///
/// - A swap the cloud has never heard of is added to it if it's ticked.
/// - A tick from before timestamps existed is stamped [now] the first time
///   it's seen, so it takes part in later merges.
/// - Cloud entries for swaps this device doesn't have (a newer catalogue
///   elsewhere, or an item deleted here) are kept, not dropped.
///
/// Applying the result locally and then merging again changes nothing.
MergeResult mergeProgress({
  required Map<String, Challenge> local,
  required List<ItemStamp> remote,
  required int now,
}) {
  final remoteById = <String, ItemStamp>{};
  for (final stamp in remote) {
    final existing = remoteById[stamp.id];
    if (existing == null || stamp.at > existing.at) {
      remoteById[stamp.id] = stamp;
    }
  }
  final newRemote = Map<String, ItemStamp>.from(remoteById);
  var localChanged = false;

  ChecklistItem mergeItem(ChecklistItem item) {
    final localAt = item.updatedAt ?? 0;
    final theirs = remoteById[item.id];

    if (theirs == null) {
      if (!item.isCompleted && localAt == 0) return item; // untouched
      final at = localAt > 0 ? localAt : now;
      newRemote[item.id] = ItemStamp(
        id: item.id,
        done: item.isCompleted,
        at: at,
      );
      if (localAt == 0) {
        localChanged = true;
        return item.copyWith(updatedAt: at);
      }
      return item;
    }

    final remoteWins =
        theirs.at > localAt ||
        (theirs.at == localAt && theirs.done && !item.isCompleted);
    if (remoteWins) {
      if (theirs.done == item.isCompleted && theirs.at == item.updatedAt) {
        return item;
      }
      localChanged = true;
      return item.copyWith(isCompleted: theirs.done, updatedAt: theirs.at);
    }

    if (theirs.done == item.isCompleted && theirs.at == localAt) return item;
    final at = localAt > 0 ? localAt : now;
    newRemote[item.id] = ItemStamp(id: item.id, done: item.isCompleted, at: at);
    if (localAt == 0) {
      localChanged = true;
      return item.copyWith(updatedAt: at);
    }
    return item;
  }

  final merged = {
    for (final entry in local.entries)
      entry.key: entry.value.copyWith(
        checklist: [for (final item in entry.value.checklist) mergeItem(item)],
      ),
  };

  final sorted = newRemote.values.toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  final before = remoteById.values.toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  var remoteChanged = sorted.length != before.length;
  if (!remoteChanged) {
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i] != before[i]) {
        remoteChanged = true;
        break;
      }
    }
  }

  return MergeResult(
    challenges: merged,
    localChanged: localChanged,
    remote: sorted,
    remoteChanged: remoteChanged,
  );
}
