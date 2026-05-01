import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'challenge_model.dart';
import 'challenge_repository.dart';
import 'friends_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ChallengeRepository _repository = ChallengeRepository();
  Map<String, Challenge> _challenges = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final challenges = await _repository.loadChallenges();
    if (!mounted) return;
    setState(() {
      _challenges = challenges;
      _isLoading = false;
    });
  }

  int get _totalItems {
    return _challenges.values.fold(
      0,
      (total, challenge) => total + challenge.checklist.length,
    );
  }

  int get _completedItems {
    return _challenges.values.fold(
      0,
      (total, challenge) =>
          total + challenge.checklist.where((item) => item.isCompleted).length,
    );
  }

  double get _progress {
    if (_totalItems == 0) return 0;
    return _completedItems / _totalItems;
  }

  List<_CategoryProgress> get _categoryProgress {
    final start = _challenges['Start'];
    if (start == null) return [];

    return start.unlocks
        .map((label) => _buildCategoryProgress(label))
        .whereType<_CategoryProgress>()
        .toList();
  }

  _CategoryProgress? _buildCategoryProgress(String rootLabel) {
    final visited = <String>{};
    var completed = 0;
    var total = 0;

    void visit(String label) {
      final challenge = _challenges[label];
      if (challenge == null || !visited.add(label)) return;

      total += challenge.checklist.length;
      completed += challenge.checklist.where((item) => item.isCompleted).length;

      for (final child in challenge.unlocks) {
        visit(child);
      }
    }

    visit(rootLabel);
    if (total == 0) return null;
    return _CategoryProgress(
      label: rootLabel,
      completed: completed,
      total: total,
    );
  }

  List<ChecklistItem> get _completedExamples {
    return _challenges.values
        .expand((challenge) => challenge.checklist)
        .where((item) => item.isCompleted)
        .take(5)
        .toList();
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
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
                          children: [
                            _buildProfileCard(),
                            const SizedBox(height: 14),
                            _buildFriendsCard(),
                            const SizedBox(height: 14),
                            _buildCategoryCard(),
                            const SizedBox(height: 14),
                            _buildRecentCard(),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsCard() {
    return _GlassPanel(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const FriendsPage()),
          );
        },
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.people_alt, color: Colors.greenAccent),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Friends',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'See shared progress and cheer each other on.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProgressAvatar(progress: _progress, size: 82),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Thomas Pennock',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'EcoSteps profile',
                      style: TextStyle(
                        color: Colors.greenAccent.withOpacity(0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total progress',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$_completedItems/$_totalItems',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progress,
            minHeight: 6,
            backgroundColor: Colors.white12,
            color: Colors.greenAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard() {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Progress By Area',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          for (final category in _categoryProgress) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  category.label,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                Text(
                  '${category.completed}/${category.total}',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: category.progress,
              minHeight: 5,
              backgroundColor: Colors.white12,
              color: Colors.greenAccent,
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentCard() {
    final completed = _completedExamples;

    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Checked Off',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (completed.isEmpty)
            const Text(
              'Nothing checked off yet.',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            )
          else
            for (final item in completed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.greenAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
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

class _ProgressAvatar extends StatelessWidget {
  final double progress;
  final double size;

  const _ProgressAvatar({required this.progress, required this.size});

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
            child: const Center(
              child: Text(
                'TP',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
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

class _GlassPanel extends StatelessWidget {
  final Widget child;

  const _GlassPanel({required this.child});

  @override
  Widget build(BuildContext context) {
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
          child: child,
        ),
      ),
    );
  }
}

class _CategoryProgress {
  final String label;
  final int completed;
  final int total;

  const _CategoryProgress({
    required this.label,
    required this.completed,
    required this.total,
  });

  double get progress {
    if (total == 0) return 0;
    return completed / total;
  }
}
