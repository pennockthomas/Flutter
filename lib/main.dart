import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart'; // ✅ Added for sound
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';
import 'app_shell.dart';
import 'background_music.dart';
import 'firebase_options.dart';
import 'intro_page.dart';
import 'notifications.dart';
import 'progress_sync.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    ProgressSync.instance.start();
  } catch (e) {
    // Accounts/sync are additive — the app must stay fully usable offline
    // even if Firebase can't be reached (no network, misconfigured project).
    debugPrint('Firebase init failed, continuing in local-only mode: $e');
  }
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
  Timer? _startupTimer;
  bool _didNavigate = false;

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
    BackgroundMusicController.instance.syncWithSettings();
    AppSettings.loadReducedMotion();
    NotificationService.instance.syncDailyReminders();
    _controller.forward();
    _startupTimer = Timer(const Duration(milliseconds: 4200), _goToHome);
  }

  Future<void> _playStartupSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final soundEnabled = prefs.getBool(AppSettingKeys.startupSound) ?? true;
      if (!soundEnabled) return;

      // A small delay ensures the audio engine is "awake" before the asset fires
      await Future.delayed(const Duration(milliseconds: 200));

      await _audioPlayer.play(AssetSource('sounds/startup.mp3'));
    } catch (e) {
      debugPrint("Sound error: $e");
    }
  }

  Future<void> _goToHome() async {
    if (!mounted || _didNavigate) return;
    _didNavigate = true;

    // First launch shows the intro before Home; after that, straight home.
    final introSeen = await IntroPage.hasBeenSeen();
    if (!mounted) return;

    // Captured now: this screen (and its context) is gone by the time the
    // intro finishes, but the app's navigator outlives it.
    final navigator = Navigator.of(context);
    navigator.pushReplacement(
      _fadeRoute(
        introSeen
            ? const AppShell()
            : IntroPage(
                onFinished: () =>
                    navigator.pushReplacement(_fadeRoute(const AppShell())),
              ),
      ),
    );
  }

  static Route<void> _fadeRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
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
          Positioned(
            right: 24,
            bottom: 24,
            child: SafeArea(
              child: TextButton(
                onPressed: _goToHome,
                child: const Text(
                  "Continue",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
