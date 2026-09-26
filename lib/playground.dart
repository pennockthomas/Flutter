import 'dart:ui';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'challenge_model.dart';
import 'challenge_store.dart';

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
  static const double minTreeZoom = 0.35;
  static const double maxTreeZoom = 2.5;

  Offset offset = Offset.zero;
  late AnimationController controller;
  late Animation<Offset> animation;
  final TransformationController _treeTransformController =
      TransformationController();

  Map<String, Challenge> _challengeData = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    ChallengeStore.instance.addListener(_onChallengesChanged);
    _loadChallenges();
  }

  void _onChallengesChanged() {
    if (!mounted) return;
    setState(() => _challengeData = ChallengeStore.instance.challenges);
  }

  Future<void> _loadChallenges() async {
    try {
      final challengeData = await ChallengeStore.instance.ensureLoaded();
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

  Future<void> _saveChallengeData() async {
    await ChallengeStore.instance.save(_challengeData);
  }

  String _uniqueChildLabel(String parentLabel) {
    var baseLabel = "$parentLabel Child";
    var candidate = baseLabel;
    var index = 2;
    while (_challengeData.containsKey(candidate)) {
      candidate = "$baseLabel $index";
      index++;
    }
    return candidate;
  }

  Future<bool> _renameChallenge({
    required String oldLabel,
    required String newLabel,
    required String description,
  }) async {
    final existing = _challengeData[oldLabel];
    if (existing == null) return false;

    final cleanedLabel = newLabel.trim();
    final cleanedDescription = description.trim();
    if (cleanedLabel.isEmpty) return false;
    if (cleanedLabel != oldLabel && _challengeData.containsKey(cleanedLabel)) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$cleanedLabel" already exists.')),
      );
      return false;
    }

    final updatedData = <String, Challenge>{};
    for (final entry in _challengeData.entries) {
      final challenge = entry.value;
      final updatedUnlocks = challenge.unlocks
          .map((label) => label == oldLabel ? cleanedLabel : label)
          .toList();

      if (entry.key == oldLabel) {
        updatedData[cleanedLabel] = existing.copyWith(
          label: cleanedLabel,
          description: cleanedDescription,
          unlocks: updatedUnlocks,
        );
      } else {
        updatedData[entry.key] = challenge.copyWith(unlocks: updatedUnlocks);
      }
    }

    setState(() => _challengeData = updatedData);
    await _saveChallengeData();
    return true;
  }

  Future<bool> _addChild({
    required String parentLabel,
    required String childLabel,
    required String childDescription,
  }) async {
    final parent = _challengeData[parentLabel];
    if (parent == null) return false;

    final cleanedLabel = childLabel.trim();
    if (cleanedLabel.isEmpty) return false;
    if (_challengeData.containsKey(cleanedLabel)) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$cleanedLabel" already exists.')),
      );
      return false;
    }

    final updatedParent = parent.copyWith(
      unlocks: [...parent.unlocks, cleanedLabel],
    );
    final child = Challenge(
      label: cleanedLabel,
      description: childDescription.trim(),
      unlocks: const [],
    );

    setState(() {
      _challengeData = {
        ..._challengeData,
        parentLabel: updatedParent,
        cleanedLabel: child,
      };
    });
    await _saveChallengeData();
    return true;
  }

  Future<void> _toggleChecklistItem({
    required String label,
    required int itemIndex,
    required bool isCompleted,
  }) async {
    final challenge = _challengeData[label];
    if (challenge == null) return;
    if (itemIndex < 0 || itemIndex >= challenge.checklist.length) return;

    final updatedChecklist = [...challenge.checklist];
    updatedChecklist[itemIndex] = updatedChecklist[itemIndex].copyWith(
      isCompleted: isCompleted,
    );
    final updatedChallenge = challenge.copyWith(checklist: updatedChecklist);

    setState(() {
      _challengeData = {..._challengeData, label: updatedChallenge};
    });
    if (!challenge.isFullyCompleted && updatedChallenge.isFullyCompleted) {
      await AppSettings.playSoundEffectIfEnabled(AppSounds.challengeFinished);
    } else {
      await AppSettings.playSystemSoundIfEnabled();
    }
    await _saveChallengeData();
  }

  Future<bool> _addChecklistItem({
    required String label,
    required String itemLabel,
  }) async {
    final challenge = _challengeData[label];
    if (challenge == null) return false;

    final cleanedLabel = itemLabel.trim();
    if (cleanedLabel.isEmpty) return false;

    final alreadyExists = challenge.checklist.any(
      (item) => item.label.toLowerCase() == cleanedLabel.toLowerCase(),
    );
    if (alreadyExists) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$cleanedLabel" is already in this checklist.'),
        ),
      );
      return false;
    }

    setState(() {
      _challengeData = {
        ..._challengeData,
        label: challenge.copyWith(
          checklist: [
            ...challenge.checklist,
            ChecklistItem(label: cleanedLabel),
          ],
        ),
      };
    });
    await _saveChallengeData();
    return true;
  }

  Future<void> _deleteChecklistItem({
    required String label,
    required int itemIndex,
  }) async {
    final challenge = _challengeData[label];
    if (challenge == null) return;
    if (itemIndex < 0 || itemIndex >= challenge.checklist.length) return;

    final updatedChecklist = [...challenge.checklist]..removeAt(itemIndex);

    setState(() {
      _challengeData = {
        ..._challengeData,
        label: challenge.copyWith(checklist: updatedChecklist),
      };
    });
    await _saveChallengeData();
  }

  Set<String> _collectDescendants(String label) {
    final collected = <String>{};

    void visit(String currentLabel) {
      if (!collected.add(currentLabel)) return;
      for (final childLabel in _challengeData[currentLabel]?.unlocks ?? []) {
        visit(childLabel);
      }
    }

    visit(label);
    return collected;
  }

  Future<bool> _deleteChallenge(String label) async {
    if (label == "Start") return false;
    if (!_challengeData.containsKey(label)) return false;

    final labelsToDelete = _collectDescendants(label);
    final updatedData = <String, Challenge>{};

    for (final entry in _challengeData.entries) {
      if (labelsToDelete.contains(entry.key)) continue;

      updatedData[entry.key] = entry.value.copyWith(
        unlocks: entry.value.unlocks
            .where((childLabel) => !labelsToDelete.contains(childLabel))
            .toList(),
      );
    }

    setState(() => _challengeData = updatedData);
    await _saveChallengeData();
    return true;
  }

  Future<void> _confirmDeleteChallenge(String label) async {
    if (label == "Start") return;
    final labelsToDelete = _collectDescendants(label);
    final childCount = labelsToDelete.length - 1;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF101510),
          title: Text(
            'Delete "$label"?',
            style: const TextStyle(color: Colors.white),
          ),
          content: Text(
            childCount == 0
                ? "This removes the bubble from the playground."
                : "This removes the bubble and $childCount child bubble(s).",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;
    final didDelete = await _deleteChallenge(label);
    if (didDelete && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _openAddChildSheet(String label) async {
    if (!_challengeData.containsKey(label)) return;

    final childNameController = TextEditingController(
      text: _uniqueChildLabel(label),
    );
    final childDescriptionController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black.withOpacity(0.85),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _EditorSheetFrame(
          title: "Add child to $label",
          children: [
            TextField(
              controller: childNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Child name",
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.greenAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: childDescriptionController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Child description",
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.greenAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final didAdd = await _addChild(
                  parentLabel: label,
                  childLabel: childNameController.text,
                  childDescription: childDescriptionController.text,
                );
                if (didAdd && context.mounted) Navigator.pop(context);
              },
              child: const Text("Add Child"),
            ),
          ],
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      childNameController.dispose();
      childDescriptionController.dispose();
    });
  }

  Future<void> _openNodeEditor(String label) async {
    final challenge = _challengeData[label];
    if (challenge == null) return;

    final nameController = TextEditingController(text: challenge.label);
    final descriptionController = TextEditingController(
      text: challenge.description,
    );
    final checklistItemController = TextEditingController();
    final canRename = label != "Start";

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black.withOpacity(0.85),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _EditorSheetFrame(
          title: label,
          children: [
            TextField(
              controller: nameController,
              enabled: canRename,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: canRename ? "Bubble name" : "Root bubble name",
                labelStyle: const TextStyle(color: Colors.white70),
                helperText: canRename ? null : "Start stays fixed as root.",
                helperStyle: const TextStyle(color: Colors.white54),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                disabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.greenAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Description",
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.greenAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final didSave = await _renameChallenge(
                  oldLabel: label,
                  newLabel: canRename ? nameController.text : label,
                  description: descriptionController.text,
                );
                if (didSave && context.mounted) Navigator.pop(context);
              },
              child: const Text("Save Bubble"),
            ),
            const Divider(color: Colors.white24, height: 32),
            StatefulBuilder(
              builder: (context, setSheetState) {
                final currentChallenge = _challengeData[label];
                final checklist = currentChallenge?.checklist ?? const [];
                final completedCount = checklist
                    .where((item) => item.isCompleted)
                    .length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Checklist $completedCount/${checklist.length}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (checklist.isEmpty)
                      const Text(
                        "No product swaps yet.",
                        style: TextStyle(color: Colors.white54),
                      )
                    else
                      ...checklist.asMap().entries.map((entry) {
                        return Row(
                          children: [
                            Expanded(
                              child: CheckboxListTile(
                                value: entry.value.isCompleted,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                activeColor: Colors.greenAccent,
                                checkColor: Colors.black,
                                title: Text(
                                  entry.value.label,
                                  style: TextStyle(
                                    color: entry.value.isCompleted
                                        ? Colors.white54
                                        : Colors.white,
                                    decoration: entry.value.isCompleted
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                  ),
                                ),
                                onChanged: (value) async {
                                  await _toggleChecklistItem(
                                    label: label,
                                    itemIndex: entry.key,
                                    isCompleted: value ?? false,
                                  );
                                  setSheetState(() {});
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: "Remove product swap",
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                                size: 22,
                              ),
                              onPressed: () async {
                                await _deleteChecklistItem(
                                  label: label,
                                  itemIndex: entry.key,
                                );
                                setSheetState(() {});
                              },
                            ),
                          ],
                        );
                      }),
                    const SizedBox(height: 8),
                    TextField(
                      controller: checklistItemController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: "Add product swap",
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.greenAccent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final didAdd = await _addChecklistItem(
                          label: label,
                          itemLabel: checklistItemController.text,
                        );
                        if (!didAdd) return;
                        checklistItemController.clear();
                        setSheetState(() {});
                      },
                      child: const Text("Add Checklist Item"),
                    ),
                  ],
                );
              },
            ),
            if (canRename) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                ),
                onPressed: () => _confirmDeleteChallenge(label),
                child: const Text("Delete Bubble"),
              ),
            ],
          ],
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      descriptionController.dispose();
      checklistItemController.dispose();
    });
  }

  void openDetail(String name) {
    _openNodeEditor(name);
  }

  void _zoomTree(double zoomDelta) {
    final currentScale = _treeTransformController.value.getMaxScaleOnAxis();
    final nextScale = (currentScale + zoomDelta).clamp(
      minTreeZoom,
      maxTreeZoom,
    );
    final scaleChange = nextScale / currentScale;
    final nextMatrix = Matrix4.copy(_treeTransformController.value)
      ..scale(scaleChange);

    setState(() {
      _treeTransformController.value = nextMatrix;
    });
  }

  _PlaygroundLayout _buildPlaygroundLayout(Size screenSize) {
    final edges = <_PlaygroundConnection>[];
    final positions = <String, Offset>{};
    final visited = <String>{};
    var nextLeafX = sidePadding;
    var maxDepth = 0;

    double placeSubtree(String label, int depth) {
      final challenge = _challengeData[label];
      if (challenge == null) return nextLeafX;
      if (!visited.add(label)) {
        return positions[label]?.dx ?? nextLeafX;
      }

      maxDepth = depth > maxDepth ? depth : maxDepth;
      final childLabels = challenge.unlocks
          .where((childLabel) => _challengeData.containsKey(childLabel))
          .toList();

      for (final childLabel in childLabels) {
        edges.add(_PlaygroundConnection(label, childLabel));
      }

      final x = childLabels.isEmpty
          ? nextLeafX
          : childLabels
                    .map((childLabel) => placeSubtree(childLabel, depth + 1))
                    .reduce((a, b) => a + b) /
                childLabels.length;

      if (childLabels.isEmpty) {
        nextLeafX += horizontalSpacing;
      }

      positions[label] = Offset(x, topPadding + depth * verticalSpacing);
      return x;
    }

    placeSubtree("Start", 0);

    for (final label in _challengeData.keys) {
      if (!visited.contains(label)) {
        nextLeafX += horizontalSpacing;
        placeSubtree(label, 0);
      }
    }

    final contentWidth = positions.values.isEmpty
        ? screenSize.width
        : positions.values
                  .map((position) => position.dx)
                  .reduce((a, b) => a > b ? a : b) +
              sidePadding;
    final resolvedWidth = contentWidth < screenSize.width
        ? screenSize.width
        : contentWidth;
    if (contentWidth < screenSize.width) {
      final shift = (screenSize.width - contentWidth) / 2;
      positions.updateAll(
        (label, position) => Offset(position.dx + shift, position.dy),
      );
    }

    final canvasHeight =
        topPadding + maxDepth * verticalSpacing + nodeSize + 80;
    final resolvedHeight = canvasHeight < screenSize.height
        ? screenSize.height
        : canvasHeight;

    return _PlaygroundLayout(
      size: Size(resolvedWidth, resolvedHeight),
      positions: positions,
      edges: edges,
    );
  }

  @override
  void dispose() {
    ChallengeStore.instance.removeListener(_onChallengesChanged);
    controller.dispose();
    _treeTransformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Transform.translate(
            offset: offset * 0.2,
            child: Transform.scale(
              scale: 1.2,
              child: SizedBox.expand(
                child: Image.asset('assets/background.jpg', fit: BoxFit.cover),
              ),
            ),
          ),
          const AppBackgroundOverlay(fallbackDarkness: 0.2),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final layout = _buildPlaygroundLayout(
                  Size(constraints.maxWidth, constraints.maxHeight),
                );

                return InteractiveViewer(
                  transformationController: _treeTransformController,
                  constrained: false,
                  minScale: minTreeZoom,
                  maxScale: maxTreeZoom,
                  boundaryMargin: const EdgeInsets.all(400),
                  child: SizedBox(
                    width: layout.size.width,
                    height: layout.size.height,
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
                                onLongPress: () =>
                                    _openAddChildSheet(entry.key),
                              ),
                            );
                          }),
                        ],
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
          Positioned(
            right: 18,
            bottom: 28,
            child: Column(
              children: [
                _ZoomButton(icon: Icons.add, onPressed: () => _zoomTree(0.2)),
                const SizedBox(height: 10),
                _ZoomButton(
                  icon: Icons.remove,
                  onPressed: () => _zoomTree(-0.2),
                ),
                const SizedBox(height: 10),
                _ZoomButton(
                  icon: Icons.center_focus_strong,
                  onPressed: () {
                    setState(() {
                      _treeTransformController.value = Matrix4.identity();
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _ZoomButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withOpacity(0.12),
          shape: CircleBorder(
            side: BorderSide(color: Colors.white.withOpacity(0.24)),
          ),
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
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

class _EditorSheetFrame extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _EditorSheetFrame({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: bottomInset + 12,
        ),
        child: SizedBox(
          height: screenHeight * 0.82,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GlassCircle extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const GlassCircle({
    super.key,
    required this.label,
    this.onTap,
    this.onLongPress,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
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
          const AppBackgroundOverlay(fallbackDarkness: 0.25),
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
