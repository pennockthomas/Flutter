import 'dart:ui';
import 'package:flutter/material.dart';

import 'challenge_model.dart';
import 'challenge_repository.dart';

// ---------------- PLAYGROUND SCREEN (FIXED LAYOUT) ----------------

class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});
  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen>
    with SingleTickerProviderStateMixin {
  static const double nodeSize = 100;
  static const double horizontalSpacing = 170;
  static const double verticalSpacing = 145;
  static const double topPadding = 180;
  static const double sidePadding = 90;

  Offset offset = Offset.zero;
  late AnimationController controller;
  late Animation<Offset> animation;

  final ChallengeRepository _challengeRepository = ChallengeRepository();
  Map<String, Challenge> _challengeData = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadChallenges();
  }

  Future<void> _loadChallenges() async {
    try {
      final challengeData = await _challengeRepository.loadChallenges();
      if (!mounted) return;
      setState(() {
        _challengeData = challengeData;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void animateBack() {
    animation =
        Tween<Offset>(begin: offset, end: Offset.zero).animate(
          CurvedAnimation(parent: controller, curve: Curves.easeOut),
        )..addListener(() {
          setState(() {
            offset = animation.value;
          });
        });
    controller.forward(from: 0);
  }

  void openDetail(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          label: name,
          description: _challengeData[name]?.description ?? "",
        ),
      ),
    );
  }

  _PlaygroundLayout _buildPlaygroundLayout(Size screenSize) {
    final rows = <int, List<String>>{};
    final depths = <String, int>{};
    final edges = <_PlaygroundConnection>[];
    final queue = <String>["Start"];

    depths["Start"] = 0;

    for (var queueIndex = 0; queueIndex < queue.length; queueIndex++) {
      final label = queue[queueIndex];
      final depth = depths[label] ?? 0;
      rows.putIfAbsent(depth, () => []).add(label);

      for (final childLabel in _challengeData[label]?.unlocks ?? <String>[]) {
        edges.add(_PlaygroundConnection(label, childLabel));
        if (!depths.containsKey(childLabel)) {
          depths[childLabel] = depth + 1;
          queue.add(childLabel);
        }
      }
    }

    final maxRowSize = rows.values.fold<int>(
      1,
      (largest, row) => row.length > largest ? row.length : largest,
    );
    final maxDepth = rows.keys.isEmpty
        ? 0
        : rows.keys.reduce((a, b) => a > b ? a : b);
    final canvasWidth = (maxRowSize - 1) * horizontalSpacing + sidePadding * 2;
    final canvasHeight =
        topPadding + maxDepth * verticalSpacing + nodeSize + 80;
    final resolvedWidth = canvasWidth < screenSize.width
        ? screenSize.width
        : canvasWidth;
    final resolvedHeight = canvasHeight < screenSize.height
        ? screenSize.height
        : canvasHeight;

    final positions = <String, Offset>{};
    for (final entry in rows.entries) {
      final depth = entry.key;
      final labels = entry.value;
      final rowWidth = (labels.length - 1) * horizontalSpacing;
      final startX = (resolvedWidth - rowWidth) / 2;
      final y = topPadding + depth * verticalSpacing;

      for (var i = 0; i < labels.length; i++) {
        positions[labels[i]] = Offset(startX + i * horizontalSpacing, y);
      }
    }

    return _PlaygroundLayout(
      size: Size(resolvedWidth, resolvedHeight),
      positions: positions,
      edges: edges,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanUpdate: (details) {
          controller.stop();
          setState(() {
            offset += details.delta * 0.5;
            offset = Offset(offset.dx.clamp(-80, 80), offset.dy.clamp(-80, 80));
          });
        },
        onPanEnd: (_) => animateBack(),
        child: Stack(
          children: [
            Transform.translate(
              offset: offset * 0.2,
              child: Transform.scale(
                scale: 1.2,
                child: SizedBox.expand(
                  child: Image.asset(
                    'assets/background.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            Container(color: Colors.black.withOpacity(0.2)),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final layout = _buildPlaygroundLayout(
                    Size(constraints.maxWidth, constraints.maxHeight),
                  );

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: layout.size.width,
                      height: layout.size.height,
                      child: Transform.translate(
                        offset: offset,
                        child: CustomPaint(
                          painter: _LinePainter(layout.positions, layout.edges),
                          child: Stack(
                            children: [
                              ...layout.positions.entries.map((entry) {
                                return Positioned(
                                  left: entry.value.dx - nodeSize / 2,
                                  top: entry.value.dy - nodeSize / 2,
                                  child: GlassCircle(
                                    label: entry.key,
                                    onTap: () => openDetail(entry.key),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            Positioned(
              top: 50,
              left: 10,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- HELPERS ----------------

class _PlaygroundConnection {
  final String from;
  final String to;

  const _PlaygroundConnection(this.from, this.to);
}

class _PlaygroundLayout {
  final Size size;
  final Map<String, Offset> positions;
  final List<_PlaygroundConnection> edges;

  const _PlaygroundLayout({
    required this.size,
    required this.positions,
    required this.edges,
  });
}

class GlassCircle extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const GlassCircle({super.key, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: _PlaygroundScreenState.nodeSize,
            height: _PlaygroundScreenState.nodeSize,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final Map<String, Offset> positions;
  final List<_PlaygroundConnection> edges;

  const _LinePainter(this.positions, this.edges);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 2;

    for (final edge in edges) {
      final from = positions[edge.from];
      final to = positions[edge.to];
      if (from == null || to == null) continue;
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) {
    return oldDelegate.positions != positions || oldDelegate.edges != edges;
  }
}

class DetailScreen extends StatelessWidget {
  final String label;
  final String description;

  const DetailScreen({
    super.key,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: Image.asset('assets/background.jpg', fit: BoxFit.cover),
          ),
          Container(color: Colors.black.withOpacity(0.25)),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
