import 'dart:convert';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'app_page_route.dart';
import 'background_music.dart';
import 'challenge_store.dart';
import 'fading_edge_scroll_view.dart';
import 'intro_page.dart';
import 'notifications.dart';
import 'playground.dart';

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

  Future<void> _exportProgress() async {
    try {
      final jsonText = await ChallengeStore.instance.exportJson();
      if (jsonText == null) {
        _showMessage('Nothing to export yet.');
        return;
      }
      // Use a screen-local rect rather than this route's global position:
      // this button lives on a screen pushed on top of SettingsScreen, and
      // that covered route sits at a parallax-shifted (non-zero) offset
      // that the share sheet's native side rejects as out of bounds.
      final screenSize = MediaQuery.sizeOf(context);
      final sharePositionOrigin = Rect.fromLTWH(
        0,
        0,
        screenSize.width,
        screenSize.height,
      );

      // Shared from memory rather than a file path, so it works the same on
      // devices and in the browser (where a download is offered instead).
      await Share.shareXFiles(
        [
          XFile.fromData(
            utf8.encode(jsonText),
            mimeType: 'application/json',
            name: 'ecosteps-progress.json',
          ),
        ],
        subject: 'EcoSteps progress',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      _showMessage('Could not export progress.');
    }
  }

  Future<void> _importProgress() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        // Bytes, not a path: the browser has no file paths to give.
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes == null) return;

      final jsonText = utf8.decode(bytes);
      if (!ChallengeStore.instance.isValidImportJson(jsonText)) {
        _showMessage(
          "That file isn't a valid EcoSteps export or contains a broken challenge tree.",
        );
        return;
      }
      if (!mounted) return;
      final confirmed = await _confirmDataReplacement(
        title: 'Import progress?',
        message:
            'This will replace your current challenge and checklist progress. EcoSteps will keep one pre-import backup that you can restore from this screen.',
        confirmLabel: 'Import',
      );
      if (!confirmed) return;

      final succeeded = await ChallengeStore.instance.importFromJson(jsonText);
      _showMessage(
        succeeded
            ? 'Progress imported.'
            : "That file doesn't look like an EcoSteps export.",
      );
    } catch (e) {
      _showMessage('Could not import progress.');
    }
  }

  Future<void> _restoreImportBackup() async {
    try {
      final hasBackup = await ChallengeStore.instance.hasImportBackup();
      if (!hasBackup) {
        _showMessage('No pre-import backup is available.');
        return;
      }
      if (!mounted) return;
      final confirmed = await _confirmDataReplacement(
        title: 'Restore previous progress?',
        message:
            'This will replace your current challenge and checklist progress with the backup created before your most recent import.',
        confirmLabel: 'Restore',
      );
      if (!confirmed) return;

      final succeeded = await ChallengeStore.instance.restoreImportBackup();
      _showMessage(
        succeeded
            ? 'Previous progress restored.'
            : 'Could not restore the pre-import backup.',
      );
    } catch (e) {
      _showMessage('Could not restore the pre-import backup.');
    }
  }

  Future<bool> _confirmDataReplacement({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _navigateToSubPage(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    Navigator.push(
      context,
      appPageRoute(
        SubSettingsPage(
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
                  child: FadingEdgeScrollView(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _buildSettingsTile(
                          context,
                          Icons.palette_outlined,
                          "Appearance",
                          [
                            _BackgroundDarknessTile(
                              darkness: _backgroundDarkness,
                            ),
                            _SettingSwitchTile(
                              label: "Reduce Motion",
                              preferenceKey: AppSettingKeys.reducedMotion,
                              defaultValue: false,
                              onChanged: AppSettings.setReducedMotion,
                            ),
                          ],
                        ),
                        _buildSettingsTile(
                          context,
                          Icons.storage_outlined,
                          "Progress & Data",
                          [
                            _actionTile("Export Progress", _exportProgress),
                            _actionTile("Import Progress", _importProgress),
                            _actionTile(
                              "Restore Pre-Import Backup",
                              _restoreImportBackup,
                            ),
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
                              onChanged: (_) => BackgroundMusicController
                                  .instance
                                  .syncWithSettings(),
                            ),
                          ],
                        ),
                        if (NotificationService.isSupported)
                          _buildSettingsTile(
                            context,
                            Icons.notifications_active_outlined,
                            "Notifications",
                            [
                              _SettingSwitchTile(
                                label: "Daily Reminders",
                                preferenceKey: AppSettingKeys.dailyReminders,
                                defaultValue: true,
                                onChanged: (_) => NotificationService.instance
                                    .syncDailyReminders(),
                              ),
                              const _SettingSwitchTile(
                                label: "Milestone Alerts",
                                preferenceKey: AppSettingKeys.milestoneAlerts,
                                defaultValue: true,
                              ),
                            ],
                          ),
                        // Playground can rename and delete challenges, so it's a
                        // developer tool: debug builds only, never in a release.
                        if (kDebugMode)
                          _buildSettingsTile(
                            context,
                            Icons.construction_outlined,
                            "Developer",
                            [
                              _actionTile(
                                "Playground (challenge editor)",
                                () => Navigator.push(
                                  context,
                                  appPageRoute(const PlaygroundScreen()),
                                ),
                              ),
                              _actionTile(
                                "Replay first-run intro",
                                () => Navigator.push(
                                  context,
                                  appPageRoute(
                                    IntroPage(
                                      onFinished: () => Navigator.pop(context),
                                    ),
                                  ),
                                ),
                              ),
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
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
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

  static Widget _actionTile(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.greenAccent),
          ],
        ),
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
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.all(25),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: FadingEdgeScrollView(
                            child: SingleChildScrollView(
                              child: Column(children: children),
                            ),
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
