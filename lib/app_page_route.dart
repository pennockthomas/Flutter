import 'package:flutter/material.dart';

import 'app_settings.dart';

/// The shared transition for navigation inside EcoSteps. A short fade with a
/// very small vertical drift keeps glass-heavy screens calm in both directions
/// without the hard edge of the platform's full-width slide transition.
Route<T> appPageRoute<T>(Widget page) {
  final reduceMotion = AppSettings.reducedMotion.value;
  return PageRouteBuilder<T>(
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 320),
    reverseTransitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion) return child;

      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}
