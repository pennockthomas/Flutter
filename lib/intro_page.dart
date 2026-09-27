import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'glass_panel.dart';

/// Short first-run explanation of what EcoSteps is for, shown once between
/// the startup splash and Home. [onFinished] runs after "Get started" or
/// "Skip", once the seen-flag is saved; the caller decides where to go next.
class IntroPage extends StatefulWidget {
  final VoidCallback onFinished;

  const IntroPage({super.key, required this.onFinished});

  static Future<bool> hasBeenSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppSettingKeys.introSeen) ?? false;
  }

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroSlide {
  final IconData icon;
  final String title;
  final String body;

  const _IntroSlide(this.icon, this.title, this.body);
}

const _slides = [
  _IntroSlide(
    Icons.eco_rounded,
    'Swap plastic for things that last',
    'EcoSteps is a checklist of everyday swaps — metal knives, glass jars, '
        'a bamboo toothbrush — that replace plastic around your home, one '
        'step at a time.',
  ),
  _IntroSlide(
    Icons.account_tree_rounded,
    'Grow your tree',
    'Tap Start to begin. Each bubble is an area of your life, like the '
        'Kitchen or Bathroom. Open its checklist, or unlock the next level '
        'to go deeper.',
  ),
  _IntroSlide(
    Icons.check_circle_rounded,
    'Count what you already do',
    'Already own some of these? Tick them off in QuickSwipe or the Progress '
        'Register, so your progress starts where you are. Everything stays '
        'on your phone unless you sign in.',
  ),
];

class _IntroPageState extends State<IntroPage> {
  final _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  bool get _isLastPage => _page == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppSettingKeys.introSeen, true);
    if (!mounted) return;
    widget.onFinished();
  }

  void _next() {
    if (_isLastPage) {
      _finish();
      return;
    }
    if (AppSettings.reducedMotion.value) {
      _controller.jumpToPage(_page + 1);
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
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
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                    child: AnimatedOpacity(
                      opacity: _isLastPage ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: TextButton(
                        onPressed: _isLastPage ? null : _finish,
                        child: const Text(
                          'Skip',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, index) =>
                        _IntroSlideView(slide: _slides[index]),
                  ),
                ),
                _PageDots(count: _slides.length, current: _page),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      minimumSize: const Size.fromHeight(52),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(_isLastPage ? 'Get started' : 'Next'),
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

class _IntroSlideView extends StatelessWidget {
  final _IntroSlide slide;

  const _IntroSlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: GlassPanel(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.greenAccent.withValues(alpha: 0.12),
                  border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(slide.icon, size: 48, color: Colors.greenAccent),
              ),
              const SizedBox(height: 28),
              Text(
                slide.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                slide.body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int current;

  const _PageDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current ? Colors.greenAccent : Colors.white30,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
