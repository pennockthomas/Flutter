// What adding a friend does in each situation, and the made-up demo friends.
// Against an in-memory backend: the real one is Firestore, with the rules in
// firestore.rules.

import 'package:flutter_test/flutter_test.dart';

import 'package:flut/challenge_model.dart';
import 'package:flut/friends_models.dart';
import 'package:flut/friends_service.dart';

import 'fake_friends_backend.dart';

FriendRequest _request(String from, String to, {bool accepted = false}) =>
    FriendRequest(
      from: from,
      to: to,
      fromName: 'name-$from',
      toName: 'name-$to',
      accepted: accepted,
    );

void main() {
  late FakeFriendsBackend backend;
  late FriendsService service;

  Future<AddFriendOutcome> add(String code) =>
      service.addByCode(myUid: 'me', myName: 'Me Myself', rawCode: code);

  setUp(() {
    backend = FakeFriendsBackend();
    service = FriendsService(backend);
    backend.addCode('ABC234', 'anna', 'Anna Jansen');
  });

  group('normalizeCode', () {
    test('tidies case, spaces and dashes', () {
      expect(FriendsService.normalizeCode(' abc-234 '), 'ABC234');
      expect(FriendsService.normalizeCode('abc 234'), 'ABC234');
    });

    test('refuses anything that cannot be a code', () {
      expect(FriendsService.normalizeCode(''), isNull);
      expect(FriendsService.normalizeCode('ABC23'), isNull);
      expect(FriendsService.normalizeCode('ABC2345'), isNull);
      expect(
        FriendsService.normalizeCode('ABC10O'),
        isNull,
        reason: '0, 1, O and I are never in a code',
      );
    });
  });

  group('addByCode', () {
    test('an unreadable code is refused without asking the backend', () async {
      backend.failLookupWith = StateError('should not be called');

      expect(await add('nope'), AddFriendOutcome.invalidCode);
    });

    test('an unknown code is not found', () async {
      expect(await add('ZZZ999'), AddFriendOutcome.notFound);
    });

    test('your own code is refused', () async {
      backend.addCode('MNPE22', 'me', 'Me Myself');

      expect(await add('mnpe22'), AddFriendOutcome.yourOwnCode);
      expect(backend.requests, isEmpty);
    });

    test('a new friend gets a pending request with both names', () async {
      expect(await add('abc234'), AddFriendOutcome.requestSent);

      final sent = backend.requests['me_anna']!;
      expect(sent.accepted, isFalse);
      expect(sent.fromName, 'Me Myself');
      expect(sent.toName, 'Anna Jansen');
    });

    test('asking twice does not send a second request', () async {
      await add('ABC234');

      expect(await add('ABC234'), AddFriendOutcome.alreadyRequested);
      expect(backend.requests.length, 1);
    });

    test('someone who already asked you becomes your friend at once', () async {
      backend.putRequest(_request('anna', 'me'));

      expect(await add('ABC234'), AddFriendOutcome.nowFriends);

      expect(backend.requests['anna_me']!.accepted, isTrue);
      expect(
        backend.requests.containsKey('me_anna'),
        isFalse,
        reason: 'no second request is needed',
      );
    });

    test('an accepted friendship, either way round, is already one', () async {
      backend.putRequest(_request('me', 'anna', accepted: true));
      expect(await add('ABC234'), AddFriendOutcome.alreadyFriends);

      backend.requests.clear();
      backend.putRequest(_request('anna', 'me', accepted: true));
      expect(await add('ABC234'), AddFriendOutcome.alreadyFriends);
    });
  });

  test('accept and remove change the request', () async {
    final incoming = _request('anna', 'me');
    backend.putRequest(incoming);

    await service.accept(incoming);
    expect(backend.requests['anna_me']!.accepted, isTrue);

    await service.remove(backend.requests['anna_me']!);
    expect(backend.requests, isEmpty);
  });

  test('a friend code is created once and then kept', () async {
    final first = await service.myCode('me', 'Me');
    final second = await service.myCode('me', 'Me Renamed');

    expect(second, first);
    expect(backend.codes[first]!.displayName, 'Me Renamed');
    expect(backend.codesCreated, 1);
  });

  group('demo friends', () {
    Map<String, Challenge> catalog() => {
      'Start': const Challenge(
        label: 'Start',
        description: '',
        unlocks: ['Kitchen', 'Bathroom', 'On-The-Go'],
      ),
      for (final (name, count) in [
        ('Kitchen', 47),
        ('Bathroom', 29),
        ('On-The-Go', 42),
      ])
        name: Challenge(
          label: name,
          description: '',
          unlocks: const [],
          checklist: [
            for (var i = 0; i < count; i++)
              ChecklistItem(id: '$name.$i', label: '$name $i'),
          ],
        ),
    };

    test('there are three, flagged as demo, with the real totals', () {
      final demo = FriendsService.buildDemoFriends(catalog());

      expect(demo.map((f) => f.name), [
        'Mila Vermeer',
        'Sam de Vries',
        'Lena Bakker',
      ]);
      for (final friend in demo) {
        expect(friend.isDemo, isTrue);
        expect(friend.total, 47 + 29 + 42);
        expect(friend.completed, inInclusiveRange(1, friend.total - 1));
        expect(friend.areas.map((a) => a.label), [
          'Kitchen',
          'Bathroom',
          'On-The-Go',
        ]);
        expect(
          friend.areas.fold<int>(0, (sum, a) => sum + a.completed),
          friend.completed,
        );
      }
    });

    test('they differ, so the screen has something to compare', () {
      final demo = FriendsService.buildDemoFriends(catalog());

      expect(demo.map((f) => f.completed).toSet().length, 3);
    });

    test('resetting stores them in the backend', () async {
      await service.resetDemoFriends(catalog());

      expect((await service.loadDemoFriends()).length, 3);
    });
  });

  group('FriendSummary', () {
    test('is read from a stored summary, ignoring anything malformed', () {
      final friend = FriendSummary.fromData(
        uid: 'x',
        name: '',
        summary: {
          'completed': 5,
          'total': 20,
          'areas': [
            {'label': 'Kitchen', 'completed': 4, 'total': 10},
            {'completed': 1, 'total': 2},
            'junk',
          ],
        },
      );

      expect(friend.name, 'EcoSteps friend');
      expect(friend.progress, 0.25);
      expect(friend.areas.length, 1);
      expect(friend.focus, 'Kitchen');
    });

    test('a missing summary reads as nothing done yet', () {
      final friend = FriendSummary.fromData(
        uid: 'x',
        name: 'Sam',
        summary: null,
      );

      expect(friend.completed, 0);
      expect(friend.progress, 0);
      expect(friend.focus, isNull);
    });
  });
}
