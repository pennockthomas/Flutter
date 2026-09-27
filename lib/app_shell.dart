import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'background_music.dart';
import 'progress_register_page.dart';
import 'quick_swipe_page.dart';
import 'start_page.dart';

/// The app's main screen after startup: the unlock tree plus QuickSwipe and
/// Progress, switched with a glass tab bar at the bottom. Profile opens from
/// the avatar in each tab's top-right corner, and Settings from Profile.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const _pages = [StartScreen(), QuickSwipePage(), ProgressRegisterPage()];

  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    BackgroundMusicController.instance.handleAppLifecycleChange(
      state == AppLifecycleState.resumed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // The pages' background photo runs behind the floating tab bar; pages
      // still keep their content above it because extendBody adds the bar's
      // height to the bottom padding their SafeAreas see.
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: [
          // Tabs keep their state while hidden, but TickerMode pauses their
          // animations — notably the tree's always-running physics.
          for (var i = 0; i < _pages.length; i++)
            TickerMode(enabled: i == _index, child: _pages[i]),
        ],
      ),
      bottomNavigationBar: ShellTabBar(
        currentIndex: _index,
        onSelect: (index) => setState(() => _index = index),
      ),
    );
  }
}

class ShellTab {
  final IconData icon;
  final String label;

  const ShellTab(this.icon, this.label);
}

class ShellTabBar extends StatelessWidget {
  static const tabs = [
    ShellTab(Icons.account_tree_rounded, 'Tree'),
    ShellTab(Icons.style_rounded, 'QuickSwipe'),
    ShellTab(Icons.checklist_rounded, 'Progress'),
  ];

  final int currentIndex;
  final ValueChanged<int> onSelect;

  const ShellTabBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(28));
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: radius,
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _TabButton(
                        tab: tabs[i],
                        selected: i == currentIndex,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final ShellTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.greenAccent : Colors.white70;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tab.icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(
              tab.label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
