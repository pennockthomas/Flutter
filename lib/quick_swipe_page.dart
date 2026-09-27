import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'challenge_store.dart';
import 'glass_panel.dart';

class QuickSwipePage extends StatefulWidget {
  const QuickSwipePage({super.key});

  @override
  State<QuickSwipePage> createState() => _QuickSwipePageState();
}

class _QuickSwipePageState extends State<QuickSwipePage> {
  static const double _decisionThreshold = 90;

  List<_QuickSwipeItem> _items = [];
  int _currentIndex = 0;
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  bool _isSaving = false;
  bool _isLoading = true;
  String? _loadError;

  _QuickSwipeItem? get _currentItem =>
      _currentIndex < _items.length ? _items[_currentIndex] : null;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final challenges = await ChallengeStore.instance.ensureLoaded();
      final items = <_QuickSwipeItem>[];
      for (final entry in challenges.entries) {
        for (var index = 0; index < entry.value.checklist.length; index++) {
          final checklistItem = entry.value.checklist[index];
          items.add(
            _QuickSwipeItem(
              challengeId: entry.key,
              category: entry.value.label,
              itemIndex: index,
              label: checklistItem.label,
              isCompleted: checklistItem.isCompleted,
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _currentIndex = 0;
        _dragOffset = Offset.zero;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load your swaps.';
      });
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_isSaving) return;
    setState(() {
      _isDragging = true;
      _dragOffset += details.delta;
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_isSaving) return;
    _isDragging = false;
    if (_dragOffset.dx.abs() >= _decisionThreshold) {
      _saveDecision(_dragOffset.dx > 0);
    } else {
      setState(() => _dragOffset = Offset.zero);
    }
  }

  Future<void> _saveDecision(bool isCompleted) async {
    final item = _currentItem;
    if (item == null || _isSaving) return;

    final challenges = ChallengeStore.instance.challenges;
    final challenge = challenges[item.challengeId];
    if (challenge == null || item.itemIndex >= challenge.checklist.length) {
      return;
    }

    final updatedChecklist = [...challenge.checklist];
    updatedChecklist[item.itemIndex] = updatedChecklist[item.itemIndex]
        .copyWith(isCompleted: isCompleted);
    final updatedChallenges = {
      ...challenges,
      item.challengeId: challenge.copyWith(checklist: updatedChecklist),
    };
    final screenWidth = MediaQuery.sizeOf(context).width;

    setState(() {
      _isSaving = true;
      _isDragging = false;
      _dragOffset = Offset(
        isCompleted ? screenWidth * 1.25 : -screenWidth * 1.25,
        _dragOffset.dy,
      );
    });

    try {
      await Future.wait([
        ChallengeStore.instance.save(updatedChallenges),
        Future<void>.delayed(const Duration(milliseconds: 220)),
      ]);
      await AppSettings.playSystemSoundIfEnabled();
      if (!mounted) return;
      setState(() {
        _items[_currentIndex] = item.copyWith(isCompleted: isCompleted);
        _currentIndex++;
        _dragOffset = Offset.zero;
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dragOffset = Offset.zero;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that choice. Try again.')),
      );
    }
  }

  void _restartReview() {
    setState(() {
      _currentIndex = 0;
      _dragOffset = Offset.zero;
    });
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
          const AppBackgroundOverlay(fallbackDarkness: 0.42),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final reviewed = math.min(_currentIndex, _items.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 18, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QuickSwipe',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Review your swaps in seconds',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          if (!_isLoading && _items.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '$reviewed/${_items.length}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.greenAccent),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: GlassPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _loadError!,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loadItems,
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: GlassPanel(
            child: Text(
              'Add checklist swaps in Playground to use QuickSwipe.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ),
      );
    }
    if (_currentItem == null) return _buildFinishedState();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _DirectionHint(
                icon: Icons.close_rounded,
                label: 'Still to do',
                color: Colors.orangeAccent,
              ),
              _DirectionHint(
                icon: Icons.check_rounded,
                label: 'Already done',
                color: Colors.greenAccent,
              ),
            ],
          ),
        ),
        Expanded(child: _buildCardDeck()),
        _buildDecisionButtons(),
      ],
    );
  }

  Widget _buildCardDeck() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = math.min(constraints.maxWidth - 54, 370.0);
        final cardHeight = math.min(constraints.maxHeight - 38, 470.0);
        final item = _currentItem!;
        final strength = (_dragOffset.dx / _decisionThreshold).clamp(-1.0, 1.0);

        return Center(
          child: SizedBox(
            width: cardWidth,
            height: cardHeight,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                for (var depth = 3; depth >= 1; depth--)
                  if (_currentIndex + depth < _items.length)
                    _StackedPreviewCard(
                      depth: depth,
                      width: cardWidth,
                      height: cardHeight,
                      item: _items[_currentIndex + depth],
                    ),
                TweenAnimationBuilder<Offset>(
                  key: ValueKey('${item.challengeId}:${item.itemIndex}'),
                  tween: Tween<Offset>(end: _dragOffset),
                  duration: _isDragging
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, offset, child) {
                    return Transform.translate(
                      offset: offset,
                      child: Transform.rotate(
                        angle: (offset.dx / cardWidth) * 0.12,
                        child: child,
                      ),
                    );
                  },
                  child: GestureDetector(
                    onPanUpdate: _handlePanUpdate,
                    onPanEnd: _handlePanEnd,
                    child: _SwapCard(
                      width: cardWidth,
                      height: cardHeight,
                      item: item,
                      decisionStrength: strength,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDecisionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(38, 10, 38, 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _DecisionButton(
            icon: Icons.close_rounded,
            label: 'Still to do',
            color: Colors.orangeAccent,
            onPressed: _isSaving ? null : () => _saveDecision(false),
          ),
          _DecisionButton(
            icon: Icons.check_rounded,
            label: 'Done',
            color: Colors.greenAccent,
            onPressed: _isSaving ? null : () => _saveDecision(true),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: GlassPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.eco_rounded,
                color: Colors.greenAccent,
                size: 64,
              ),
              const SizedBox(height: 18),
              const Text(
                'All swaps reviewed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${ChallengeStore.instance.completedItems} of ${ChallengeStore.instance.totalItems} swaps are marked done.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _restartReview,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Review Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Product illustrations keyed by their checklist label. Only a handful of
/// items have real artwork so far (see `tool/generate_product_icons.py`);
/// everything else falls back to the generic eco icon in [_SwapCard].
const Map<String, String> _productIllustrations = {
  'Stainless steel lunch box': 'assets/products/metal_lunchbox.png',
};

class _SwapCard extends StatelessWidget {
  final double width;
  final double height;
  final _QuickSwipeItem item;
  final double decisionStrength;

  const _SwapCard({
    required this.width,
    required this.height,
    required this.item,
    this.decisionStrength = 0,
  });

  @override
  Widget build(BuildContext context) {
    final rightOpacity = decisionStrength.clamp(0.0, 1.0);
    final leftOpacity = (-decisionStrength).clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: height,
      child: _SwipeGlassCard(
        padding: const EdgeInsets.all(26),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.greenAccent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      item.category,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                _ProductGlyph(assetPath: _productIllustrations[item.label]),
                const SizedBox(height: 24),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    height: 1.15,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.isCompleted
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: item.isCompleted
                          ? Colors.greenAccent
                          : Colors.white54,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.isCompleted
                          ? 'Currently marked done'
                          : 'Currently still to do',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 56,
              right: 0,
              child: Opacity(
                opacity: rightOpacity,
                child: const _DecisionStamp(
                  label: 'DONE',
                  icon: Icons.check_rounded,
                  color: Colors.greenAccent,
                ),
              ),
            ),
            Positioned(
              top: 56,
              left: 0,
              child: Opacity(
                opacity: leftOpacity,
                child: const _DecisionStamp(
                  label: 'TO DO',
                  icon: Icons.close_rounded,
                  color: Colors.orangeAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the product illustration for an item when one exists, otherwise
/// falls back to the generic eco glyph used for everything else.
class _ProductGlyph extends StatelessWidget {
  final String? assetPath;

  const _ProductGlyph({this.assetPath});

  @override
  Widget build(BuildContext context) {
    if (assetPath == null) {
      return const Icon(
        Icons.eco_rounded,
        color: Colors.greenAccent,
        size: 72,
      );
    }
    return Image.asset(
      assetPath!,
      width: 84,
      height: 84,
      errorBuilder: (context, error, stackTrace) => const Icon(
        Icons.eco_rounded,
        color: Colors.greenAccent,
        size: 72,
      ),
    );
  }
}

class _StackedPreviewCard extends StatelessWidget {
  final int depth;
  final double width;
  final double height;
  final _QuickSwipeItem item;

  const _StackedPreviewCard({
    required this.depth,
    required this.width,
    required this.height,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final angle = switch (depth) {
      1 => -0.035,
      2 => 0.05,
      _ => -0.065,
    };
    final horizontalOffset = switch (depth) {
      1 => -4.0,
      2 => 7.0,
      _ => -5.0,
    };

    return Transform.translate(
      offset: Offset(horizontalOffset, depth * 7.0),
      child: Transform.rotate(
        angle: angle,
        child: Transform.scale(
          scale: 1 - (depth * 0.018),
          child: Opacity(
            opacity: 1 - (depth * 0.11),
            child: IgnorePointer(
              child: _SwapCard(width: width, height: height, item: item),
            ),
          ),
        ),
      ),
    );
  }
}

/// QuickSwipe cards use a deliberately dense glass treatment because several
/// cards overlap and their text must remain readable over the forest photo.
class _SwipeGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SwipeGlassCard({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(28));
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xE0363933),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.32),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DirectionHint extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DirectionHint({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}

class _DecisionStamp extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _DecisionStamp({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _DecisionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.12),
          shape: CircleBorder(
            side: BorderSide(color: color.withValues(alpha: 0.7)),
          ),
          child: IconButton(
            tooltip: label,
            onPressed: onPressed,
            icon: Icon(icon, color: color, size: 32),
            padding: const EdgeInsets.all(15),
          ),
        ),
        const SizedBox(height: 7),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}

class _QuickSwipeItem {
  final String challengeId;
  final String category;
  final int itemIndex;
  final String label;
  final bool isCompleted;

  const _QuickSwipeItem({
    required this.challengeId,
    required this.category,
    required this.itemIndex,
    required this.label,
    required this.isCompleted,
  });

  _QuickSwipeItem copyWith({bool? isCompleted}) {
    return _QuickSwipeItem(
      challengeId: challengeId,
      category: category,
      itemIndex: itemIndex,
      label: label,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
