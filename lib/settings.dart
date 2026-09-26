import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'app_user.dart';
import 'background_music.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ValueNotifier<double> _backgroundDarkness =
      AppSettings.backgroundDarkness;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await AppSettings.loadBackgroundDarkness();
  }

  void _navigateToSubPage(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SubSettingsPage(
          title: title,
          backgroundDarkness: _backgroundDarkness,
          children: children,
        ),
      ),
    );
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
          ValueListenableBuilder<double>(
            valueListenable: _backgroundDarkness,
            builder: (context, darkness, child) {
              return Container(color: Colors.black.withOpacity(darkness));
            },
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 10),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 28,
                    ),
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
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _buildSettingsTile(
                        context,
                        Icons.person_outline,
                        "Account Profile",
                        [
                          _infoTile("Name", AppUser.name),
                          _infoTile("Profile ID", "Local profile"),
                          _infoTile("Impact Level", "Getting Started"),
                          _infoTile("Avatar", "Initials: ${AppUser.initials}"),
                        ],
                      ),
                      _buildSettingsTile(
                        context,
                        Icons.palette_outlined,
                        "Appearance",
                        [
                          _BackgroundDarknessTile(
                            darkness: _backgroundDarkness,
                          ),
                          const _SettingSwitchTile(
                            label: "Reduce Motion",
                            preferenceKey: AppSettingKeys.reducedMotion,
                            defaultValue: false,
                          ),
                          const _SettingSwitchTile(
                            label: "High Contrast Text",
                            preferenceKey: AppSettingKeys.highContrastText,
                            defaultValue: false,
                          ),
                          _infoTile("Current Theme", "Glass Forest"),
                        ],
                      ),
                      _buildSettingsTile(
                        context,
                        Icons.people_alt_outlined,
                        "Friends & Sharing",
                        [
                          const _SettingSwitchTile(
                            label: "Share Total Progress",
                            preferenceKey: AppSettingKeys.shareTotalProgress,
                            defaultValue: true,
                          ),
                          const _SettingSwitchTile(
                            label: "Share Area Progress",
                            preferenceKey: AppSettingKeys.shareCategoryProgress,
                            defaultValue: true,
                          ),
                          const _SettingSwitchTile(
                            label: "Share Checked Items",
                            preferenceKey: AppSettingKeys.shareChecklistItems,
                            defaultValue: false,
                          ),
                          _infoTile("Friend Requests", "Coming later"),
                        ],
                      ),
                      _buildSettingsTile(
                        context,
                        Icons.storage_outlined,
                        "Progress & Data",
                        [
                          _infoTile("Storage", "Local JSON file"),
                          _infoTile("Progress Register", "Enabled"),
                          _infoTile("Developer Editor", "Local seed editor"),
                          _infoTile("Export / Import", "Coming later"),
                          _infoTile("Reset Progress", "Available in Start"),
                        ],
                      ),
                      _buildSettingsTile(
                        context,
                        Icons.volume_up_rounded,
                        "Sounds",
                        [
                          const _SettingSwitchTile(
                            label: "Startup Sound",
                            preferenceKey: AppSettingKeys.startupSound,
                            defaultValue: true,
                          ),
                          const _SettingSwitchTile(
                            label: "System Sounds",
                            preferenceKey: AppSettingKeys.systemSounds,
                            defaultValue: true,
                          ),
                          _SettingSwitchTile(
                            label: "Background Music",
                            preferenceKey: AppSettingKeys.backgroundMusic,
                            defaultValue: false,
                            onChanged: (_) =>
                                BackgroundMusicController.instance
                                    .syncWithSettings(),
                          ),
                        ],
                      ),
                      _buildSettingsTile(
                        context,
                        Icons.notifications_active_outlined,
                        "Notifications",
                        const [
                          _SettingSwitchTile(
                            label: "Daily Reminders",
                            preferenceKey: AppSettingKeys.dailyReminders,
                            defaultValue: true,
                          ),
                          _SettingSwitchTile(
                            label: "Milestone Alerts",
                            preferenceKey: AppSettingKeys.milestoneAlerts,
                            defaultValue: true,
                          ),
                          _SettingSwitchTile(
                            label: "Friend Updates",
                            preferenceKey: AppSettingKeys.friendUpdates,
                            defaultValue: false,
                          ),
                        ],
                      ),
                      _buildSettingsTile(
                        context,
                        Icons.security_outlined,
                        "Privacy & Security",
                        [
                          _infoTile("Current Mode", "Local only"),
                          _infoTile("Cloud Sync", "Not connected"),
                          _infoTile("Authentication", "Not required yet"),
                          _infoTile("Private Items", "Coming later"),
                        ],
                      ),
                      _buildSettingsTile(
                        context,
                        Icons.help_outline,
                        "Help & Support",
                        [
                          _infoTile("How Progress Works", "Checklist items"),
                          _infoTile("Friends", "Prototype mode"),
                          _infoTile("Contact", "support@ecosteps.app"),
                        ],
                      ),
                      const SizedBox(height: 40),
                      Center(
                        child: Text(
                          "Version 1.0.4",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
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

  Widget _buildSettingsTile(
    BuildContext context,
    IconData icon,
    String title,
    List<Widget> subContent,
  ) {
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
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withOpacity(0.4),
                  ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingSwitchTile extends StatefulWidget {
  final String label;
  final String preferenceKey;
  final bool defaultValue;
  final ValueChanged<bool>? onChanged;

  const _SettingSwitchTile({
    required this.label,
    required this.preferenceKey,
    required this.defaultValue,
    this.onChanged,
  });

  @override
  State<_SettingSwitchTile> createState() => _SettingSwitchTileState();
}

class _SettingSwitchTileState extends State<_SettingSwitchTile> {
  late bool _value = widget.defaultValue;

  @override
  void initState() {
    super.initState();
    _loadValue();
  }

  Future<void> _loadValue() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _value = prefs.getBool(widget.preferenceKey) ?? widget.defaultValue;
    });
  }

  Future<void> _setValue(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(widget.preferenceKey, value);
    if (!mounted) return;
    setState(() => _value = value);
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          Switch(
            value: _value,
            onChanged: _setValue,
            activeThumbColor: Colors.greenAccent,
          ),
        ],
      ),
    );
  }
}

class _BackgroundDarknessTile extends StatefulWidget {
  final ValueNotifier<double> darkness;

  const _BackgroundDarknessTile({required this.darkness});

  @override
  State<_BackgroundDarknessTile> createState() =>
      _BackgroundDarknessTileState();
}

class _BackgroundDarknessTileState extends State<_BackgroundDarknessTile> {
  static const double _maxDarkness = 0.7;

  double _brightnessFromDarkness(double darkness) {
    return ((1 - (darkness / _maxDarkness)) * 100).clamp(0, 100).toDouble();
  }

  double _darknessFromBrightness(double brightness) {
    return ((1 - (brightness / 100)) * _maxDarkness)
        .clamp(0, _maxDarkness)
        .toDouble();
  }

  Future<void> _setDarkness(double value) async {
    await AppSettings.setBackgroundDarkness(value);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.darkness,
      builder: (context, darkness, child) {
        final brightness = _brightnessFromDarkness(darkness);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Background Brightness",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  Text(
                    "${brightness.round()}%",
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Slider(
                value: brightness,
                min: 0.0,
                max: 100,
                divisions: 20,
                activeColor: Colors.greenAccent,
                inactiveColor: Colors.white24,
                onChanged: (value) =>
                    _setDarkness(_darknessFromBrightness(value)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SubSettingsPage extends StatelessWidget {
  final String title;
  final ValueNotifier<double> backgroundDarkness;
  final List<Widget> children;

  const SubSettingsPage({
    super.key,
    required this.title,
    required this.backgroundDarkness,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SizedBox.expand(
            child: Image.asset('assets/background.jpg', fit: BoxFit.cover),
          ),
          ValueListenableBuilder<double>(
            valueListenable: backgroundDarkness,
            builder: (context, darkness, child) {
              return Container(color: Colors.black.withOpacity(darkness));
            },
          ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Container(
                          padding: const EdgeInsets.all(25),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
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
