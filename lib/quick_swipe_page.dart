import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'challenge_store.dart';
import 'glass_panel.dart';
import 'profile_avatar_button.dart';

class QuickSwipePage extends StatefulWidget {
  const QuickSwipePage({super.key});

  @override
  State<QuickSwipePage> createState() => _QuickSwipePageState();
}

class _QuickSwipePageState extends State<QuickSwipePage>
    with SingleTickerProviderStateMixin {
  static const double _decisionThreshold = 90;

  List<_QuickSwipeItem> _items = [];
  int _currentIndex = 0;
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  bool _isSaving = false;
  bool _isLoading = true;
  bool _isShuffling = false;
  String? _loadError;

  /// Drives the shuffle flourish: 0 → 1 fans the visible cards out, the item
  /// order is swapped at the peak, then 1 → 0 brings the (now reordered)
  /// cards back into the stack.
  late final AnimationController _shuffleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  _QuickSwipeItem? get _currentItem =>
      _currentIndex < _items.length ? _items[_currentIndex] : null;

  /// A small persistent tilt per card position, so cards don't all rest at
  /// the exact same angle. It's keyed to the item's slot in `_items` (not a
  /// random value picked at render time) so a given card always renders
  /// with the same tilt whether it's a stacked preview or the active card —
  /// that's what lets a promoted card keep its angle with zero visible jump.
  static const List<double> _wobblePattern = [
    0.05,
    -0.07,
    0.06,
    -0.045,
    0.08,
    -0.06,
    0.04,
    -0.08,
  ];

  double _itemWobble(int globalIndex) {
    if (globalIndex == 0) return 0;
    return _wobblePattern[globalIndex % _wobblePattern.length];
  }

  @override
  void initState() {
    super.initState();
    ChallengeStore.instance.addListener(_onChallengesChanged);
    _loadItems();
  }

  /// This page stays alive as a tab, so items checked off on the Tree or
  /// Progress tabs need reflecting here. Only completion state is refreshed;
  /// the review order and position are kept. Skipped mid-save, since
  /// [_saveDecision] updates its own item once the save finishes.
  void _onChallengesChanged() {
    if (!mounted || _isSaving || _items.isEmpty) return;
    final challenges = ChallengeStore.instance.challenges;
    setState(() {
      _items = [
        for (final item in _items)
          item.copyWith(
            isCompleted:
                challenges[item.challengeId]?.checklist
                    .elementAtOrNull(item.itemIndex)
                    ?.isCompleted ??
                item.isCompleted,
          ),
      ];
    });
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

  Future<void> _shuffleRemaining() async {
    if (_isSaving || _isShuffling || _currentIndex >= _items.length - 1) {
      return;
    }
    setState(() => _isShuffling = true);
    await _shuffleController.forward(from: 0);
    if (!mounted) return;
    setState(() {
      final remaining = _items.sublist(_currentIndex)..shuffle();
      _items = [..._items.sublist(0, _currentIndex), ...remaining];
    });
    await _shuffleController.reverse();
    if (!mounted) return;
    setState(() {
      _isShuffling = false;
      _dragOffset = Offset.zero;
    });
  }

  @override
  void dispose() {
    ChallengeStore.instance.removeListener(_onChallengesChanged);
    _shuffleController.dispose();
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
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 6),
      child: Row(
        children: [
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
          if (!_isLoading && _items.isNotEmpty) ...[
            IconButton(
              tooltip: 'Shuffle remaining swaps',
              icon: const Icon(Icons.shuffle_rounded, color: Colors.white70),
              onPressed: _isShuffling || _currentIndex >= _items.length - 1
                  ? null
                  : _shuffleRemaining,
            ),
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
          const SizedBox(width: 12),
          const ProfileAvatarButton(),
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
              'There are no swaps to review yet.',
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

        if (_isShuffling) {
          return _buildShuffleAnimation(cardWidth, cardHeight);
        }

        final item = _currentItem!;
        final strength = (_dragOffset.dx / _decisionThreshold).clamp(-1.0, 1.0);
        final wobble = _itemWobble(_currentIndex);

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
                      wobble: _itemWobble(_currentIndex + depth),
                    ),
                // A card just promoted from depth 1 looked slightly offset,
                // scaled down, and faded as a preview a moment ago. Easing
                // from that exact look up to the true "active" look (instead
                // of snapping straight there) is what removes the teleport —
                // its rotation never needs to change at all, since `wobble`
                // is the same value it already had as a depth-1 preview.
                TweenAnimationBuilder<double>(
                  key: ValueKey('${item.challengeId}:${item.itemIndex}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  builder: (context, settle, child) {
                    final baseOffset = Offset.lerp(
                      Offset(
                        _StackedPreviewCard.offsetXForDepth(1),
                        _StackedPreviewCard.offsetYForDepth(1),
                      ),
                      Offset.zero,
                      settle,
                    )!;
                    final baseScale = ui.lerpDouble(
                      _StackedPreviewCard.scaleForDepth(1),
                      1.0,
                      settle,
                    )!;
                    final baseOpacity = ui.lerpDouble(
                      _StackedPreviewCard.opacityForDepth(1),
                      1.0,
                      settle,
                    )!;
                    return Opacity(
                      opacity: baseOpacity,
                      child: Transform.translate(
                        offset: baseOffset,
                        child: Transform.scale(scale: baseScale, child: child),
                      ),
                    );
                  },
                  child: TweenAnimationBuilder<Offset>(
                    tween: Tween<Offset>(end: _dragOffset),
                    duration: _isDragging
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    builder: (context, offset, child) {
                      return Transform.translate(
                        offset: offset,
                        child: Transform.rotate(
                          angle: wobble + (offset.dx / cardWidth) * 0.12,
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Shown instead of the normal interactive deck while [_isShuffling]. It's
  /// deliberately a separate, non-interactive render path rather than trying
  /// to blend the fan effect into the draggable active-card machinery above
  /// — dragging is disabled for the moment anyway, so there's nothing to
  /// reconcile. `_shuffleController` runs 0→1 (fan out), the item order is
  /// swapped at the peak, then 1→0 (cards land back into the stack, now
  /// showing the reshuffled order).
  Widget _buildShuffleAnimation(double cardWidth, double cardHeight) {
    return AnimatedBuilder(
      animation: _shuffleController,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_shuffleController.value);
        final layers = <Widget>[];

        for (var depth = 3; depth >= 0; depth--) {
          final index = _currentIndex + depth;
          if (index >= _items.length) continue;
          final item = _items[index];

          final stackOffsetX = depth == 0
              ? 0.0
              : _StackedPreviewCard.offsetXForDepth(depth);
          final stackOffsetY = depth == 0
              ? 0.0
              : _StackedPreviewCard.offsetYForDepth(depth);
          final stackScale = depth == 0
              ? 1.0
              : _StackedPreviewCard.scaleForDepth(depth);
          final stackOpacity = depth == 0
              ? 1.0
              : _StackedPreviewCard.opacityForDepth(depth);
          final stackAngle = depth == 0
              ? _itemWobble(index)
              : _itemWobble(index) + _StackedPreviewCard.fanBonusForDepth(depth);

          // A hand-of-cards spread: fanned horizontally by depth, each one
          // tilted further out from center than the last.
          final fanSpread = depth - 1.5;
          final fanOffsetX = fanSpread * 78.0;
          final fanOffsetY = 22.0 + depth * 5.0;
          final fanAngle = fanSpread * 0.42;

          layers.add(
            Transform.translate(
              offset: Offset(
                ui.lerpDouble(stackOffsetX, fanOffsetX, t)!,
                ui.lerpDouble(stackOffsetY, fanOffsetY, t)!,
              ),
              child: Transform.rotate(
                angle: ui.lerpDouble(stackAngle, fanAngle, t)!,
                child: Transform.scale(
                  scale: ui.lerpDouble(stackScale, 0.92, t)!,
                  child: Opacity(
                    opacity: ui.lerpDouble(stackOpacity, 1.0, t)!,
                    child: _SwapCard(
                      width: cardWidth,
                      height: cardHeight,
                      item: item,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Center(
          child: SizedBox(
            width: cardWidth,
            height: cardHeight,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: layers,
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
            onPressed: _isSaving || _isShuffling
                ? null
                : () => _saveDecision(false),
          ),
          _DecisionButton(
            icon: Icons.check_rounded,
            label: 'Done',
            color: Colors.greenAccent,
            onPressed: _isSaving || _isShuffling
                ? null
                : () => _saveDecision(true),
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
  final double wobble;

  const _StackedPreviewCard({
    required this.depth,
    required this.width,
    required this.height,
    required this.item,
    required this.wobble,
  });

  /// Extra tilt layered on top of the card's own persistent [wobble] so a
  /// stack of several cards visibly fans out. Zero at depth 1 on purpose:
  /// that's the position a card is promoted from, so its angle (wobble +
  /// this bonus) must be identical the instant before and after promotion.
  static double fanBonusForDepth(int depth) => switch (depth) {
    1 => 0.0,
    2 => 0.035,
    _ => -0.035,
  };

  static double offsetXForDepth(int depth) => switch (depth) {
    1 => -6.0,
    2 => 10.0,
    _ => -8.0,
  };

  static double offsetYForDepth(int depth) => depth * 7.0;

  static double scaleForDepth(int depth) => 1 - (depth * 0.018);

  static double opacityForDepth(int depth) => 1 - (depth * 0.11);

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(offsetXForDepth(depth), offsetYForDepth(depth)),
      child: Transform.rotate(
        angle: wobble + fanBonusForDepth(depth),
        child: Transform.scale(
          scale: scaleForDepth(depth),
          child: Opacity(
            opacity: opacityForDepth(depth),
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
