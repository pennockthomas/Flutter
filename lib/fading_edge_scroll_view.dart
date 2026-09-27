import 'package:flutter/material.dart';

/// Softens the hard viewport edge of a vertical scroll view. The fade only
/// appears on an edge when more content exists beyond that edge.
///
/// Implemented as a gradient scrim drawn *on top* of the scroll view rather
/// than a `ShaderMask` wrapping it. A `ShaderMask` forces its child onto its
/// own offscreen compositing layer, which cuts off any `BackdropFilter`
/// inside that child from the real backdrop behind it (the background photo
/// painted as an earlier sibling in the page's Stack) — its blur ends up
/// sampling that isolated, nearly-blank layer instead, which is why glass
/// panels inside a scrolling list looked far less blurred than identical
/// panels elsewhere on the same screen. A plain overlay has no such effect.
class FadingEdgeScrollView extends StatefulWidget {
  final Widget child;
  final double fadeExtent;

  const FadingEdgeScrollView({
    super.key,
    required this.child,
    this.fadeExtent = 28,
  });

  @override
  State<FadingEdgeScrollView> createState() => _FadingEdgeScrollViewState();
}

class _FadingEdgeScrollViewState extends State<FadingEdgeScrollView> {
  bool _showTopFade = false;
  bool _showBottomFade = false;
  bool _nextTopFade = false;
  bool _nextBottomFade = false;
  bool _updateScheduled = false;

  void _queueMetricsUpdate(ScrollMetrics metrics) {
    _nextTopFade = metrics.extentBefore > 0.5;
    _nextBottomFade = metrics.extentAfter > 0.5;
    if (_updateScheduled ||
        (_nextTopFade == _showTopFade && _nextBottomFade == _showBottomFade)) {
      return;
    }

    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (!mounted ||
          (_nextTopFade == _showTopFade &&
              _nextBottomFade == _showBottomFade)) {
        return;
      }
      setState(() {
        _showTopFade = _nextTopFade;
        _showBottomFade = _nextBottomFade;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) {
          _queueMetricsUpdate(notification.metrics);
        }
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            _queueMetricsUpdate(notification.metrics);
          }
          return false;
        },
        child: Stack(
          children: [
            widget.child,
            if (_showTopFade)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: widget.fadeExtent,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(context).scaffoldBackgroundColor,
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_showBottomFade)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: widget.fadeExtent,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Theme.of(context).scaffoldBackgroundColor,
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
