import 'progress_summary.dart';

/// A friend's shared progress: counts only (totals and per area), never swap
/// names. Built from `users/{uid}/progress/summary` and the profile name.
class FriendSummary {
  final String uid;
  final String name;
  final int completed;
  final int total;
  final List<AreaProgress> areas;

  /// True for the made-up friends shown to demonstrate the screen.
  final bool isDemo;

  const FriendSummary({
    required this.uid,
    required this.name,
    required this.completed,
    required this.total,
    required this.areas,
    this.isDemo = false,
  });

  double get progress => total == 0 ? 0 : completed / total;

  /// First letter of the first and last word, like [AppUser.initials].
  String get initials {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String first(String word) =>
        String.fromCharCode(word.runes.first).toUpperCase();
    return parts.length == 1
        ? first(parts.first)
        : first(parts.first) + first(parts.last);
  }

  /// The area this friend has done most in, or null if none yet.
  String? get focus {
    AreaProgress? best;
    for (final area in areas) {
      if (area.completed > (best?.completed ?? 0)) best = area;
    }
    return best?.label;
  }

  factory FriendSummary.fromData({
    required String uid,
    required String name,
    required Map<String, dynamic>? summary,
    bool isDemo = false,
  }) {
    int count(Object? value) =>
        (value is num && value >= 0) ? value.toInt() : 0;
    final areas = <AreaProgress>[];
    final rawAreas = summary?['areas'];
    if (rawAreas is List) {
      for (final entry in rawAreas) {
        if (entry is Map && entry['label'] is String) {
          areas.add(
            AreaProgress(
              label: entry['label'] as String,
              completed: count(entry['completed']),
              total: count(entry['total']),
            ),
          );
        }
      }
    }
    return FriendSummary(
      uid: uid,
      name: name.isEmpty ? 'EcoSteps friend' : name,
      completed: count(summary?['completed']),
      total: count(summary?['total']),
      areas: areas,
      isDemo: isDemo,
    );
  }

  /// The document written for a demo friend (`demoFriends/{id}`).
  Map<String, dynamic> toDemoJson() => {
    'name': name,
    'completed': completed,
    'total': total,
    'areas': [for (final area in areas) area.toJson()],
  };
}

/// One friend request, as stored in `friendRequests/{from}_{to}`.
class FriendRequest {
  final String from;
  final String to;
  final String fromName;
  final String toName;
  final bool accepted;

  const FriendRequest({
    required this.from,
    required this.to,
    required this.fromName,
    required this.toName,
    this.accepted = false,
  });

  String get id => '${from}_$to';

  /// The other person in this request, from [me]'s side.
  String otherUid(String me) => from == me ? to : from;
  String otherName(String me) => from == me ? toName : fromName;

  factory FriendRequest.fromData(Map<String, dynamic> data) => FriendRequest(
    from: data['from'] as String,
    to: data['to'] as String,
    fromName: (data['fromName'] as String?) ?? '',
    toName: (data['toName'] as String?) ?? '',
    accepted: data['status'] == 'accepted',
  );

  /// The fields of a new request (the creation time is added when saving).
  Map<String, dynamic> toData() => {
    'from': from,
    'to': to,
    'fromName': fromName,
    'toName': toName,
    'status': accepted ? 'accepted' : 'pending',
  };
}

/// What a friend code points at.
class FriendCodeInfo {
  final String code;
  final String uid;
  final String displayName;

  const FriendCodeInfo({
    required this.code,
    required this.uid,
    required this.displayName,
  });
}

/// What happened when the user tried to add a friend by code.
enum AddFriendOutcome {
  /// A request was sent; the other person has to accept it.
  requestSent,

  /// They had already asked us, so this made you friends straight away.
  nowFriends,
  alreadyFriends,
  alreadyRequested,
  notFound,
  yourOwnCode,
  invalidCode,
}
