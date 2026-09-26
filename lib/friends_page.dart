import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'app_page_route.dart';
import 'fading_edge_scroll_view.dart';
import 'glass_panel.dart';

class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  static const List<_FriendProfile> _friends = [
    _FriendProfile(
      name: 'Mila Vermeer',
      initials: 'MV',
      completed: 43,
      total: 118,
      focus: 'Kitchen',
      message: 'Swapped to glass jars and metal lunch boxes.',
      recentItems: ['Glass jars', 'Metal lunch box', 'Wooden dish brush'],
      areaProgress: [
        _FriendAreaProgress(label: 'Kitchen', completed: 24, total: 49),
        _FriendAreaProgress(label: 'Bathroom', completed: 9, total: 28),
        _FriendAreaProgress(label: 'On-The-Go', completed: 10, total: 41),
      ],
    ),
    _FriendProfile(
      name: 'Sam de Vries',
      initials: 'SD',
      completed: 67,
      total: 118,
      focus: 'On-The-Go',
      message: 'Building a zero-waste travel kit.',
      recentItems: ['Reusable coffee cup', 'Metal cutlery set', 'Cotton tote'],
      areaProgress: [
        _FriendAreaProgress(label: 'Kitchen', completed: 21, total: 49),
        _FriendAreaProgress(label: 'Bathroom', completed: 15, total: 28),
        _FriendAreaProgress(label: 'On-The-Go', completed: 31, total: 41),
      ],
    ),
    _FriendProfile(
      name: 'Lena Bakker',
      initials: 'LB',
      completed: 18,
      total: 118,
      focus: 'Bathroom',
      message: 'Just getting started with personal care swaps.',
      recentItems: ['Bamboo toothbrush', 'Solid shampoo bar'],
      areaProgress: [
        _FriendAreaProgress(label: 'Kitchen', completed: 5, total: 49),
        _FriendAreaProgress(label: 'Bathroom', completed: 10, total: 28),
        _FriendAreaProgress(label: 'On-The-Go', completed: 3, total: 41),
      ],
    ),
  ];

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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Friends',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Preview only — these are sample profiles. Real friends and sharing are not connected yet.',
                          style: TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: FadingEdgeScrollView(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
                      itemCount: _friends.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _FriendCard(friend: _friends[index]);
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
}

class _FriendCard extends StatelessWidget {
  final _FriendProfile friend;

  const _FriendCard({required this.friend});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            appPageRoute(_FriendProfilePage(friend: friend)),
          );
        },
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
                    Text(
                      friend.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
                    const SizedBox(height: 5),
                    Text(
                      'Focus: ${friend.focus}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
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

class _FriendProfilePage extends StatelessWidget {
  final _FriendProfile friend;

  const _FriendProfilePage({required this.friend});

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
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 26,
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
                              const SizedBox(height: 18),
                              Text(
                                friend.message,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                  height: 1.35,
                                ),
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
                                'Shared Progress',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 14),
                              for (final area in friend.areaProgress) ...[
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
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        GlassPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Recently Checked Off',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              for (final item in friend.recentItems)
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
                                          item,
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
                        ),
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

class _FriendProfile {
  final String name;
  final String initials;
  final int completed;
  final int total;
  final String focus;
  final String message;
  final List<String> recentItems;
  final List<_FriendAreaProgress> areaProgress;

  const _FriendProfile({
    required this.name,
    required this.initials,
    required this.completed,
    required this.total,
    required this.focus,
    required this.message,
    required this.recentItems,
    required this.areaProgress,
  });

  double get progress {
    if (total == 0) return 0;
    return completed / total;
  }
}

class _FriendAreaProgress {
  final String label;
  final int completed;
  final int total;

  const _FriendAreaProgress({
    required this.label,
    required this.completed,
    required this.total,
  });

  double get progress {
    if (total == 0) return 0;
    return completed / total;
  }
}
