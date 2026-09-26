import 'package:flutter/material.dart';

/// Softens the hard viewport edge of a vertical scroll view. The fade only
/// appears on an edge when more content exists beyond that edge.
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (!_showTopFade && !_showBottomFade) return widget.child;

            final height = constraints.maxHeight;
            final fadeFraction = height.isFinite && height > 0
                ? (widget.fadeExtent / height).clamp(0.0, 0.18)
                : 0.06;
            return ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _showTopFade ? Colors.transparent : Colors.white,
                  Colors.white,
                  Colors.white,
                  _showBottomFade ? Colors.transparent : Colors.white,
                ],
                stops: [0, fadeFraction, 1 - fadeFraction, 1],
              ).createShader(bounds),
              child: widget.child,
            );
          },
        ),
      ),
    );
  }
}
