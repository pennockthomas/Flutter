import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'challenge_model.dart';
import 'challenge_store.dart';
import 'fading_edge_scroll_view.dart';
import 'notifications.dart';

class ProgressRegisterPage extends StatefulWidget {
  const ProgressRegisterPage({super.key});

  @override
  State<ProgressRegisterPage> createState() => _ProgressRegisterPageState();
}

class _ProgressRegisterPageState extends State<ProgressRegisterPage> {
  final TextEditingController _searchController = TextEditingController();

  Map<String, Challenge> _challenges = {};
  Map<String, String> _parentByChallenge = {};
  List<_ChallengeRow> _orderedRows = [];
  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    ChallengeStore.instance.addListener(_onChallengesChanged);
    _loadChallenges();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  void _onChallengesChanged() {
    if (!mounted) return;
    _applyChallenges(ChallengeStore.instance.challenges);
  }

  Future<void> _loadChallenges() async {
    try {
      final challenges = await ChallengeStore.instance.ensureLoaded();
      if (!mounted) return;
      _applyChallenges(challenges, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _applyChallenges(Map<String, Challenge> challenges, {bool? isLoading}) {
    setState(() {
      _challenges = challenges;
      _parentByChallenge = _buildParentMap(challenges);
      _orderedRows = _buildOrderedRows(challenges);
      if (isLoading != null) _isLoading = isLoading;
    });
  }

  Map<String, String> _buildParentMap(Map<String, Challenge> challenges) {
    final parentByChallenge = <String, String>{};
    for (final challenge in challenges.values) {
      for (final child in challenge.unlocks) {
        parentByChallenge.putIfAbsent(child, () => challenge.label);
      }
    }
    return parentByChallenge;
  }

  List<_ChallengeRow> _buildOrderedRows(Map<String, Challenge> challenges) {
    final rows = <_ChallengeRow>[];
    final visited = <String>{};

    void visit(String label, int depth) {
      final challenge = challenges[label];
      if (challenge == null || !visited.add(label)) return;

      if (challenge.checklist.isNotEmpty) {
        rows.add(_ChallengeRow(challenge: challenge, depth: depth));
      }

      for (final child in challenge.unlocks) {
        visit(child, depth + 1);
      }
    }

    visit('Start', 0);

    for (final challenge in challenges.values) {
      if (!visited.contains(challenge.label)) {
        visit(challenge.label, 0);
      }
    }

    return rows;
  }

  bool _matchesQuery(Challenge challenge, ChecklistItem item) {
    if (_query.isEmpty) return true;

    final parent = _parentByChallenge[challenge.label] ?? '';
    return challenge.label.toLowerCase().contains(_query) ||
        challenge.description.toLowerCase().contains(_query) ||
        parent.toLowerCase().contains(_query) ||
        item.label.toLowerCase().contains(_query);
  }

  List<_VisibleChallengeRow> get _visibleRows {
    final visibleRows = <_VisibleChallengeRow>[];

    for (final row in _orderedRows) {
      final items = <_VisibleChecklistItem>[];
      for (var i = 0; i < row.challenge.checklist.length; i++) {
        final item = row.challenge.checklist[i];
        if (_matchesQuery(row.challenge, item)) {
          items.add(_VisibleChecklistItem(index: i, item: item));
        }
      }

      if (items.isNotEmpty) {
        visibleRows.add(_VisibleChallengeRow(row: row, items: items));
      }
    }

    return visibleRows;
  }

  Future<void> _toggleItem({
    required Challenge challenge,
    required int itemIndex,
    required bool isCompleted,
  }) async {
    final updatedChecklist = [...challenge.checklist];
    updatedChecklist[itemIndex] = updatedChecklist[itemIndex].copyWith(
      isCompleted: isCompleted,
    );
    final updatedChallenge = challenge.copyWith(checklist: updatedChecklist);
    final updatedChallenges = {
      ..._challenges,
      challenge.label: updatedChallenge,
    };
    _applyChallenges(updatedChallenges);
    if (!challenge.isFullyCompleted && updatedChallenge.isFullyCompleted) {
      await AppSettings.playSoundEffectIfEnabled(AppSounds.challengeFinished);
      await NotificationService.instance.showMilestoneAlert(
        title: 'Challenge complete!',
        body: 'You finished every swap in ${challenge.label}.',
      );
    } else {
      await AppSettings.playSystemSoundIfEnabled();
    }
    await ChallengeStore.instance.save(updatedChallenges);
  }

  @override
  void dispose() {
    ChallengeStore.instance.removeListener(_onChallengesChanged);
    _searchController.dispose();
    super.dispose();
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
          const AppBackgroundOverlay(fallbackDarkness: 0.36),
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.greenAccent),
                  )
                : Column(
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                        child: _buildHeader(),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: _buildSearchField(),
                      ),
                      Expanded(
                        child: _visibleRows.isEmpty
                            ? const Center(
                                child: Text(
                                  'No checklist items found',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                              )
                            : FadingEdgeScrollView(
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    24,
                                  ),
                                  itemCount: _visibleRows.length,
                                  itemBuilder: (context, index) {
                                    return _buildChallengeSection(
                                      _visibleRows[index],
                                    );
                                  },
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

  Widget _buildHeader() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Progress Register',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Mark everything you already use, grouped by its place in the tree.',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Completed',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${ChallengeStore.instance.completedItems}/${ChallengeStore.instance.totalItems}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: ChallengeStore.instance.progress,
                minHeight: 6,
                backgroundColor: Colors.white12,
                color: Colors.greenAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.greenAccent,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            prefixIcon: const Icon(Icons.search, color: Colors.white70),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: _searchController.clear,
                  ),
            hintText: 'Search swaps, rooms, or parent bubbles',
            hintStyle: const TextStyle(color: Colors.white54),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.greenAccent),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChallengeSection(_VisibleChallengeRow visibleRow) {
    final challenge = visibleRow.row.challenge;
    final completed = challenge.checklist
        .where((item) => item.isCompleted)
        .length;
    final parent = _parentByChallenge[challenge.label];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              challenge.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '$completed/${challenge.checklist.length}',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (parent != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Parent: $parent',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                for (final visibleItem in visibleRow.items)
                  CheckboxListTile(
                    dense: true,
                    visualDensity: const VisualDensity(
                      horizontal: 0,
                      vertical: -2,
                    ),
                    value: visibleItem.item.isCompleted,
                    onChanged: (value) => _toggleItem(
                      challenge: challenge,
                      itemIndex: visibleItem.index,
                      isCompleted: value ?? false,
                    ),
                    activeColor: Colors.greenAccent,
                    checkColor: Colors.black,
                    controlAffinity: ListTileControlAffinity.trailing,
                    contentPadding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                    title: Text(
                      visibleItem.item.label,
                      style: TextStyle(
                        color: visibleItem.item.isCompleted
                            ? Colors.white54
                            : Colors.white,
                        fontSize: 15,
                        decoration: visibleItem.item.isCompleted
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChallengeRow {
  final Challenge challenge;
  final int depth;

  const _ChallengeRow({required this.challenge, required this.depth});
}

class _VisibleChallengeRow {
  final _ChallengeRow row;
  final List<_VisibleChecklistItem> items;

  const _VisibleChallengeRow({required this.row, required this.items});
}

class _VisibleChecklistItem {
  final int index;
  final ChecklistItem item;

  const _VisibleChecklistItem({required this.index, required this.item});
}
