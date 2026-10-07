import 'dart:math';

/// One tickable swap.
///
/// [id] is the item's permanent identity: unlike [label] (which the user can
/// edit) or its position in the list (which changes when items are added or
/// removed), it never changes, so progress can be matched up across devices
/// and accounts. Seed items carry readable ids like `kitchen.metal-knives`;
/// items the user adds get a random `u-…` id. An empty id means "not assigned
/// yet" (saves from before ids existed) and is filled in by the repository
/// when it loads.
class ChecklistItem {
  final String id;
  final String label;
  final bool isCompleted;

  /// When [isCompleted] last changed, in milliseconds since the epoch (UTC);
  /// null if it never has (or the save predates timestamps). Per-account
  /// sync uses it to decide which device's change is newer.
  final int? updatedAt;

  const ChecklistItem({
    required this.id,
    required this.label,
    this.isCompleted = false,
    this.updatedAt,
  });

  /// A brand-new item with a fresh random id (for items the user adds).
  factory ChecklistItem.create(String label) =>
      ChecklistItem(id: newId(), label: label);

  static final Random _random = Random();

  static String newId() =>
      'u-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_random.nextInt(1 << 32).toRadixString(36)}';

  /// Id for a seed item that doesn't spell one out: challenge and label as
  /// lowercase slugs, e.g. (`Kitchen`, `Metal knives`) → `kitchen.metal-knives`.
  static String derivedId(String challengeId, String label) =>
      '${_slug(challengeId)}.${_slug(label)}';

  static String _slug(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  bool get hasId => id.isNotEmpty;

  ChecklistItem copyWith({
    String? id,
    String? label,
    bool? isCompleted,
    int? updatedAt,
    bool clearUpdatedAt = false,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      label: label ?? this.label,
      isCompleted: isCompleted ?? this.isCompleted,
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
    );
  }

  factory ChecklistItem.fromJson(dynamic json) {
    // The oldest format was a bare string per item.
    if (json is String) {
      return ChecklistItem(id: '', label: json);
    }

    final map = json as Map<String, dynamic>;
    return ChecklistItem(
      id: map['id'] as String? ?? '',
      label: map['label'] as String,
      isCompleted: map['completed'] as bool? ?? false,
      updatedAt: (map['updatedAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'completed': isCompleted,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }
}

class Challenge {
  final String label;
  final String description;
  final List<String> unlocks;
  final List<ChecklistItem> checklist;

  const Challenge({
    required this.label,
    required this.description,
    required this.unlocks,
    this.checklist = const [],
  });

  bool get isFullyCompleted =>
      checklist.isNotEmpty && checklist.every((item) => item.isCompleted);

  Challenge copyWith({
    String? label,
    String? description,
    List<String>? unlocks,
    List<ChecklistItem>? checklist,
  }) {
    return Challenge(
      label: label ?? this.label,
      description: description ?? this.description,
      unlocks: unlocks ?? this.unlocks,
      checklist: checklist ?? this.checklist,
    );
  }

  factory Challenge.fromJson(Map<String, dynamic> json) {
    return Challenge(
      label: json['id'] as String,
      description: json['description'] as String,
      unlocks: List<String>.from(json['unlocks'] as List),
      checklist: (json['checklist'] as List<dynamic>? ?? [])
          .map(ChecklistItem.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': label,
      'description': description,
      'unlocks': unlocks,
      'checklist': checklist.map((item) => item.toJson()).toList(),
    };
  }
}
