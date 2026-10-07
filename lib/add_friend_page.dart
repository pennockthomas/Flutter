import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'app_settings.dart';
import 'app_user.dart';
import 'fading_edge_scroll_view.dart';
import 'friends_models.dart';
import 'friends_service.dart';
import 'glass_panel.dart';

/// Add a friend: your own friend code to give away (copy or share), and a box
/// to type theirs. Opened from the Add button on the Friends screen.
class AddFriendPage extends StatefulWidget {
  const AddFriendPage({super.key, required this.service, required this.uid});

  final FriendsService service;
  final String uid;

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  final _codeField = TextEditingController();
  late Future<String> _myCode = _loadMyCode();

  bool _adding = false;
  String? _message;
  bool _messageIsGood = false;

  String get _myName => AppUser.hasName ? AppUser.name : 'EcoSteps friend';

  Future<String> _loadMyCode() => widget.service.myCode(widget.uid, _myName);

  @override
  void dispose() {
    _codeField.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    _say('Code copied.');
  }

  Future<void> _shareCode(String code) async {
    final screen = MediaQuery.sizeOf(context);
    try {
      await Share.share(
        'Add me on EcoSteps! My friend code is $code',
        sharePositionOrigin: Rect.fromLTWH(0, 0, screen.width, screen.height),
      );
    } catch (e) {
      _say("Couldn't open the share sheet.");
    }
  }

  Future<void> _addFriend() async {
    if (_adding) return;
    setState(() {
      _adding = true;
      _message = null;
    });
    String message;
    var good = false;
    try {
      final outcome = await widget.service.addByCode(
        myUid: widget.uid,
        myName: _myName,
        rawCode: _codeField.text,
      );
      switch (outcome) {
        case AddFriendOutcome.requestSent:
          message =
              'Request sent. They need to accept it before you can see '
              "each other's progress.";
          good = true;
        case AddFriendOutcome.nowFriends:
          message = "You're now friends!";
          good = true;
        case AddFriendOutcome.alreadyFriends:
          message = "You're already friends.";
        case AddFriendOutcome.alreadyRequested:
          message = 'You already sent them a request.';
        case AddFriendOutcome.notFound:
          message = 'No one has that code. Check it and try again.';
        case AddFriendOutcome.yourOwnCode:
          message = "That's your own code.";
        case AddFriendOutcome.invalidCode:
          message = 'A friend code has 6 letters and numbers.';
      }
      if (good) _codeField.clear();
    } catch (e) {
      message =
          "Couldn't reach the server. Check your connection and try again.";
    }
    if (!mounted) return;
    setState(() {
      _adding = false;
      _message = message;
      _messageIsGood = good;
    });
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
                  child: FadingEdgeScrollView(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
                      children: [
                        const GlassPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add a friend',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Swap friend codes. Once they accept your '
                                "request you can see each other's totals and "
                                'progress per area, never the names of the '
                                'swaps.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildMyCode(),
                        const SizedBox(height: 14),
                        _buildEnterCode(),
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

  Widget _buildMyCode() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your friend code',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Give this to a friend so they can send you a request.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 14),
          FutureBuilder<String>(
            future: _myCode,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Couldn't get your code.",
                        style: TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _myCode = _loadMyCode()),
                      child: const Text('Try again'),
                    ),
                  ],
                );
              }
              final code = snapshot.data;
              if (code == null) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      '${code.substring(0, 3)} ${code.substring(3)}',
                      key: const Key('friend-code'),
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy code',
                    onPressed: () => _copyCode(code),
                    icon: const Icon(Icons.copy_rounded, color: Colors.white70),
                  ),
                  IconButton(
                    tooltip: 'Share code',
                    onPressed: () => _shareCode(code),
                    icon: const Icon(Icons.ios_share, color: Colors.white70),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEnterCode() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter their code',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('friend-code-field'),
                  controller: _codeField,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    letterSpacing: 2,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Their friend code',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      letterSpacing: 0,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.greenAccent),
                    ),
                  ),
                  onSubmitted: (_) => _addFriend(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                key: const Key('send-request-button'),
                onPressed: _adding ? null : _addFriend,
                child: _adding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send'),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(
              _message!,
              key: const Key('add-friend-message'),
              style: TextStyle(
                color: _messageIsGood
                    ? Colors.greenAccent
                    : Colors.orangeAccent,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
