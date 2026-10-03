import 'package:flutter_test/flutter_test.dart';

import 'package:flut/challenge_model.dart';

void main() {
  group('Challenge.isFullyCompleted', () {
    test('is false when the checklist is empty', () {
      const challenge = Challenge(
        label: 'Kitchen',
        description: '',
        unlocks: [],
      );
      expect(challenge.isFullyCompleted, isFalse);
    });

    test('is false when some items are incomplete', () {
      const challenge = Challenge(
        label: 'Kitchen',
        description: '',
        unlocks: [],
        checklist: [
          ChecklistItem(id: 'k.knives', label: 'Metal knives', isCompleted: true),
          ChecklistItem(id: 'k.spoons', label: 'Wooden spoons', isCompleted: false),
        ],
      );
      expect(challenge.isFullyCompleted, isFalse);
    });

    test('is true when every item is completed', () {
      const challenge = Challenge(
        label: 'Kitchen',
        description: '',
        unlocks: [],
        checklist: [
          ChecklistItem(id: 'k.knives', label: 'Metal knives', isCompleted: true),
          ChecklistItem(id: 'k.spoons', label: 'Wooden spoons', isCompleted: true),
        ],
      );
      expect(challenge.isFullyCompleted, isTrue);
    });
  });
}
