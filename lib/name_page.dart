import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'app_user.dart';
import 'glass_panel.dart';

/// Asks for the user's name: once on first launch (and once for installs
/// from before names existed). [onFinished] runs after the name is saved.
/// Friends will see this name, which is why it's asked for up front.
class NamePage extends StatefulWidget {
  final VoidCallback onFinished;

  const NamePage({super.key, required this.onFinished});

  @override
  State<NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<NamePage> {
  final _controller = TextEditingController();
  bool _saving = false;

  bool get _isValid => AppUser.cleanName(_controller.text) != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_isValid || _saving) return;
    _saving = true;
    final saved = await AppUser.setName(_controller.text);
    if (!mounted) return;
    if (saved) {
      widget.onFinished();
    } else {
      _saving = false;
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
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GlassPanel(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
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
                        child: const Icon(
                          Icons.person_rounded,
                          size: 48,
                          color: Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'What should we call you?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'This is the name your friends will see. You can '
                        'change it any time in your profile.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        maxLength: AppUser.maxNameLength,
                        style: const TextStyle(color: Colors.white),
                        decoration: _nameDecoration('Your name'),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _continue(),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _isValid ? _continue : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          disabledBackgroundColor: Colors.white24,
                          minimumSize: const Size.fromHeight(52),
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Continue'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _nameDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white70),
    counterStyle: const TextStyle(color: Colors.white54),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.white24),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.greenAccent),
    ),
  );
}

/// Lets the user change their name (from the Profile). Returns after the
/// dialog closes; the new name shows everywhere through [AppUser.listenable].
Future<void> showEditNameDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _EditNameDialog(),
  );
}

class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog();

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  // Owned by the dialog's state, so it's only disposed once the dialog has
  // finished animating away.
  final _controller = TextEditingController(text: AppUser.name);

  bool get _isValid => AppUser.cleanName(_controller.text) != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_isValid) return;
    await AppUser.setName(_controller.text);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF101510),
      title: const Text('Your name', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        maxLength: AppUser.maxNameLength,
        style: const TextStyle(color: Colors.white),
        decoration: _nameDecoration('Name'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isValid ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
