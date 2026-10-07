// The Friends screen and its Add friend screen, driven against an in-memory
// backend: signed out, adding friends, answering requests, the friends list,
// removing a friend and the demo friends.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flut/app_user.dart';
import 'package:flut/friends_models.dart';
import 'package:flut/friends_page.dart';
import 'package:flut/friends_service.dart';
import 'package:flut/progress_summary.dart';

import 'fake_friends_backend.dart';

FriendSummary _friend(
  String uid,
  String name, {
  int completed = 10,
  int total = 100,
  bool demo = false,
}) => FriendSummary(
  uid: uid,
  name: name,
  completed: completed,
  total: total,
  areas: [
    AreaProgress(label: 'Kitchen', completed: completed, total: total ~/ 2),
    AreaProgress(label: 'Bathroom', completed: 0, total: total ~/ 2),
  ],
  isDemo: demo,
);

FriendRequest _request(
  String from,
  String to, {
  bool accepted = false,
  String? fromName,
  String? toName,
}) => FriendRequest(
  from: from,
  to: to,
  fromName: fromName ?? 'name-$from',
  toName: toName ?? 'name-$to',
  accepted: accepted,
);

const _codeField = Key('friend-code-field');
const _addButton = Key('add-friend-button');

void main() {
  late FakeFriendsBackend backend;
  late StreamController<String?> uids;

  Future<void> show(
    WidgetTester tester, {
    String? uid = 'me',
    bool showDemo = false,
  }) async {
    // A tall screen, so every section is built (lists build lazily).
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    uids = StreamController<String?>.broadcast();
    addTearDown(uids.close);
    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          service: FriendsService(backend),
          uids: uids.stream,
          initialUid: uid,
          showDemo: showDemo,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAddFriend(WidgetTester tester) async {
    await tester.tap(find.byKey(_addButton));
    await tester.pumpAndSettle();
  }

  Future<void> goBack(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
  }

  Future<void> sendCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(_codeField), code);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppUser.setName('Me Myself');
    backend = FakeFriendsBackend();
    backend.addCode('ABC234', 'anna', 'Anna Jansen');
  });

  testWidgets('signed out: asks to sign in and shows nothing private', (
    tester,
  ) async {
    await show(tester, uid: null);

    expect(find.textContaining('Sign in to add friends'), findsOneWidget);
    expect(find.byKey(_addButton), findsNothing);
    expect(find.byKey(const Key('friend-code')), findsNothing);
    expect(find.text('Your friends'), findsNothing);
  });

  testWidgets(
    'signed in: an Add button next to the title opens the add screen',
    (tester) async {
      await show(tester);

      expect(find.byKey(_addButton), findsOneWidget);
      expect(
        find.byKey(const Key('friend-code')),
        findsNothing,
        reason: 'the code lives on the add screen, not the list',
      );

      await openAddFriend(tester);

      expect(find.text('Add a friend'), findsOneWidget);
      expect(find.text('Your friend code'), findsOneWidget);
      expect(find.byKey(const Key('friend-code')), findsOneWidget);
      expect(find.byKey(_codeField), findsOneWidget);
      expect(backend.codeOf['me'], isNotNull);
    },
  );

  testWidgets('the friends list has no code box of its own', (tester) async {
    await show(tester);

    expect(find.byKey(_codeField), findsNothing);
  });

  testWidgets('copying the code puts it on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await show(tester);
    await openAddFriend(tester);

    await tester.tap(find.byTooltip('Copy code'));
    await tester.pumpAndSettle();

    expect(copied, backend.codeOf['me']);
  });

  testWidgets('with no friends it explains how to get some', (tester) async {
    await show(tester);

    expect(find.byKey(const Key('no-friends')), findsOneWidget);
    expect(find.textContaining('Tap Add'), findsOneWidget);
    expect(find.text('Requests'), findsNothing);
  });

  testWidgets('adding a friend by code sends a request', (tester) async {
    await show(tester);
    await openAddFriend(tester);

    await sendCode(tester, 'abc 234');

    expect(find.textContaining('Request sent'), findsOneWidget);
    expect(backend.requests['me_anna']!.toName, 'Anna Jansen');

    await goBack(tester);
    expect(find.text('Waiting for Anna Jansen'), findsOneWidget);
  });

  testWidgets('a wrong code says so and sends nothing', (tester) async {
    await show(tester);
    await openAddFriend(tester);

    await sendCode(tester, 'ZZZ999');

    expect(find.textContaining('No one has that code'), findsOneWidget);
    expect(backend.requests, isEmpty);
  });

  testWidgets('a server problem is explained, not shown raw', (tester) async {
    backend.failLookupWith = StateError('boom: permission-denied');
    await show(tester);
    await openAddFriend(tester);

    await sendCode(tester, 'ABC234');

    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('entering the code of someone who asked you makes you friends', (
    tester,
  ) async {
    backend.putRequest(_request('anna', 'me', fromName: 'Anna Jansen'));
    backend.putFriend(_friend('anna', 'Anna Jansen'));
    await show(tester);
    await openAddFriend(tester);

    await sendCode(tester, 'ABC234');

    expect(find.text("You're now friends!"), findsOneWidget);
    expect(backend.requests['anna_me']!.accepted, isTrue);
  });

  testWidgets('an incoming request can be accepted', (tester) async {
    backend.putRequest(_request('anna', 'me', fromName: 'Anna Jansen'));
    backend.putFriend(
      _friend('anna', 'Anna Jansen', completed: 30, total: 118),
    );
    await show(tester);

    expect(find.text('Anna Jansen wants to be friends'), findsOneWidget);

    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();

    expect(backend.requests['anna_me']!.accepted, isTrue);
    expect(find.text('Anna Jansen wants to be friends'), findsNothing);
    expect(find.text('30/118 swaps completed'), findsOneWidget);
  });

  testWidgets('an incoming request can be declined', (tester) async {
    backend.putRequest(_request('anna', 'me', fromName: 'Anna Jansen'));
    await show(tester);

    await tester.tap(find.byTooltip('Decline'));
    await tester.pumpAndSettle();

    expect(backend.requests, isEmpty);
    expect(find.byKey(const Key('no-friends')), findsOneWidget);
  });

  testWidgets('an outgoing request can be cancelled', (tester) async {
    backend.putRequest(_request('me', 'anna', toName: 'Anna Jansen'));
    await show(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(backend.requests, isEmpty);
  });

  testWidgets('friends show their totals and focus area', (tester) async {
    backend.putRequest(
      _request('me', 'anna', accepted: true, toName: 'Anna Jansen'),
    );
    backend.putFriend(
      _friend('anna', 'Anna Jansen', completed: 43, total: 118),
    );
    await show(tester);

    expect(find.text('Anna Jansen'), findsOneWidget);
    expect(find.text('43/118 swaps completed'), findsOneWidget);
    expect(find.text('Focus: Kitchen'), findsOneWidget);
  });

  testWidgets('a friend whose data cannot be read says so', (tester) async {
    backend.putRequest(
      _request('anna', 'me', accepted: true, fromName: 'Anna Jansen'),
    );
    await show(tester);

    expect(find.textContaining("Can't show Anna Jansen"), findsOneWidget);
  });

  testWidgets('opening a friend shows counts per area and a privacy note', (
    tester,
  ) async {
    backend.putRequest(
      _request('me', 'anna', accepted: true, toName: 'Anna Jansen'),
    );
    backend.putFriend(
      _friend('anna', 'Anna Jansen', completed: 43, total: 118),
    );
    await show(tester);

    await tester.tap(find.text('Anna Jansen'));
    await tester.pumpAndSettle();

    expect(find.text('Progress per area'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.textContaining('names of the swaps'), findsOneWidget);
  });

  testWidgets('removing a friend asks first, then ends the friendship', (
    tester,
  ) async {
    backend.putRequest(
      _request('me', 'anna', accepted: true, toName: 'Anna Jansen'),
    );
    backend.putFriend(_friend('anna', 'Anna Jansen'));
    await show(tester);
    await tester.tap(find.text('Anna Jansen'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove friend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.requests, isNotEmpty, reason: 'cancelling keeps them');

    await tester.tap(find.text('Remove friend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(backend.requests, isEmpty);
    expect(find.byKey(const Key('no-friends')), findsOneWidget);
  });

  testWidgets(
    'demo friends are listed, marked as demo, and cannot be removed',
    (tester) async {
      backend.demo = [_friend('demo-mila', 'Mila Vermeer', demo: true)];
      await show(tester, showDemo: true);

      expect(find.text('Demo friends'), findsOneWidget);
      expect(find.text('Mila Vermeer'), findsOneWidget);
      expect(find.text('Demo'), findsOneWidget);

      await tester.tap(find.text('Mila Vermeer'));
      await tester.pumpAndSettle();

      expect(find.text('Remove friend'), findsNothing);
      expect(find.textContaining('demo friend'), findsOneWidget);
    },
  );

  testWidgets('demo friends are hidden unless switched on', (tester) async {
    backend.demo = [_friend('demo-mila', 'Mila Vermeer', demo: true)];
    await show(tester);

    expect(find.text('Demo friends'), findsNothing);
    expect(find.text('Mila Vermeer'), findsNothing);
  });

  testWidgets('demo friends also show when signed out', (tester) async {
    backend.demo = [_friend('demo-mila', 'Mila Vermeer', demo: true)];
    await show(tester, uid: null, showDemo: true);

    expect(find.text('Mila Vermeer'), findsOneWidget);
  });

  testWidgets('signing in while the screen is open brings in the Add button', (
    tester,
  ) async {
    await show(tester, uid: null);
    expect(find.byKey(_addButton), findsNothing);

    uids.add('me');
    await tester.pumpAndSettle();

    expect(find.byKey(_addButton), findsOneWidget);
    expect(
      backend.codeOf['me'],
      isNotNull,
      reason: 'the account gets its code as soon as it signs in',
    );
  });
}
