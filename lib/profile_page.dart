import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'app_page_route.dart';
import 'app_user.dart';
import 'auth_service.dart';
import 'challenge_model.dart';
import 'challenge_store.dart';
import 'friends_page.dart';
import 'fading_edge_scroll_view.dart';
import 'glass_panel.dart';
import 'sign_in_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, Challenge> _challenges = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    ChallengeStore.instance.addListener(_onChallengesChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    ChallengeStore.instance.removeListener(_onChallengesChanged);
    super.dispose();
  }

  void _onChallengesChanged() {
    if (!mounted) return;
    setState(() => _challenges = ChallengeStore.instance.challenges);
  }

  Future<void> _loadProfile() async {
    try {
      final challenges = await ChallengeStore.instance.ensureLoaded();
      if (!mounted) return;
      setState(() {
        _challenges = challenges;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
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
          const AppBackgroundOverlay(fallbackDarkness: 0.32),
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
                        child: FadingEdgeScrollView(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
                            children: [
                              _buildAccountCard(),
                              const SizedBox(height: 14),
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
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      initialData: AuthService.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        return GlassPanel(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: Icon(
                  user == null ? Icons.person_outline : Icons.check_circle,
                  color: user == null ? Colors.white70 : Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user == null ? 'Not signed in' : 'Signed in',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user == null
                          ? 'Sign in to sync progress & add friends'
                          : (user.email ?? user.displayName ?? 'Apple account'),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (user == null) const SizedBox(width: 12),
              if (user == null)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                  ),
                  onPressed: () {
                    Navigator.push(context, appPageRoute(const SignInPage()));
                  },
                  child: const Text('Sign In'),
                )
              else
                TextButton(
                  onPressed: () => AuthService.instance.signOut(),
                  child: const Text(
                    'Sign Out',
                    style: TextStyle(color: Colors.orangeAccent),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFriendsCard() {
    return GlassPanel(
      child: InkWell(
        onTap: () {
          Navigator.push(context, appPageRoute(const FriendsPage()));
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
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProgressAvatar(
                progress: ChallengeStore.instance.progress,
                size: 82,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppUser.name,
                      style: const TextStyle(
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
    );
  }

  Widget _buildCategoryCard() {
    return GlassPanel(
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

    return GlassPanel(
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
            child: Center(
              child: Text(
                AppUser.initials,
                style: const TextStyle(
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
