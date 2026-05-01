import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart'; // ✅ Added for sound
import 'playground.dart';
import 'settings.dart'; 

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

// ---------------- ECOSTEPS STARTUP WITH SOUND ----------------

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> with SingleTickerProviderStateMixin {
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
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
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
              child: Image.asset(
                'assets/background.jpg',
                fit: BoxFit.cover,
              ),
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
                        )
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
                            color: Colors.greenAccent
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: Image.asset(
              'assets/background.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Container(color: Colors.black.withOpacity(0.2)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassButton(
                  text: "Start",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NextScreen()),
                    );
                  },
                ),
                const SizedBox(height: 20),
                GlassButton(
                  text: "Playground",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PlaygroundScreen()),
                    );
                  },
                ),
                const SizedBox(height: 20),
                GlassButton(
                  text: "Settings",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    );
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

// ---------------- GLASS BUTTON ----------------

class GlassButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const GlassButton({
    super.key,
    required this.text,
    required this.onPressed,
  });

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

// ---------------- NEXT SCREEN (PARALLAX) ----------------

class NextScreen extends StatefulWidget {
  const NextScreen({super.key});
  @override
  State<NextScreen> createState() => _NextScreenState();
}

class _NextScreenState extends State<NextScreen> with SingleTickerProviderStateMixin {
  Offset offset = Offset.zero;
  late AnimationController controller;
  late Animation<Offset> animation;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  }

  void animateBack() {
    animation = Tween<Offset>(begin: offset, end: Offset.zero).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    )..addListener(() { setState(() { offset = animation.value; }); });
    controller.forward(from: 0);
  }

  void openDetail(String name) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(label: name)));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      body: GestureDetector(
        onPanUpdate: (details) {
          controller.stop();
          setState(() {
            offset += details.delta * 0.5;
            offset = Offset(offset.dx.clamp(-80, 80), offset.dy.clamp(-80, 80));
          });
        },
        onPanEnd: (_) => animateBack(),
        child: Stack(
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
            Container(color: Colors.black.withOpacity(0.2)),
            Transform.translate(
              offset: offset,
              child: CustomPaint(
                painter: LinePainter(),
                child: Stack(
                  children: [
                    Positioned(top: 200, left: screenWidth / 2 - 50, child: GlassCircle(label: "Core", onTap: () => openDetail("Core"))),
                    Positioned(top: 350, left: screenWidth * 0.2 - 50, child: GlassCircle(label: "Skill 1", onTap: () => openDetail("Skill 1"))),
                    Positioned(top: 350, left: screenWidth * 0.5 - 50, child: GlassCircle(label: "Skill 2", onTap: () => openDetail("Skill 2"))),
                    Positioned(top: 350, left: screenWidth * 0.8 - 50, child: GlassCircle(label: "Skill 3", onTap: () => openDetail("Skill 3"))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- HELPERS ----------------

class GlassCircle extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const GlassCircle({super.key, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Center(child: Text(label, style: const TextStyle(color: Colors.white))),
          ),
        ),
      ),
    );
  }
}

class LinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.3)..strokeWidth = 2;
    final centerX = size.width / 2;
    final main = Offset(centerX, 250);
    canvas.drawLine(main, Offset(size.width * 0.2, 400), paint);
    canvas.drawLine(main, Offset(centerX, 400), paint);
    canvas.drawLine(main, Offset(size.width * 0.8, 400), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DetailScreen extends StatelessWidget {
  final String label;
  const DetailScreen({super.key, required this.label});
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}