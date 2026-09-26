class ChecklistItem {
  final String label;
  final bool isCompleted;

  const ChecklistItem({required this.label, this.isCompleted = false});

  ChecklistItem copyWith({String? label, bool? isCompleted}) {
    return ChecklistItem(
      label: label ?? this.label,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  factory ChecklistItem.fromJson(dynamic json) {
    if (json is String) {
      return ChecklistItem(label: json);
    }

    final map = json as Map<String, dynamic>;
    return ChecklistItem(
      label: map['label'] as String,
      isCompleted: map['completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'label': label, 'completed': isCompleted};
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
