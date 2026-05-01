import 'dart:ui';
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // Helper to build the sub-pages on the fly
  void _navigateToSubPage(BuildContext context, String title, List<Widget> children) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SubSettingsPage(title: title, children: children),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Image
          SizedBox.expand(
            child: Image.asset(
              'assets/background.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.blueGrey[900]),
            ),
          ),
          
          // Background darkening set to 0.1 for maximum vibrance
          Container(color: Colors.black.withOpacity(0.2)),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back Button
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 10),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                  child: Text(
                    "Settings",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),

                // Settings List
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // --- SOUNDS MENU ---


                      _buildSettingsTile(context, Icons.person_outline, "Account Profile", [
                        _infoTile("Username", "EcoWarrior_01"),
                        _infoTile("Email", "nature@example.com"),
                        _infoTile("Impact Level", "Plastic Reducer (Lvl 4)"),
                      ]),

                      _buildSettingsTile(context, Icons.volume_up_rounded, "Sounds", [
                        _switchTile("Startup Sound", true),
                        _switchTile("System Sounds", true),
                        _switchTile("Background Music", true),
                      ]),                      

                      _buildSettingsTile(context, Icons.notifications_active_outlined, "Notifications", [
                        _switchTile("Daily Reminders", true),
                        _switchTile("Milestone Alerts", true),
                        _switchTile("Eco News", false),
                      ]),

                      _buildSettingsTile(context, Icons.palette_outlined, "Theme Appearance", [
                        _infoTile("Current Theme", "Glass Forest (Dark)"),
                        _infoTile("Node Style", "Organic Bubbles"),
                      ]),

                      _buildSettingsTile(context, Icons.security_outlined, "Privacy & Security", [
                        _infoTile("Data Usage", "Local Storage Only"),
                        _infoTile("Encryption", "AES-256 Active"),
                      ]),

                      _buildSettingsTile(context, Icons.help_outline, "Help & Support", [
                        _infoTile("FAQ", "How to track progress?"),
                        _infoTile("Contact", "support@ecosteps.app"),
                      ]),

                      const SizedBox(height: 40),
                      
                      Center(
                        child: Text(
                          "Version 1.0.4",
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
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

  Widget _buildSettingsTile(BuildContext context, IconData icon, String title, List<Widget> subContent) {
    return GestureDetector(
      onTap: () => _navigateToSubPage(context, title, subContent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 24),
                  const SizedBox(width: 20),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _infoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  static Widget _switchTile(String label, bool val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
          Switch(
            value: val, 
            onChanged: (v) {}, 
            activeColor: Colors.greenAccent,
          ),
        ],
      ),
    );
  }
}

// ---------------- SUB-PAGE COMPONENT ----------------

// ---------------- SUB-PAGE COMPONENT ----------------

class SubSettingsPage extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SubSettingsPage({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Sub-page background
          SizedBox.expand(
            child: Image.asset('assets/background.jpg', fit: BoxFit.cover),
          ),
          Container(color: Colors.black.withOpacity(0.2)),
          
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  padding: const EdgeInsets.all(20),
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Text(
                    title, 
                    style: const TextStyle(
                      color: Colors.white, 
                      fontSize: 28, 
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), // Frosted effect
                        child: Container(
                          padding: const EdgeInsets.all(25),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1), // Glass tint
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          child: SingleChildScrollView(
                            child: Column(children: children),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}