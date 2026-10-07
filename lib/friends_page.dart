import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_page_route.dart';
import 'app_settings.dart';
import 'add_friend_page.dart';
import 'app_user.dart';
import 'auth_service.dart';
import 'fading_edge_scroll_view.dart';
import 'friends_firestore.dart';
import 'friends_models.dart';
import 'friends_service.dart';
import 'glass_panel.dart';
import 'sign_in_page.dart';

/// Preference: also show the made-up demo friends (Settings → Developer).
const String showDemoFriendsKey = 'friends.show_demo';

/// Friends: add people by their friend code, answer requests, and see how
/// each friend is doing: totals and counts per area, never swap names.
///
/// [service], [uids], [initialUid] and [showDemo] let tests run the screen
/// without Firebase; the app uses the defaults.
class FriendsPage extends StatefulWidget {
  const FriendsPage({
    super.key,
    this.service,
    this.uids,
    this.initialUid,
    this.showDemo,
  });

  final FriendsService? service;
  final Stream<String?>? uids;
  final String? initialUid;
  final bool? showDemo;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  late final FriendsService _service =
      widget.service ?? FriendsService(FirestoreFriendsBackend());
  StreamSubscription<String?>? _uidSubscription;
  String? _uid;

  Stream<List<FriendRequest>>? _requests;

  bool _showDemo = false;
  Future<List<FriendSummary>>? _demo;

  @override
  void initState() {
    super.initState();
    _uid = widget.initialUid ?? AuthService.instance.currentUser?.uid;
    _startFor(_uid);
    _uidSubscription =
        (widget.uids ??
                AuthService.instance.authStateChanges.map((user) => user?.uid))
            .listen((uid) {
              if (uid == _uid) return;
              setState(() {
                _uid = uid;
                _startFor(uid);
              });
            });
    AppUser.listenable.addListener(_nameChanged);
    _loadDemoSetting();
  }

  @override
  void dispose() {
    _uidSubscription?.cancel();
    AppUser.listenable.removeListener(_nameChanged);
    super.dispose();
  }

  String get _myName => AppUser.hasName ? AppUser.name : 'EcoSteps friend';

  void _startFor(String? uid) {
    if (uid == null) {
      _requests = null;
      return;
    }
    _syncMyCode(uid);
    _requests = _service.watchRequests(uid).asBroadcastStream();
  }

  /// Makes sure this account has a friend code, and that the name stored next
  /// to it is the current one (so people who look the code up see it).
  Future<void> _syncMyCode(String uid) async {
    try {
      await _service.myCode(uid, _myName);
    } catch (e) {
      debugPrint('Could not sync the friend code: $e');
    }
  }

  void _nameChanged() {
    final uid = _uid;
    if (uid != null && mounted) _syncMyCode(uid);
  }

  Future<void> _loadDemoSetting() async {
    var show = widget.showDemo;
    if (show == null) {
      final prefs = await SharedPreferences.getInstance();
      show = prefs.getBool(showDemoFriendsKey) ?? false;
    }
    if (!mounted || !show) return;
    setState(() {
      _showDemo = true;
      _demo = _service.loadDemoFriends();
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _answer(Future<void> Function() action, String failure) async {
    try {
      await action();
    } catch (e) {
      _say(failure);
    }
  }

  void _openFriend(FriendSummary friend, {FriendRequest? request}) {
    Navigator.push(
      context,
      appPageRoute(
        _FriendProfilePage(
          friend: friend,
          onRemove: request == null ? null : () => _service.remove(request),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SizedBox.expand(
            child: Image.asset(
              'assets/background.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: Colors.blueGrey[900]),
            ),
          ),
          const AppBackgroundOverlay(fallbackDarkness: 0.32),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 10),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Expanded(
                  child: FadingEdgeScrollView(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
                      children: [
                        _buildHeader(uid),
                        if (uid == null) ...[
                          const SizedBox(height: 14),
                          _buildSignInPrompt(),
                        ] else ...[
                          _buildFriends(uid),
                        ],
                        if (_showDemo) _buildDemo(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String? uid) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Friends',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (uid != null)
                FilledButton.tonalIcon(
                  key: const Key('add-friend-button'),
                  onPressed: () => Navigator.push(
                    context,
                    appPageRoute(AddFriendPage(service: _service, uid: uid)),
                  ),
                  icon: const Icon(Icons.person_add_alt_1, size: 20),
                  label: const Text('Add'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            uid == null
                ? 'Sign in to add friends and see how they are doing.'
                : "Friends see your totals and your progress per area. "
                      "They never see the names of your swaps.",
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInPrompt() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AuthService.instance.isAvailable
                ? 'Friends need an account, so your progress can be shared '
                      'with people you choose.'
                : 'Accounts are not available right now.',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          if (AuthService.instance.isAvailable) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () =>
                  Navigator.push(context, appPageRoute(const SignInPage())),
              child: const Text('Sign in or create an account'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _retryRow(String message, VoidCallback onRetry) {
    return Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 14),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }

  Widget _buildFriends(String uid) {
    return StreamBuilder<List<FriendRequest>>(
      stream: _requests,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: GlassPanel(
              child: _retryRow(
                "Couldn't load your friends.",
                () => setState(() => _startFor(_uid)),
              ),
            ),
          );
        }
        final requests = snapshot.data;
        if (requests == null) {
          return const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final incoming = [
          for (final r in requests)
            if (!r.accepted && r.to == uid) r,
        ];
        final outgoing = [
          for (final r in requests)
            if (!r.accepted && r.from == uid) r,
        ];
        final friends = [
          for (final r in requests)
            if (r.accepted) r,
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (incoming.isNotEmpty || outgoing.isNotEmpty) ...[
              const SizedBox(height: 18),
              _sectionTitle('Requests'),
              for (final request in incoming) _incomingTile(request),
              for (final request in outgoing) _outgoingTile(request),
            ],
            const SizedBox(height: 18),
            _sectionTitle('Your friends'),
            if (friends.isEmpty)
              GlassPanel(
                child: const Text(
                  'No friends yet. Tap Add to share your friend code or type '
                  "someone else's. You will see how they are doing once they "
                  'accept.',
                  key: Key('no-friends'),
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              )
            else
              for (final request in friends)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _friendTile(uid, request),
                ),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _incomingTile(FriendRequest request) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${request.fromName} wants to be friends',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            IconButton(
              tooltip: 'Accept',
              onPressed: () => _answer(
                () => _service.accept(request),
                "Couldn't accept the request. Try again.",
              ),
              icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
            ),
            IconButton(
              tooltip: 'Decline',
              onPressed: () => _answer(
                () => _service.remove(request),
                "Couldn't decline the request. Try again.",
              ),
              icon: const Icon(Icons.cancel_outlined, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outgoingTile(FriendRequest request) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Waiting for ${request.toName}',
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
            TextButton(
              onPressed: () => _answer(
                () => _service.remove(request),
                "Couldn't cancel the request. Try again.",
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _friendTile(String me, FriendRequest request) {
    final otherUid = request.otherUid(me);
    final fallback = request.otherName(me);
    return StreamBuilder<FriendSummary?>(
      stream: _service.watchFriend(otherUid, fallbackName: fallback),
      builder: (context, snapshot) {
        final friend = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting &&
            friend == null) {
          return GlassPanel(
            child: Text(
              fallback,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          );
        }
        if (friend == null) {
          return GlassPanel(
            child: Text(
              "Can't show $fallback right now.",
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          );
        }
        return _FriendCard(
          friend: friend,
          onTap: () => _openFriend(friend, request: request),
        );
      },
    );
  }

  Widget _buildDemo() {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Demo friends'),
          FutureBuilder<List<FriendSummary>>(
            future: _demo,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return GlassPanel(
                  child: _retryRow(
                    "Couldn't load the demo friends.",
                    () => setState(() => _demo = _service.loadDemoFriends()),
                  ),
                );
              }
              final demo = snapshot.data;
              if (demo == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (demo.isEmpty) {
                return const GlassPanel(
                  child: Text(
                    'There are no demo friends yet. Create them under '
                    'Settings → Developer.',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                );
              }
              return Column(
                children: [
                  for (final friend in demo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _FriendCard(
                        friend: friend,
                        onTap: () => _openFriend(friend),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  final FriendSummary friend;
  final VoidCallback onTap;

  const _FriendCard({required this.friend, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final focus = friend.focus;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _FriendAvatar(
                initials: friend.initials,
                progress: friend.progress,
                size: 66,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            friend.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (friend.isDemo) ...[
                          const SizedBox(width: 8),
                          const _DemoChip(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${friend.completed}/${friend.total} swaps completed',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (focus != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        'Focus: $focus',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoChip extends StatelessWidget {
  const _DemoChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white38),
      ),
      child: const Text(
        'Demo',
        style: TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }
}

/// One friend: totals and counts per area. [onRemove] is null for demo
/// friends, who can't be removed.
class _FriendProfilePage extends StatelessWidget {
  final FriendSummary friend;
  final Future<void> Function()? onRemove;

  const _FriendProfilePage({required this.friend, this.onRemove});

  Future<void> _confirmRemove(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF101510),
        title: Text(
          'Remove ${friend.name}?',
          style: const TextStyle(color: Colors.white),
        ),
        content: const Text(
          "You won't see each other's progress any more. You can add each "
          'other again later with a friend code.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await onRemove!();
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't remove them. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SizedBox.expand(
            child: Image.asset(
              'assets/background.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: Colors.blueGrey[900]),
            ),
          ),
          const AppBackgroundOverlay(fallbackDarkness: 0.32),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 10),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Expanded(
                  child: FadingEdgeScrollView(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
                      children: [
                        GlassPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _FriendAvatar(
                                    initials: friend.initials,
                                    progress: friend.progress,
                                    size: 82,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          friend.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${friend.completed}/${friend.total} swaps completed',
                                          style: const TextStyle(
                                            color: Colors.greenAccent,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              LinearProgressIndicator(
                                value: friend.progress,
                                minHeight: 6,
                                backgroundColor: Colors.white12,
                                color: Colors.greenAccent,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        GlassPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Progress per area',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (friend.areas.isEmpty)
                                const Text(
                                  'No progress to show yet.',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              for (final area in friend.areas) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      area.label,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      '${area.completed}/${area.total}',
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: area.progress,
                                  minHeight: 5,
                                  backgroundColor: Colors.white12,
                                  color: Colors.greenAccent,
                                ),
                                const SizedBox(height: 14),
                              ],
                              const Text(
                                'You see totals and counts only. The names of '
                                'the swaps someone has done stay private.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onRemove != null) ...[
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: () => _confirmRemove(context),
                            child: const Text(
                              'Remove friend',
                              style: TextStyle(color: Colors.orangeAccent),
                            ),
                          ),
                        ],
                        if (friend.isDemo) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'This is a demo friend, made up to show how the '
                            'Friends screen works.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  final String initials;
  final double progress;
  final double size;

  const _FriendAvatar({
    required this.initials,
    required this.progress,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 4,
              backgroundColor: Colors.white12,
              color: Colors.greenAccent,
            ),
          ),
          Container(
            width: size - 12,
            height: size - 12,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size < 70 ? 16 : 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
