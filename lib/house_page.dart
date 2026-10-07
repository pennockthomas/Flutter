import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'app_user.dart';
import 'fading_edge_scroll_view.dart';
import 'friends_models.dart';
import 'glass_panel.dart';
import 'house_chart.dart';
import 'house_models.dart';
import 'house_stats.dart';
import 'houses_controller.dart';
import 'houses_service.dart';

/// A house's page, opened from the stats button on its tree: a back button
/// over [HouseView].
class HousePage extends StatelessWidget {
  const HousePage({super.key, required this.house, required this.controller});

  final House house;
  final HousesController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Rebuilds with the house, so a rename shows straight away, and
          // closes the page if you leave or are removed.
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final current = controller.houses
                  .where((h) => h.id == house.id)
                  .firstOrNull;
              if (current == null) return const SizedBox.shrink();
              return HouseView(
                key: ValueKey(house.id),
                house: current,
                controller: controller,
              );
            },
          ),
          SafeArea(
            child: Padding(
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
          ),
        ],
      ),
    );
  }
}

/// One house: its name, who is in it, invitations, who ticked the most swaps
/// in the shared tree, and a graph of swaps over time. Everyone in a house
/// has equal rights.
class HouseView extends StatefulWidget {
  const HouseView({
    super.key,
    required this.house,
    required this.controller,
    this.now,
  });

  final House house;
  final HousesController controller;

  /// For tests: the moment to treat as now.
  final DateTime? now;

  @override
  State<HouseView> createState() => _HouseViewState();
}

enum _Ranking { allTime, thisWeek }

class _HouseViewState extends State<HouseView> {
  late final Stream<Map<String, String>> _names = widget.controller.service
      .watchMemberNames(widget.house.id)
      .asBroadcastStream();
  late final Stream<List<HouseSwap>> _swaps = widget.controller.service
      .watchSwaps(widget.house.id)
      .asBroadcastStream();
  late final Stream<List<HouseInvite>> _houseInvites = widget.controller.service
      .watchHouseInvites(widget.house.id)
      .asBroadcastStream();
  late final Stream<List<FriendRequest>> _friendRequests = widget
      .controller
      .friends
      .watchRequests(widget.controller.uid ?? '')
      .asBroadcastStream();

  _Ranking _ranking = _Ranking.allTime;
  ChartRange _range = ChartRange.month;

  HousesService get _service => widget.controller.service;
  String get _me => widget.controller.uid ?? '';
  House get _house => widget.house;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameHouseDialog(initial: _house.name),
    );
    if (name == null) return;
    try {
      await _service.rename(_house, name);
    } catch (e) {
      _say(describeHouseError(e));
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF101510),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _leave() async {
    final last = _house.memberUids.length <= 1;
    final ok = await _confirm(
      'Leave ${_house.name}?',
      last
          ? 'You are the last person here, so the house will be deleted.'
          : "You won't see this house's stats any more. Someone there can "
                'invite you back.',
      'Leave',
    );
    if (!ok) return;
    try {
      await widget.controller.leave(_house);
    } catch (e) {
      _say(describeHouseError(e));
    }
  }

  Future<void> _remove(HouseMember member) async {
    final ok = await _confirm(
      'Remove ${member.name}?',
      'They will be taken out of ${_house.name}. A friend there can invite '
          'them again.',
      'Remove',
    );
    if (!ok) return;
    try {
      await _service.removeMember(_house, member.uid);
    } catch (e) {
      _say(describeHouseError(e));
    }
  }

  Future<void> _cancelInvite(HouseInvite invite) async {
    try {
      await _service.dropInvite(invite);
    } catch (e) {
      _say(describeHouseError(e));
    }
  }

  Future<void> _invite(
    List<({String uid, String name})> choices,
    List<HouseInvite> pending,
  ) async {
    final friend = await showModalBottomSheet<({String uid, String name})>(
      context: context,
      backgroundColor: const Color(0xFF101510),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          children: [
            const Text(
              'Invite a friend',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (choices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No friends to invite. Add friends first, from Profile → '
                  'Friends. Everyone already here, or already invited, is '
                  'left out.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            for (final friend in choices)
              ListTile(
                key: Key('invite-${friend.uid}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.person_add_alt_1,
                  color: Colors.white70,
                ),
                title: Text(
                  friend.name,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(sheetContext, friend),
              ),
          ],
        ),
      ),
    );
    if (friend == null) return;
    try {
      await _service.invite(
        house: _house,
        fromUid: _me,
        fromName: AppUser.hasName ? AppUser.name : 'EcoSteps friend',
        friendUid: friend.uid,
        pendingInvites: pending,
      );
      _say('Invitation sent to ${friend.name}.');
    } catch (e) {
      _say(describeHouseError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
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
          child: FadingEdgeScrollView(
            child: StreamBuilder<Map<String, String>>(
              stream: _names,
              builder: (context, namesSnapshot) =>
                  StreamBuilder<List<HouseSwap>>(
                    stream: _swaps,
                    builder: (context, swapsSnapshot) {
                      final names = {...?namesSnapshot.data};
                      // Before your own name has been shared, use the local one.
                      if (AppUser.hasName)
                        names.putIfAbsent(_me, () => AppUser.name);
                      // In the house's own order, so colours stay with people.
                      final members = deriveMembers(
                        memberUids: _house.memberUids,
                        names: names,
                        swaps: swapsSnapshot.data ?? const [],
                        totalSwaps:
                            widget.controller.houseStore?.totalItems ?? 0,
                      );
                      return ListView(
                        // Leaves room for the back button above.
                        padding: const EdgeInsets.fromLTRB(20, 64, 20, 26),
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 14),
                          _buildMembers(members),
                          const SizedBox(height: 14),
                          _buildLeaderboard(members),
                          const SizedBox(height: 14),
                          _buildGraph(members),
                          const SizedBox(height: 8),
                          TextButton(
                            key: const Key('leave-house'),
                            onPressed: _leave,
                            child: const Text(
                              'Leave house',
                              style: TextStyle(color: Colors.orangeAccent),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return GlassPanel(
      child: Row(
        children: [
          const Icon(Icons.home_rounded, color: Colors.greenAccent, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              key: const Key('rename-house'),
              onTap: _rename,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _house.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.edit_outlined,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ],
                  ),
                  Text(
                    _house.memberUids.length == 1
                        ? '1 person'
                        : '${_house.memberUids.length} people',
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _buildMembers(List<HouseMember> members) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('In this house'),
          for (var i = 0; i < members.length; i++) _memberRow(members[i], i),
          _buildInvites(),
        ],
      ),
    );
  }

  Widget _memberRow(HouseMember member, int index) {
    final isMe = member.uid == _me;
    final color = memberColors[index % memberColors.length];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${member.name} (you)' : member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                Text(
                  '${member.completed}/${member.total} swaps · '
                  '${doneThisWeek(member, now: widget.now)} this week',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          if (!isMe)
            IconButton(
              key: Key('remove-${member.uid}'),
              tooltip: 'Remove from house',
              onPressed: () => _remove(member),
              icon: const Icon(
                Icons.person_remove_outlined,
                color: Colors.white54,
                size: 22,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInvites() {
    return StreamBuilder<List<FriendRequest>>(
      stream: _friendRequests,
      builder: (context, friendSnapshot) {
        final friends = HousesService.friendsOf(
          _me,
          friendSnapshot.data ?? const [],
        );
        return StreamBuilder<List<HouseInvite>>(
          stream: _houseInvites,
          builder: (context, inviteSnapshot) {
            final pending = inviteSnapshot.data ?? const <HouseInvite>[];
            final choices = HousesService.invitableFriends(
              house: _house,
              friends: friends,
              pendingInvites: pending,
            );
            String nameOf(String uid) {
              for (final friend in friends) {
                if (friend.uid == uid) return friend.name;
              }
              return 'a friend';
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final invite in pending)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.hourglass_empty,
                          color: Colors.white38,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Invited ${nameOf(invite.to)}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        TextButton(
                          key: Key('cancel-invite-${invite.to}'),
                          onPressed: () => _cancelInvite(invite),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                _house.isFull
                    ? Text(
                        'This house is full (${House.maxMembers} people).',
                        style: const TextStyle(color: Colors.white60),
                      )
                    : FilledButton.tonalIcon(
                        key: const Key('invite-friend'),
                        onPressed: () => _invite(choices, pending),
                        icon: const Icon(Icons.person_add_alt_1, size: 20),
                        label: const Text('Invite a friend'),
                      ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLeaderboard(List<HouseMember> members) {
    final ranked = rankMembers(
      members,
      _ranking == _Ranking.allTime
          ? (m) => m.completed
          : (m) => doneThisWeek(m, now: widget.now),
    );
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Who did the most swaps'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const Key('ranking-all'),
                label: const Text('All time'),
                selected: _ranking == _Ranking.allTime,
                onSelected: (_) => setState(() => _ranking = _Ranking.allTime),
              ),
              ChoiceChip(
                key: const Key('ranking-week'),
                label: const Text('This week'),
                selected: _ranking == _Ranking.thisWeek,
                onSelected: (_) => setState(() => _ranking = _Ranking.thisWeek),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final row in ranked)
            Padding(
              key: Key('rank-${row.member.uid}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: row.rank == 1 && row.value > 0
                        ? const Icon(
                            Icons.emoji_events_rounded,
                            color: Colors.amberAccent,
                            size: 22,
                          )
                        : Text(
                            '${row.rank}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 16,
                            ),
                          ),
                  ),
                  Expanded(
                    child: Text(
                      row.member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  Text(
                    '${row.value}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGraph(List<HouseMember> members) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Swaps over time'),
          Wrap(
            spacing: 8,
            children: [
              for (final range in ChartRange.values)
                ChoiceChip(
                  key: Key('range-${range.name}'),
                  label: Text(range.label),
                  selected: _range == range,
                  onSelected: (_) => setState(() => _range = range),
                ),
            ],
          ),
          const SizedBox(height: 10),
          HouseChart(members: members, range: _range, today: widget.now),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (var i = 0; i < members.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: memberColors[i % memberColors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      members[i].name,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RenameHouseDialog extends StatefulWidget {
  const _RenameHouseDialog({required this.initial});

  final String initial;

  @override
  State<_RenameHouseDialog> createState() => _RenameHouseDialogState();
}

class _RenameHouseDialogState extends State<_RenameHouseDialog> {
  // Owned here, so it's disposed only once the dialog has animated away.
  late final _controller = TextEditingController(text: widget.initial);

  bool get _isValid => House.cleanName(_controller.text) != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_isValid) Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF101510),
      title: const Text('House name', style: TextStyle(color: Colors.white)),
      content: TextField(
        key: const Key('house-name-field'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        maxLength: House.maxNameLength,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          counterStyle: const TextStyle(color: Colors.white54),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.greenAccent),
          ),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isValid ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
