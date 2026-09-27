import 'package:flutter/material.dart';

import 'app_page_route.dart';
import 'app_user.dart';
import 'challenge_store.dart';
import 'profile_page.dart';

/// The small initials avatar with an overall-progress ring that sits in the
/// top-right corner of each main tab and opens the Profile page.
class ProfileAvatarButton extends StatefulWidget {
  final double size;

  const ProfileAvatarButton({super.key, this.size = 44});

  @override
  State<ProfileAvatarButton> createState() => _ProfileAvatarButtonState();
}

class _ProfileAvatarButtonState extends State<ProfileAvatarButton> {
  @override
  void initState() {
    super.initState();
    ChallengeStore.instance.addListener(_onChallengesChanged);
    ChallengeStore.instance.ensureLoaded().then((_) => _onChallengesChanged());
  }

  @override
  void dispose() {
    ChallengeStore.instance.removeListener(_onChallengesChanged);
    super.dispose();
  }

  void _onChallengesChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Semantics(
      button: true,
      label: 'Profile',
      child: GestureDetector(
        onTap: () => Navigator.push(context, appPageRoute(const ProfilePage())),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: ChallengeStore.instance.progress,
                  strokeWidth: 3,
                  backgroundColor: Colors.white12,
                  color: Colors.greenAccent,
                ),
              ),
              Container(
                width: size - 9,
                height: size - 9,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: Center(
                  child: Text(
                    AppUser.initials,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
