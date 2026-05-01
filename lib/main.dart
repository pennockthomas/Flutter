import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart'; // ✅ Added for sound
import 'app_settings.dart';
import 'challenge_repository.dart';
import 'playground.dart';
import 'profile_page.dart';
import 'progress_register_page.dart';
import 'settings.dart';
import 'start_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const StartupScreen(),
    );
  }
}

// ---------------- ECOSTEPS STARTUP WITH SOUND -----------------

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _iconGrow;
  late Animation<double> _fadeText;

  // ✅ Audio player instance
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Elastic pop effect for the eco icon
    _iconGrow = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
    );

    // Smooth fade for the text
    _fadeText = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
    );

    // ✅ Fire the sound and animation
    _playStartupSound();
    _controller.forward();
    _navigateToHome();
  }

  Future<void> _playStartupSound() async {
    try {
      // We removed SharedPreferences entirely here so it ignores the toggle

      // A small delay ensures the audio engine is "awake" before the asset fires
      await Future.delayed(const Duration(milliseconds: 200));

      // Direct play command
      await _audioPlayer.play(AssetSource('sounds/startup.mp3'));

      debugPrint("Startup sound triggered (ignoring settings)");
    } catch (e) {
      debugPrint("Sound error: $e");
    }
  }

  Future<void> _navigateToHome() async {
    await Future.delayed(const Duration(milliseconds: 4000));

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 1000),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose(); // ✅ Clean up player
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0A), // Deep eco-black
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.3,
              child: Image.asset('assets/background.jpg', fit: BoxFit.cover),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _iconGrow,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.2),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          color: Colors.white.withOpacity(0.05),
                          child: const Icon(
                            Icons.eco_rounded,
                            size: 70,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                FadeTransition(
                  opacity: _fadeText,
                  child: Column(
                    children: [
                      const Text(
                        "EcoSteps",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "ONE STEP CLOSER TO PLASTIC-FREE",
                        style: TextStyle(
                          color: Colors.greenAccent.withOpacity(0.7),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
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

// ---------------- HOME SCREEN ----------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ChallengeRepository _challengeRepository = ChallengeRepository();
  bool _showWelcomeCard = true;
  int _completedItems = 0;
  int _totalItems = 0;

  @override
  void initState() {
    super.initState();
    _loadProgress();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      setState(() => _showWelcomeCard = false);
    });
  }

  Future<void> _loadProgress() async {
    final challenges = await _challengeRepository.loadChallenges();
    if (!mounted) return;

    final totalItems = challenges.values.fold(
      0,
      (total, challenge) => total + challenge.checklist.length,
    );
    final completedItems = challenges.values.fold(
      0,
      (total, challenge) =>
          total + challenge.checklist.where((item) => item.isCompleted).length,
    );

    setState(() {
      _completedItems = completedItems;
      _totalItems = totalItems;
    });
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
    await _loadProgress();
  }

  double get _progress {
    if (_totalItems == 0) return 0;
    return _completedItems / _totalItems;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: Image.asset('assets/background.jpg', fit: BoxFit.cover),
          ),
          const AppBackgroundOverlay(fallbackDarkness: 0.2),
          _ProfileWelcomeButton(
            showWelcomeCard: _showWelcomeCard,
            completedItems: _completedItems,
            totalItems: _totalItems,
            progress: _progress,
            onTap: () => _openPage(const ProfilePage()),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassButton(
                  text: "Start",
                  onPressed: () {
                    _openPage(const StartScreen());
                  },
                ),
                const SizedBox(height: 20),
                GlassButton(
                  text: "Progress Register",
                  onPressed: () {
                    _openPage(const ProgressRegisterPage());
                  },
                ),
                const SizedBox(height: 20),
                GlassButton(
                  text: "Playground",
                  onPressed: () {
                    _openPage(const PlaygroundScreen());
                  },
                ),
                const SizedBox(height: 20),
                GlassButton(
                  text: "Settings",
                  onPressed: () {
                    _openPage(const SettingsScreen());
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

class _ProfileWelcomeButton extends StatelessWidget {
  final bool showWelcomeCard;
  final int completedItems;
  final int totalItems;
  final double progress;
  final VoidCallback onTap;

  const _ProfileWelcomeButton({
    required this.showWelcomeCard,
    required this.completedItems,
    required this.totalItems,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth - 40).clamp(64.0, 340.0);

    return SafeArea(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
        alignment: showWelcomeCard ? Alignment.topCenter : Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeInOutCubic,
              width: showWelcomeCard ? cardWidth : 64,
              height: showWelcomeCard ? 88 : 64,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(showWelcomeCard ? 24 : 32),
                border: Border.all(color: Colors.white.withOpacity(0.28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.greenAccent.withOpacity(0.12),
                    blurRadius: 26,
                    spreadRadius: 2,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: showWelcomeCard
                      ? Padding(
                          key: const ValueKey('welcome'),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _MenuProgressAvatar(
                                progress: progress,
                                size: 54,
                                fontSize: 16,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Welcome back, Thomas',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '$completedItems/$totalItems swaps completed',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : Center(
                          key: const ValueKey('avatar'),
                          child: _MenuProgressAvatar(
                            progress: progress,
                            size: 52,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuProgressAvatar extends StatelessWidget {
  final double progress;
  final double size;
  final double fontSize;

  const _MenuProgressAvatar({
    required this.progress,
    required this.size,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: Colors.white12,
              color: Colors.greenAccent,
            ),
          ),
          Container(
            width: size - 9,
            height: size - 9,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Center(
              child: Text(
                'TP',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- GLASS BUTTON ----------------

class GlassButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const GlassButton({super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Center(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
