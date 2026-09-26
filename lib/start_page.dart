import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'app_user.dart';
import 'challenge_model.dart';
import 'challenge_store.dart';

enum NodeStatus { available, completed }

class Node {
  Offset position;
  Offset velocity = Offset.zero;
  final String label;
  String? rootCategory;
  bool isExpanded = false;
  bool showContent = false;
  final bool isFixed;
  NodeStatus status;
  bool hasSpawnedChildren = false;

  Node({
    required this.position,
    required this.label,
    this.rootCategory,
    this.isFixed = false,
    this.status = NodeStatus.available,
  });
}

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});
  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen>
    with TickerProviderStateMixin {
  late Ticker _physicsTicker;
  final TransformationController _transformController =
      TransformationController();

  late AnimationController _cameraController;
  Animation<Matrix4>? _cameraAnimation;

  List<Node> nodes = [];
  List<List<int>> connections = [];
  Map<String, Challenge> challengeData = {};
  bool isLoading = true;
  bool _showProgressMenu = false;

  Map<String, int> categories = {};

  final double maxZoom = 4.0;
  final double minZoom = 0.2;
  final double canvasSize = 4000.0;
  final double maxLinkDistance = 200.0;
  final double targetLinkDistance = 120.0;

  double _backgroundScale = 1.2;
  final double collapsedSize = 100.0;
  final double expandedSize = 220.0;
  final math.Random _random = math.Random();

  bool _isChallengeChecklistComplete(String label) {
    return challengeData[label]?.isFullyCompleted ?? false;
  }

  Future<void> _saveChallengeData() async {
    await ChallengeStore.instance.save(challengeData);
  }

  void _syncNodeCompletionFromChecklist(String label) {
    final idx = nodes.indexWhere((node) => node.label == label);
    if (idx == -1) return;
    nodes[idx].status =
        nodes[idx].hasSpawnedChildren || _isChallengeChecklistComplete(label)
        ? NodeStatus.completed
        : NodeStatus.available;
  }

  @override
  void initState() {
    super.initState();
    ChallengeStore.instance.addListener(_onChallengesChanged);
    _loadInitialData();

    _transformController.value = Matrix4.identity()
      ..translate(-(canvasSize / 2) + 200, -(canvasSize / 2) + 400);

    _physicsTicker = createTicker(_updatePhysics)..start();

    _cameraController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 700),
        )..addListener(() {
          if (_cameraAnimation != null) {
            _transformController.value = _cameraAnimation!.value;
          }
        });

    _transformController.addListener(() {
      double scale = _transformController.value.getMaxScaleOnAxis();
      setState(() {
        _backgroundScale = 1.2 + (scale - 1.0) * 0.15;
      });
    });
  }

  void _onChallengesChanged() {
    if (!mounted || isLoading) return;
    setState(() {
      challengeData = ChallengeStore.instance.challenges;
      for (final label in challengeData.keys) {
        _syncNodeCompletionFromChecklist(label);
      }
    });
  }

  Future<void> _loadInitialData() async {
    try {
      final tempMap = await ChallengeStore.instance.ensureLoaded();

      final prefs = await SharedPreferences.getInstance();
      List<String> mainTiers = tempMap["Start"]?.unlocks ?? [];
      Map<String, int> dynamicCategories = {};
      for (var tier in mainTiers) {
        dynamicCategories[tier] = prefs.getInt('progress_$tier') ?? 0;
      }

      setState(() {
        challengeData = tempMap;
        categories = dynamicCategories;
        isLoading = false;
        nodes = [
          Node(
            position: Offset(canvasSize / 2, canvasSize / 2),
            label: "Start",
            isFixed: true,
          ),
        ];
      });

      List<String> savedUnlocked = prefs.getStringList('unlocked_nodes') ?? [];
      for (String label in savedUnlocked) {
        int idx = nodes.indexWhere((n) => n.label == label);
        if (idx != -1) _spawnNextTier(idx, isRestoring: true);
      }
      for (final label in challengeData.keys) {
        _syncNodeCompletionFromChecklist(label);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _confirmResetProgress() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF101510),
          title: const Text(
            'Reset progress?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'This clears every unlocked bubble and checklist item. '
            'This cannot be undone.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (shouldReset == true) {
      await _resetProgress();
    }
  }

  Future<void> _resetProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final progressKeys = prefs
        .getKeys()
        .where((key) => key.startsWith('progress_') || key == 'unlocked_nodes')
        .toList();
    for (final key in progressKeys) {
      await prefs.remove(key);
    }

    final resetChallenges = {
      for (final entry in challengeData.entries)
        entry.key: entry.value.copyWith(
          checklist: entry.value.checklist
              .map((item) => item.copyWith(isCompleted: false))
              .toList(),
        ),
    };
    await ChallengeStore.instance.save(resetChallenges);

    if (!mounted) return;
    setState(() => isLoading = true);
    await _loadInitialData();
  }

  Future<void> _updateCategoryProgress(String category) async {
    if (!categories.containsKey(category)) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      int currentVal = categories[category] ?? 0;
      categories[category] = (currentVal + 1).clamp(0, 10);
    });
    await prefs.setInt('progress_$category', categories[category]!);
  }

  void _centerOnNode(
    Node node, {
    bool animateZoom = true,
    bool isClosing = false,
  }) {
    final size = MediaQuery.of(context).size;
    double multiplier = isClosing ? 1.6 : 1.2;
    double targetScale = (size.width / (expandedSize * multiplier)).clamp(
      minZoom,
      maxZoom,
    );

    final double targetX = (size.width / 2) - (node.position.dx * targetScale);
    final double targetY = (size.height / 2) - (node.position.dy * targetScale);

    final Matrix4 endMatrix = Matrix4.identity()
      ..translate(targetX, targetY)
      ..scale(targetScale);

    if (animateZoom && !AppSettings.reducedMotion.value) {
      _cameraAnimation =
          Matrix4Tween(
            begin: _transformController.value,
            end: endMatrix,
          ).animate(
            CurvedAnimation(
              parent: _cameraController,
              curve: Curves.easeInOutCubic,
            ),
          );
      _cameraController.forward(from: 0);
    } else {
      _transformController.value = endMatrix;
    }
  }

  void _spawnNextTier(int parentIdx, {bool isRestoring = false}) async {
    if (nodes[parentIdx].hasSpawnedChildren) return;
    final parentNode = nodes[parentIdx];
    String currentLabel = parentNode.label;

    if (!isRestoring) {
      final prefs = await SharedPreferences.getInstance();
      List<String> history = prefs.getStringList('unlocked_nodes') ?? [];
      if (!history.contains(currentLabel)) {
        history.add(currentLabel);
        await prefs.setStringList('unlocked_nodes', history);
      }
      if (parentNode.rootCategory != null)
        _updateCategoryProgress(parentNode.rootCategory!);
      await AppSettings.playSoundEffectIfEnabled(AppSounds.tierUnlocked);
    }

    setState(() {
      parentNode.status = NodeStatus.completed;
      parentNode.hasSpawnedChildren = true;
      parentNode.showContent = false;
      parentNode.isExpanded = false;

      if (!isRestoring) _centerOnNode(parentNode, isClosing: true);

      List<String> toUnlock = challengeData[currentLabel]?.unlocks ?? [];
      for (var title in toUnlock) {
        if (!nodes.any((n) => n.label == title)) {
          String? childCategory = (parentNode.label == "Start")
              ? title
              : parentNode.rootCategory;
          nodes.add(
            Node(
              position:
                  parentNode.position +
                  Offset(_random.nextDouble() * 40, _random.nextDouble() * 40),
              label: title,
              rootCategory: childCategory,
              status: _isChallengeChecklistComplete(title)
                  ? NodeStatus.completed
                  : NodeStatus.available,
            ),
          );
          connections.add([parentIdx, nodes.length - 1]);
        }
      }
    });
  }

  Future<void> _toggleChecklistItem({
    required String label,
    required int itemIndex,
    required bool isCompleted,
  }) async {
    final challenge = challengeData[label];
    if (challenge == null) return;
    if (itemIndex < 0 || itemIndex >= challenge.checklist.length) return;

    final updatedChecklist = [...challenge.checklist];
    updatedChecklist[itemIndex] = updatedChecklist[itemIndex].copyWith(
      isCompleted: isCompleted,
    );
    final updatedChallenge = challenge.copyWith(checklist: updatedChecklist);

    setState(() {
      challengeData = {...challengeData, label: updatedChallenge};
      _syncNodeCompletionFromChecklist(label);
    });
    if (!challenge.isFullyCompleted && updatedChallenge.isFullyCompleted) {
      await AppSettings.playSoundEffectIfEnabled(AppSounds.challengeFinished);
    } else {
      await AppSettings.playSystemSoundIfEnabled();
    }
    await _saveChallengeData();
  }

  Future<void> _openChecklistScreen(String label) async {
    final challenge = challengeData[label];
    if (challenge == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return ChecklistScreen(
            challenge: challenge,
            onToggleItem: (itemIndex, isCompleted) async {
              await _toggleChecklistItem(
                label: label,
                itemIndex: itemIndex,
                isCompleted: isCompleted,
              );
            },
          );
        },
      ),
    );
  }

  void _updatePhysics(Duration elapsed) {
    if (isLoading || nodes.isEmpty) return;
    setState(() {
      for (int i = 0; i < nodes.length; i++) {
        for (int j = 0; j < nodes.length; j++) {
          if (i == j) continue;
          Offset diff = nodes[i].position - nodes[j].position;
          double dist = diff.distance.clamp(1.0, 1000.0);
          nodes[i].velocity += (diff / dist) * (600.0 / dist);
        }
      }

      for (var conn in connections) {
        Node n1 = nodes[conn[0]], n2 = nodes[conn[1]];
        Offset diff = n1.position - n2.position;
        double dist = diff.distance;
        Offset force = (diff / dist) * ((dist - targetLinkDistance) * 0.09);
        if (!n1.isFixed) n1.velocity -= force;
        if (!n2.isFixed) n2.velocity += force;

        if (dist > maxLinkDistance) {
          Offset overExtend = diff - ((diff / dist) * maxLinkDistance);
          if (n1.isFixed)
            n2.position += overExtend;
          else {
            n1.position -= overExtend * 0.5;
            n2.position += overExtend * 0.5;
          }
        }
      }

      Node? expandedNode;
      for (var node in nodes) {
        if (!node.isFixed) node.position += node.velocity;
        node.velocity *= 0.45;
        if (node.isExpanded) expandedNode = node;
      }

      if (expandedNode != null && !_cameraController.isAnimating) {
        final size = MediaQuery.of(context).size;
        double currentScale = _transformController.value.getMaxScaleOnAxis();
        final double targetX =
            (size.width / 2) - (expandedNode.position.dx * currentScale);
        final double targetY =
            (size.height / 2) - (expandedNode.position.dy * currentScale);
        _transformController.value = Matrix4.identity()
          ..translate(targetX, targetY)
          ..scale(currentScale);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading)
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Transform.scale(
              scale: _backgroundScale,
              child: Image.asset(
                'assets/background.jpg',
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) =>
                    Container(color: Colors.blueGrey[900]),
              ),
            ),
          ),

          const AppBackgroundOverlay(fallbackDarkness: 0.2),

          InteractiveViewer(
            transformationController: _transformController,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: minZoom,
            maxScale: maxZoom,
            child: SizedBox(
              width: canvasSize,
              height: canvasSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    painter: GraphPainter(nodes, connections),
                    size: Size.infinite,
                  ),
                  ...nodes
                      .asMap()
                      .entries
                      .map((entry) => _buildPhysicsNode(entry.key, entry.value))
                      .toList(),
                ],
              ),
            ),
          ),

          // ✅ Top Left: Go Back Button (Settings Style)
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

          // ✅ Top Right: Reset Button
          Positioned(
            top: 50,
            right: 20,
            child: Opacity(
              opacity: 0.5,
              child: IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 28),
                onPressed: _confirmResetProgress,
              ),
            ),
          ),

          _buildProgressMenu(),
        ],
      ),
    );
  }

  Widget _buildProgressMenu() {
    int totalLevel = categories.values.fold(0, (sum, val) => sum + val);
    return Positioned(
      bottom: 20,
      right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: _showProgressMenu
                ? Container(
                    width: 240,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                AppUser.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const Divider(color: Colors.white24, height: 20),
                              ...categories.entries
                                  .map(
                                    (e) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                e.key,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              Text(
                                                "${e.value}/10",
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(
                                            value: e.value / 10,
                                            backgroundColor: Colors.white12,
                                            color: Colors.greenAccent
                                                .withOpacity(0.6),
                                            minHeight: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              const Divider(color: Colors.white24, height: 20),
                              Text(
                                "Overall Level: $totalLevel",
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          GestureDetector(
            onTap: () => setState(() => _showProgressMenu = !_showProgressMenu),
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 300),
                turns: _showProgressMenu ? 0.5 : 0,
                child: const Icon(
                  Icons.keyboard_arrow_up,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhysicsNode(int idx, Node node) {
    final isStartNode = node.label == "Start";
    final nodeCollapsedSize = isStartNode ? collapsedSize + 22 : collapsedSize;
    double targetSize = node.isExpanded ? expandedSize : nodeCollapsedSize;
    final challenge = challengeData[node.label];
    final checklist = challenge?.checklist ?? const [];
    final completedItems = checklist.where((item) => item.isCompleted).length;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: nodeCollapsedSize, end: targetSize),
      onEnd: () {
        if (node.isExpanded) setState(() => node.showContent = true);
      },
      builder: (context, animSize, child) {
        return Positioned(
          left: node.position.dx - (animSize / 2),
          top: node.position.dy - (animSize / 2),
          child: GestureDetector(
            onPanUpdate: (d) => setState(() {
              node.position += d.delta;
              node.velocity = Offset.zero;
            }),
            onTap: () {
              setState(() {
                if (node.isExpanded) {
                  node.showContent = false;
                  node.isExpanded = false;
                  _centerOnNode(node, isClosing: true);
                } else {
                  for (var n in nodes) {
                    n.isExpanded = false;
                    n.showContent = false;
                  }
                  node.isExpanded = true;
                  _centerOnNode(node, isClosing: false);
                }
              });
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                node.isExpanded ? 30 : animSize / 2,
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  width: animSize,
                  height: animSize,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: isStartNode && !node.isExpanded
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.greenAccent.withOpacity(0.26),
                              Colors.green.withOpacity(0.22),
                              Colors.amberAccent.withOpacity(0.12),
                            ],
                          )
                        : null,
                    color: isStartNode && !node.isExpanded
                        ? null
                        : node.status == NodeStatus.completed
                        ? Colors.green.withOpacity(0.15)
                        : Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(
                      node.isExpanded ? 30 : animSize / 2,
                    ),
                    border: Border.all(
                      color: isStartNode && !node.isExpanded
                          ? Colors.greenAccent.withOpacity(0.72)
                          : node.status == NodeStatus.completed
                          ? Colors.green.withOpacity(0.4)
                          : Colors.white.withOpacity(0.25),
                      width: isStartNode && !node.isExpanded ? 2.2 : 1.0,
                    ),
                    boxShadow: isStartNode && !node.isExpanded
                        ? [
                            BoxShadow(
                              color: Colors.greenAccent.withOpacity(0.24),
                              blurRadius: 28,
                              spreadRadius: 4,
                            ),
                            BoxShadow(
                              color: Colors.amberAccent.withOpacity(0.12),
                              blurRadius: 44,
                              spreadRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: node.showContent
                          ? SingleChildScrollView(
                              key: const ValueKey("expanded"),
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    node.label,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    challenge?.description ?? "...",
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                  if (checklist.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      "Checklist $completedItems/${checklist.length}",
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      height: 34,
                                      width: 160,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white24,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.zero,
                                          textStyle: const TextStyle(
                                            fontSize: 11,
                                          ),
                                        ),
                                        onPressed: () =>
                                            _openChecklistScreen(node.label),
                                        child: const Text("Open Checklist"),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  if (!node.hasSpawnedChildren)
                                    SizedBox(
                                      height: 34,
                                      width: 160,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white24,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.zero,
                                          textStyle: const TextStyle(
                                            fontSize: 11,
                                          ),
                                        ),
                                        onPressed: () => _spawnNextTier(idx),
                                        child: const Text("Unlock Tier"),
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 30,
                                    ),
                                ],
                              ),
                            )
                          : Container(
                              alignment: Alignment.center,
                              key: const ValueKey("collapsed"),
                              width: double.infinity,
                              height: double.infinity,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: isStartNode
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(
                                              Icons.eco_rounded,
                                              color: Colors.greenAccent,
                                              size: 28,
                                            ),
                                            SizedBox(height: 6),
                                            Text(
                                              "Start",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 17,
                                                fontWeight: FontWeight.bold,
                                                height: 1.1,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          node.label,
                                          textAlign: TextAlign.center,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                            height: 1.2,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    ChallengeStore.instance.removeListener(_onChallengesChanged);
    _physicsTicker.dispose();
    _cameraController.dispose();
    _transformController.dispose();
    super.dispose();
  }
}

class ChecklistScreen extends StatefulWidget {
  final Challenge challenge;
  final Future<void> Function(int itemIndex, bool isCompleted) onToggleItem;

  const ChecklistScreen({
    super.key,
    required this.challenge,
    required this.onToggleItem,
  });

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  late List<ChecklistItem> checklist;

  @override
  void initState() {
    super.initState();
    checklist = [...widget.challenge.checklist];
  }

  int get completedCount {
    return checklist.where((item) => item.isCompleted).length;
  }

  double get progress {
    if (checklist.isEmpty) return 0;
    return completedCount / checklist.length;
  }

  Future<void> _toggleItem(int index, bool value) async {
    setState(() {
      checklist[index] = checklist[index].copyWith(isCompleted: value);
    });
    await widget.onToggleItem(index, value);
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.challenge.label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.challenge.description,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    "$completedCount/${checklist.length}",
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: Colors.white12,
                                  color: Colors.greenAccent,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: checklist.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = checklist[index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: CheckboxListTile(
                            value: item.isCompleted,
                            onChanged: (value) =>
                                _toggleItem(index, value ?? false),
                            activeColor: Colors.greenAccent,
                            checkColor: Colors.black,
                            tileColor: Colors.white.withOpacity(0.1),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: item.isCompleted
                                    ? Colors.greenAccent.withOpacity(0.5)
                                    : Colors.white24,
                              ),
                            ),
                            title: Text(
                              item.label,
                              style: TextStyle(
                                color: item.isCompleted
                                    ? Colors.white54
                                    : Colors.white,
                                fontSize: 16,
                                decoration: item.isCompleted
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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

class GraphPainter extends CustomPainter {
  final List<Node> nodes;
  final List<List<int>> connections;
  GraphPainter(this.nodes, this.connections);
  @override
  void paint(Canvas canvas, Size size) {
    final inactivePaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 6;
    final completedPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.55)
      ..strokeWidth = 6;

    for (var c in connections) {
      final fromNode = nodes[c[0]];
      final toNode = nodes[c[1]];
      final isCompletedConnection =
          fromNode.status == NodeStatus.completed &&
          toNode.status == NodeStatus.completed;

      canvas.drawLine(
        fromNode.position,
        toNode.position,
        isCompletedConnection ? completedPaint : inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
