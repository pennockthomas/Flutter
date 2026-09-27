import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'app_settings.dart';
import 'auth_service.dart';
import 'glass_panel.dart';

/// Sign-in / create-account screen. Purely additive: closing this without
/// signing in leaves the app exactly as usable as before (local-only).
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isRegistering = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailForm() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await AuthService.instance.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        isRegistering: _isRegistering,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = AuthService.instance.messageFor(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitAppleSignIn() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await AuthService.instance.signInWithApple();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = AuthService.instance.messageFor(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
          const AppBackgroundOverlay(fallbackDarkness: 0.42),
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
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GlassPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isRegistering ? 'Create Account' : 'Sign In',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Sync your progress and add friends. EcoSteps still works fully without an account.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GlassPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SignInWithAppleButton(
                                onPressed: _isSubmitting
                                    ? () {}
                                    : _submitAppleSignIn,
                                style: SignInWithAppleButtonStyle.white,
                                borderRadius: BorderRadius.circular(14),
                                height: 48,
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(color: Colors.white24),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Text(
                                      'or',
                                      style: TextStyle(
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(color: Colors.white24),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    TextFormField(
                                      controller: _emailController,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      keyboardType:
                                          TextInputType.emailAddress,
                                      autocorrect: false,
                                      decoration: _fieldDecoration('Email'),
                                      validator: (value) {
                                        if (value == null ||
                                            !value.contains('@')) {
                                          return 'Enter a valid email';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _passwordController,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      obscureText: true,
                                      decoration: _fieldDecoration(
                                        'Password',
                                      ),
                                      validator: (value) {
                                        if (value == null ||
                                            value.length < 6) {
                                          return 'At least 6 characters';
                                        }
                                        return null;
                                      },
                                    ),
                                    if (_errorMessage != null) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        _errorMessage!,
                                        style: const TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 18),
                                    FilledButton(
                                      onPressed: _isSubmitting
                                          ? null
                                          : _submitEmailForm,
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size.fromHeight(
                                          48,
                                        ),
                                      ),
                                      child: _isSubmitting
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child:
                                                  CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                            )
                                          : Text(
                                              _isRegistering
                                                  ? 'Create Account'
                                                  : 'Sign In',
                                            ),
                                    ),
                                    const SizedBox(height: 10),
                                    TextButton(
                                      onPressed: _isSubmitting
                                          ? null
                                          : () => setState(() {
                                              _isRegistering =
                                                  !_isRegistering;
                                              _errorMessage = null;
                                            }),
                                      child: Text(
                                        _isRegistering
                                            ? 'Already have an account? Sign in'
                                            : 'New here? Create an account',
                                        style: const TextStyle(
                                          color: Colors.greenAccent,
                                        ),
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.greenAccent),
      ),
    );
  }
}
