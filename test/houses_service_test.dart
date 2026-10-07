// The rules of houses: names, who can be invited, joining, leaving.
// Against an in-memory backend; the real one is Firestore (rules tested in
// tool/rules_test).

import 'package:flutter_test/flutter_test.dart';

import 'package:flut/friends_models.dart';
import 'package:flut/house_models.dart';
import 'package:flut/houses_service.dart';

import 'fake_houses_backend.dart';

House _house(String id, List<String> members, {String name = 'House'}) =>
    House(id: id, name: name, memberUids: members, createdBy: members.first);

Future<void> _throwsProblem(Future<void> Function() action, HouseProblem p) {
  return expectLater(
    action(),
    throwsA(isA<HouseException>().having((e) => e.problem, 'problem', p)),
  );
}

void main() {
  late FakeHousesBackend backend;
  late HousesService service;

  setUp(() {
    backend = FakeHousesBackend();
    service = HousesService(backend);
  });

  group('creating and renaming', () {
    test('a new house is called House and has only you in it', () async {
      final house = await service.createHouse('me');

      expect(house.name, 'House');
      expect(house.memberUids, ['me']);
      expect(backend.houses[house.id], isNotNull);
    });

    test('a house can be created with a name of your choice', () async {
      final house = await service.createHouse('me', name: '  The   Attic ');

      expect(house.name, 'The Attic');
    });

    test('an empty or too long name is refused', () async {
      await _throwsProblem(
        () => service.createHouse('me', name: '   '),
        HouseProblem.invalidName,
      );
      await _throwsProblem(
        () => service.createHouse('me', name: 'x' * 41),
        HouseProblem.invalidName,
      );
      expect(backend.houses, isEmpty);
    });

    test('renaming tidies the name and refuses bad ones', () async {
      final house = await service.createHouse('me');

      await service.rename(house, ' Our  place ');
      expect(backend.houses[house.id]!.name, 'Our place');

      await _throwsProblem(
        () => service.rename(house, ''),
        HouseProblem.invalidName,
      );
      expect(backend.houses[house.id]!.name, 'Our place');
    });
  });

  group('inviting', () {
    test(
      'a member can invite a friend; the invite names house and sender',
      () async {
        final house = await service.createHouse('me');

        await service.invite(
          house: house,
          fromUid: 'me',
          fromName: 'Me Myself',
          friendUid: 'anna',
        );

        final invite = backend.invites['${house.id}_anna']!;
        expect(invite.houseName, 'House');
        expect(invite.fromName, 'Me Myself');
      },
    );

    test('someone already inside cannot be invited', () async {
      final house = _house('h1', ['me', 'anna']);

      await _throwsProblem(
        () => service.invite(
          house: house,
          fromUid: 'me',
          fromName: 'Me',
          friendUid: 'anna',
        ),
        HouseProblem.alreadyInHouse,
      );
    });

    test('inviting twice is refused', () async {
      final house = _house('h1', ['me']);
      final first = HouseInvite(
        houseId: 'h1',
        houseName: 'House',
        from: 'me',
        fromName: 'Me',
        to: 'anna',
      );

      await _throwsProblem(
        () => service.invite(
          house: house,
          fromUid: 'me',
          fromName: 'Me',
          friendUid: 'anna',
          pendingInvites: [first],
        ),
        HouseProblem.alreadyInvited,
      );
    });

    test('a full house cannot invite anyone', () async {
      final house = _house('h1', [
        for (var i = 0; i < House.maxMembers; i++) 'u$i',
      ]);

      await _throwsProblem(
        () => service.invite(
          house: house,
          fromUid: 'u0',
          fromName: 'U',
          friendUid: 'anna',
        ),
        HouseProblem.houseFull,
      );
    });

    test(
      'friends to pick from leave out members and people already invited',
      () {
        final house = _house('h1', ['me', 'anna']);
        final friends = [
          (uid: 'anna', name: 'Anna'),
          (uid: 'ben', name: 'Ben'),
          (uid: 'carol', name: 'Carol'),
        ];
        final invites = [
          const HouseInvite(
            houseId: 'h1',
            houseName: 'House',
            from: 'me',
            fromName: 'Me',
            to: 'ben',
          ),
        ];

        final choices = HousesService.invitableFriends(
          house: house,
          friends: friends,
          pendingInvites: invites,
        );

        expect(choices.map((f) => f.name), ['Carol']);
      },
    );

    test(
      'the friends of a person are the accepted requests, either way round',
      () {
        final friends = HousesService.friendsOf('me', [
          const FriendRequest(
            from: 'me',
            to: 'anna',
            fromName: 'Me',
            toName: 'Anna',
            accepted: true,
          ),
          const FriendRequest(
            from: 'ben',
            to: 'me',
            fromName: 'Ben',
            toName: 'Me',
            accepted: true,
          ),
          const FriendRequest(
            from: 'me',
            to: 'carol',
            fromName: 'Me',
            toName: 'Carol',
          ),
        ]);

        expect(friends.map((f) => f.name), ['Anna', 'Ben']);
        expect(friends.map((f) => f.uid), ['anna', 'ben']);
      },
    );
  });

  group('joining and leaving', () {
    test('accepting an invitation makes you a member and clears it', () async {
      final house = await service.createHouse('me');
      await service.invite(
        house: house,
        fromUid: 'me',
        fromName: 'Me',
        friendUid: 'anna',
      );

      await service.accept(backend.invites['${house.id}_anna']!, 'anna');

      expect(backend.houses[house.id]!.memberUids, ['me', 'anna']);
      expect(backend.invites, isEmpty);
    });

    test('declining or cancelling removes the invitation only', () async {
      final house = await service.createHouse('me');
      await service.invite(
        house: house,
        fromUid: 'me',
        fromName: 'Me',
        friendUid: 'anna',
      );

      await service.dropInvite(backend.invites['${house.id}_anna']!);

      expect(backend.invites, isEmpty);
      expect(backend.houses[house.id]!.memberUids, ['me']);
    });

    test('leaving takes you and your name out, and keeps the house', () async {
      final house = _house('h1', ['me', 'anna']);
      backend.addHouse(house);
      backend.names['h1'] = {'me': 'me', 'anna': 'anna'};

      await service.leave(house, 'anna');

      expect(backend.houses['h1']!.memberUids, ['me']);
      expect(backend.names['h1']!.keys, ['me']);
    });

    test('anyone can remove another member', () async {
      final house = _house('h1', ['me', 'anna', 'ben']);
      backend.addHouse(house);

      await service.removeMember(house, 'ben');

      expect(backend.houses['h1']!.memberUids, ['me', 'anna']);
    });

    test('the last person leaving deletes the house', () async {
      final house = _house('h1', ['me']);
      backend.addHouse(house);

      await service.leave(house, 'me');

      expect(backend.houses, isEmpty);
    });
  });
}
