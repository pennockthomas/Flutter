// The dropdown on the tree screen and the house page: switching between
// Personal and a house, invitations, naming, inviting friends, the ranking
// and the graph.

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flut/app_user.dart';
import 'package:flut/challenge_model.dart';
import 'package:flut/friends_models.dart';
import 'package:flut/friends_service.dart';
import 'package:flut/house_models.dart';
import 'package:flut/house_page.dart';
import 'package:flut/houses_controller.dart';
import 'package:flut/houses_service.dart';
import 'package:flut/scope_dropdown.dart';

import 'fake_friends_backend.dart';
import 'fake_houses_backend.dart';

final _now = DateTime(2026, 10, 7, 12);

House _house(String id, List<String> members, {String name = 'House'}) =>
    House(id: id, name: name, memberUids: members, createdBy: members.first);

/// [count] swaps ticked by [by] on one day (ids are unique per [prefix]).
Map<String, HouseSwap> _ticks(
  String by,
  int count,
  DateTime day,
  String prefix,
) => {
  for (var i = 0; i < count; i++)
    '$prefix$i': HouseSwap(
      id: '$prefix$i',
      done: true,
      at: DateTime(day.year, day.month, day.day, 12).millisecondsSinceEpoch,
      by: by,
    ),
};

/// A tree of 118 swaps, like the real one.
Map<String, Challenge> _bigCatalog() => {
  'Kitchen': Challenge(
    label: 'Kitchen',
    description: '',
    unlocks: const [],
    checklist: [
      for (var i = 0; i < 118; i++) ChecklistItem(id: 's$i', label: 'Swap $i'),
    ],
  ),
};

void main() {
  late FakeHousesBackend houses;
  late FakeFriendsBackend friendsBackend;
  late StreamController<String?> uids;
  late HousesController controller;

  Future<void> signIn(WidgetTester tester, [String uid = 'me']) async {
    uids.add(uid);
    // The controller finishes signing in over a few microtask turns, which
    // pumpAndSettle alone doesn't wait for when no frame is scheduled.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppUser.setName('Me Myself');
    houses = FakeHousesBackend();
    friendsBackend = FakeFriendsBackend();
    uids = StreamController<String?>.broadcast();
    controller = HousesController(
      service: HousesService(houses),
      friends: FriendsService(friendsBackend),
      loadCatalog: () async => _bigCatalog(),
    );
  });

  tearDown(() async {
    await controller.stopForTest();
    await uids.close();
  });

  Future<void> tallScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('dropdown', () {
    Future<void> showDropdown(WidgetTester tester) async {
      await controller.start(uids: uids.stream);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ScopeDropdown(controller: controller),
            ),
          ),
        ),
      );
    }

    testWidgets('says Personal to begin with', (tester) async {
      await showDropdown(tester);

      expect(find.text('Personal'), findsOneWidget);
    });

    testWidgets('signed out it offers to sign in, not houses', (tester) async {
      await showDropdown(tester);

      await tester.tap(find.byKey(const Key('scope-dropdown')));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to use houses'), findsOneWidget);
      expect(find.text('New house'), findsNothing);
    });

    testWidgets('lists your houses and switches to one', (tester) async {
      houses.addHouse(_house('h1', ['me'], name: 'Our place'));
      houses.addHouse(_house('h2', ['me'], name: 'The attic'));
      await showDropdown(tester);
      await signIn(tester);

      await tester.tap(find.byKey(const Key('scope-dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('Our place'), findsOneWidget);
      expect(find.text('The attic'), findsOneWidget);

      await tester.tap(find.text('The attic'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scope-label')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('scope-label'))).data,
        'The attic',
      );
    });

    testWidgets('choosing Personal goes back', (tester) async {
      houses.addHouse(_house('h1', ['me'], name: 'Our place'));
      await showDropdown(tester);
      await signIn(tester);
      await controller.select('h1');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scope-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal').last);
      await tester.pumpAndSettle();

      expect(controller.selectedHouse, isNull);
      expect(
        tester.widget<Text>(find.byKey(const Key('scope-label'))).data,
        'Personal',
      );
    });

    testWidgets('New house makes one called House and opens it', (
      tester,
    ) async {
      await showDropdown(tester);
      await signIn(tester);

      await tester.tap(find.byKey(const Key('scope-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New house'));
      await tester.pumpAndSettle();

      expect(houses.houses.values.single.name, 'House');
      expect(controller.selectedHouse, isNotNull);
      expect(
        tester.widget<Text>(find.byKey(const Key('scope-label'))).data,
        'House',
      );
    });

    testWidgets('a sixth house is refused with a message', (tester) async {
      for (var i = 0; i < HousesService.maxHouses; i++) {
        houses.addHouse(_house('h$i', ['me'], name: 'H$i'));
      }
      await showDropdown(tester);
      await signIn(tester);

      await tester.tap(find.byKey(const Key('scope-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New house'));
      await tester.pumpAndSettle();

      expect(find.textContaining('up to 5 houses'), findsOneWidget);
      expect(houses.houses.length, HousesService.maxHouses);
    });

    testWidgets('an invitation shows a badge and can be accepted', (
      tester,
    ) async {
      houses.addHouse(_house('h2', ['anna'], name: 'Annas place'));
      houses.addInvite(
        const HouseInvite(
          houseId: 'h2',
          houseName: 'Annas place',
          from: 'anna',
          fromName: 'Anna',
          to: 'me',
        ),
      );
      await showDropdown(tester);
      await signIn(tester);
      expect(find.byKey(const Key('invite-badge')), findsOneWidget);

      await tester.tap(find.byKey(const Key('scope-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 invitation'));
      await tester.pumpAndSettle();
      expect(find.text('Anna invited you to Annas place'), findsOneWidget);

      await tester.tap(find.byKey(const Key('join-h2')));
      await tester.pumpAndSettle();

      expect(houses.houses['h2']!.hasMember('me'), isTrue);
      expect(controller.selectedHouse!.id, 'h2');
      expect(find.byKey(const Key('invite-badge')), findsNothing);
    });

    testWidgets('an invitation can be declined', (tester) async {
      houses.addHouse(_house('h2', ['anna']));
      houses.addInvite(
        const HouseInvite(
          houseId: 'h2',
          houseName: 'House',
          from: 'anna',
          fromName: 'Anna',
          to: 'me',
        ),
      );
      await showDropdown(tester);
      await signIn(tester);

      await tester.tap(find.byKey(const Key('scope-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 invitation'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decline-h2')));
      await tester.pumpAndSettle();

      expect(houses.invites, isEmpty);
      expect(find.text('No invitations right now.'), findsOneWidget);
    });
  });

  group('house page', () {
    Future<void> showHouse(
      WidgetTester tester,
      House house, {
      String uid = 'me',
    }) async {
      await tallScreen(tester);
      await controller.start(uids: uids.stream);
      houses.addHouse(house);
      await signIn(tester, uid);
      await controller.select(house.id);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HouseView(
              key: ValueKey(house.id),
              house: house,
              controller: controller,
              now: _now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    void seedStats() {
      houses.names['h1'] = {
        'me': 'Me Myself',
        'anna': 'Anna Jansen',
        'ben': 'Ben Smit',
      };
      houses.swaps['h1'] = {
        ..._ticks('me', 2, DateTime(2026, 10, 7), 'me-new'),
        ..._ticks('me', 10, DateTime(2026, 9, 20), 'me-old'),
        ..._ticks('anna', 30, DateTime(2026, 9, 1), 'anna'),
        ..._ticks('ben', 5, DateTime(2026, 10, 5), 'ben'),
      };
    }

    testWidgets('shows the name, who is in it and their totals', (
      tester,
    ) async {
      seedStats();
      await showHouse(
        tester,
        _house('h1', ['me', 'anna', 'ben'], name: 'Our place'),
      );

      expect(find.text('Our place'), findsOneWidget);
      expect(find.text('3 people'), findsOneWidget);
      expect(find.text('Me Myself (you)'), findsOneWidget);
      expect(find.text('30/118 swaps · 0 this week'), findsOneWidget);
      expect(find.text('5/118 swaps · 5 this week'), findsOneWidget);
    });

    testWidgets('the ranking puts the person with the most swaps first', (
      tester,
    ) async {
      seedStats();
      await showHouse(tester, _house('h1', ['me', 'anna', 'ben']));

      final anna = tester.getTopLeft(find.byKey(const Key('rank-anna'))).dy;
      final me = tester.getTopLeft(find.byKey(const Key('rank-me'))).dy;
      final ben = tester.getTopLeft(find.byKey(const Key('rank-ben'))).dy;
      expect(anna, lessThan(me));
      expect(me, lessThan(ben));
      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    });

    testWidgets('"This week" ranks by swaps in the last seven days', (
      tester,
    ) async {
      seedStats();
      await showHouse(tester, _house('h1', ['me', 'anna', 'ben']));

      await tester.tap(find.byKey(const Key('ranking-week')));
      await tester.pumpAndSettle();

      final ben = tester.getTopLeft(find.byKey(const Key('rank-ben'))).dy;
      final anna = tester.getTopLeft(find.byKey(const Key('rank-anna'))).dy;
      expect(ben, lessThan(anna), reason: 'Ben did 5 this week, Anna none');
    });

    testWidgets('there is a graph, and the range can be changed', (
      tester,
    ) async {
      seedStats();
      await showHouse(tester, _house('h1', ['me', 'anna', 'ben']));

      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('Swaps over time'), findsOneWidget);

      for (final range in ['range-week', 'range-all', 'range-month']) {
        await tester.tap(find.byKey(Key(range)));
        await tester.pumpAndSettle();
        expect(find.byType(LineChart), findsOneWidget);
      }
    });

    testWidgets('someone who has not shared numbers yet still appears', (
      tester,
    ) async {
      houses.names['h1'] = {'me': 'Me Myself'};
      houses.swaps['h1'] = _ticks('me', 3, DateTime(2026, 10, 6), 'm');
      await showHouse(tester, _house('h1', ['me', 'newcomer']));

      expect(find.text('EcoSteps friend'), findsWidgets);
      expect(find.text('2 people'), findsOneWidget);
    });

    testWidgets('the name can be changed by anyone in the house', (
      tester,
    ) async {
      seedStats();
      await showHouse(tester, _house('h1', ['me', 'anna', 'ben']));

      await tester.tap(find.byKey(const Key('rename-house')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('house-name-field')),
        '  The   Attic ',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(houses.houses['h1']!.name, 'The Attic');
    });

    testWidgets('an empty name cannot be saved', (tester) async {
      seedStats();
      await showHouse(tester, _house('h1', ['me', 'anna', 'ben']));

      await tester.tap(find.byKey(const Key('rename-house')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('house-name-field')), '   ');
      await tester.pump();

      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('you can invite a friend who is not in the house yet', (
      tester,
    ) async {
      seedStats();
      friendsBackend.putRequest(
        const FriendRequest(
          from: 'me',
          to: 'anna',
          fromName: 'Me',
          toName: 'Anna Jansen',
          accepted: true,
        ),
      );
      friendsBackend.putRequest(
        const FriendRequest(
          from: 'carol',
          to: 'me',
          fromName: 'Carol Dijk',
          toName: 'Me',
          accepted: true,
        ),
      );
      await showHouse(tester, _house('h1', ['me', 'anna']));

      await tester.tap(find.byKey(const Key('invite-friend')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('invite-anna')),
        findsNothing,
        reason: 'already in the house',
      );
      await tester.tap(find.byKey(const Key('invite-carol')));
      await tester.pumpAndSettle();

      expect(houses.invites['h1_carol']!.fromName, 'Me Myself');
      expect(find.text('Invited Carol Dijk'), findsOneWidget);
    });

    testWidgets('with no friends to invite it says how to get some', (
      tester,
    ) async {
      await showHouse(tester, _house('h1', ['me']));

      await tester.tap(find.byKey(const Key('invite-friend')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Add friends first'), findsOneWidget);
    });

    testWidgets('an invitation can be cancelled', (tester) async {
      friendsBackend.putRequest(
        const FriendRequest(
          from: 'me',
          to: 'carol',
          fromName: 'Me',
          toName: 'Carol Dijk',
          accepted: true,
        ),
      );
      houses.addInvite(
        const HouseInvite(
          houseId: 'h1',
          houseName: 'House',
          from: 'me',
          fromName: 'Me',
          to: 'carol',
        ),
      );
      await showHouse(tester, _house('h1', ['me']));
      expect(find.text('Invited Carol Dijk'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel-invite-carol')));
      await tester.pumpAndSettle();

      expect(houses.invites, isEmpty);
    });

    testWidgets('a full house says so instead of offering to invite', (
      tester,
    ) async {
      final eight = ['me', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
      await showHouse(tester, _house('h1', eight));

      expect(find.byKey(const Key('invite-friend')), findsNothing);
      expect(find.textContaining('house is full'), findsOneWidget);
    });

    testWidgets('anyone can remove another member, after a confirmation', (
      tester,
    ) async {
      seedStats();
      await showHouse(tester, _house('h1', ['me', 'anna', 'ben']));
      expect(find.byKey(const Key('remove-me')), findsNothing);

      await tester.tap(find.byKey(const Key('remove-ben')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(houses.houses['h1']!.memberUids, contains('ben'));

      await tester.tap(find.byKey(const Key('remove-ben')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(houses.houses['h1']!.memberUids, ['me', 'anna']);
    });

    testWidgets('leaving asks first and then takes you out', (tester) async {
      seedStats();
      await showHouse(tester, _house('h1', ['me', 'anna']));
      await controller.select('h1');

      await tester.tap(find.byKey(const Key('leave-house')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(houses.houses['h1']!.memberUids, ['anna']);
      expect(controller.selectedHouse, isNull);
    });
  });
}
