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

/// Cloud entries for unlocked tiers share the swap list, told apart by this
/// prefix on the id (`tier:Kitchen`). Locally tiers are keyed by plain label.
const String tierIdPrefix = 'tier:';

class MergeResult {
  /// The local data after merging in the remote state.
  final Map<String, Challenge> challenges;

  /// Whether [challenges] differs from what was passed in.
  final bool localChanged;

  /// The local tier state after merging, keyed by label (see
  /// [ItemStamp.done] = unlocked). Includes tiers only the cloud knew about.
  final Map<String, ItemStamp> tiers;

  /// Whether [tiers] differs from what was passed in.
  final bool tiersChanged;

  /// The full state that should now be stored in the cloud, sorted by id.
  final List<ItemStamp> remote;

  /// Whether [remote] differs from the remote state that was passed in.
  final bool remoteChanged;

  const MergeResult({
    required this.challenges,
    required this.localChanged,
    this.tiers = const {},
    this.tiersChanged = false,
    required this.remote,
    required this.remoteChanged,
  });
}

class _Resolved {
  final bool done;
  final int at;

  /// Whether the local side has to take on [done]/[at].
  final bool localChanged;

  /// What to store in the cloud for this id, if it needs updating.
  final ItemStamp? toRemote;

  const _Resolved(this.done, this.at, this.localChanged, this.toRemote);
}

/// The rule for one id (a swap or a tier): the newer change wins; a tie goes
/// to "done"; something ticked before timestamps existed is stamped [now] the
/// first time it's seen. A local state of (not done, never changed) means
/// "untouched" and is left out of the cloud.
_Resolved _resolve({
  required String id,
  required bool localDone,
  required int localAt,
  required ItemStamp? theirs,
  required int now,
}) {
  _Resolved localWins() {
    final at = localAt > 0 ? localAt : now;
    return _Resolved(
      localDone,
      at,
      localAt == 0,
      ItemStamp(id: id, done: localDone, at: at),
    );
  }

  if (theirs == null) {
    if (!localDone && localAt == 0) return _Resolved(false, 0, false, null);
    return localWins();
  }

  final remoteWins =
      theirs.at > localAt ||
      (theirs.at == localAt && theirs.done && !localDone);
  if (remoteWins) {
    final unchanged = theirs.done == localDone && theirs.at == localAt;
    return _Resolved(theirs.done, theirs.at, !unchanged, null);
  }
  if (theirs.done == localDone && theirs.at == localAt) {
    return _Resolved(localDone, localAt, false, null);
  }
  return localWins();
}

/// Merges the cloud state into the local data, swap by swap and tier by
/// tier: the newer change wins, and when both changed at the very same
/// instant a tick/unlock beats an untick/lock. Nothing is lost when two
/// devices changed different swaps.
///
/// - A swap or tier the cloud has never heard of is added to it once it's
///   been ticked or unlocked.
/// - A tick or unlock from before timestamps existed is stamped [now] the
///   first time it's seen, so it takes part in later merges.
/// - Cloud entries for swaps this device doesn't have (a newer catalogue
///   elsewhere, or an item deleted here) are kept, not dropped. Tiers the
///   cloud knows and this device doesn't are added to [MergeResult.tiers].
///
/// Applying the result locally and then merging again changes nothing.
MergeResult mergeProgress({
  required Map<String, Challenge> local,
  Map<String, ItemStamp> localTiers = const {},
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
    final resolved = _resolve(
      id: item.id,
      localDone: item.isCompleted,
      localAt: item.updatedAt ?? 0,
      theirs: remoteById[item.id],
      now: now,
    );
    if (resolved.toRemote != null) newRemote[item.id] = resolved.toRemote!;
    if (!resolved.localChanged) return item;
    localChanged = true;
    return item.copyWith(isCompleted: resolved.done, updatedAt: resolved.at);
  }

  final merged = {
    for (final entry in local.entries)
      entry.key: entry.value.copyWith(
        checklist: [for (final item in entry.value.checklist) mergeItem(item)],
      ),
  };

  var tiersChanged = false;
  final mergedTiers = <String, ItemStamp>{};
  final tierLabels = <String>{
    ...localTiers.keys,
    for (final id in remoteById.keys)
      if (id.startsWith(tierIdPrefix)) id.substring(tierIdPrefix.length),
  };
  for (final label in tierLabels) {
    final mine = localTiers[label];
    final remoteId = '$tierIdPrefix$label';
    final resolved = _resolve(
      id: remoteId,
      localDone: mine?.done ?? false,
      localAt: mine?.at ?? 0,
      theirs: remoteById[remoteId],
      now: now,
    );
    if (resolved.toRemote != null) newRemote[remoteId] = resolved.toRemote!;
    if (resolved.localChanged) tiersChanged = true;
    if (resolved.done || resolved.at > 0) {
      mergedTiers[label] = ItemStamp(
        id: label,
        done: resolved.done,
        at: resolved.at,
      );
    }
  }

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
    tiers: mergedTiers,
    tiersChanged: tiersChanged,
    remote: sorted,
    remoteChanged: remoteChanged,
  );
}
