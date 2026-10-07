import 'package:flutter/material.dart';

import 'app_page_route.dart';
import 'houses_controller.dart';
import 'houses_service.dart';
import 'sign_in_page.dart';

/// The pill at the top of the tree screen that says what you're looking at:
/// "Personal" (your tree) or one of your houses. Tapping it opens the list of
/// houses, your invitations, and "New house".
class ScopeDropdown extends StatelessWidget {
  const ScopeDropdown({super.key, required this.controller});

  final HousesController controller;

  static const _personal = 'personal';
  static const _newHouse = 'new';
  static const _invitations = 'invitations';
  static const _signIn = 'signin';
  static const _housePrefix = 'house:';

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onSelected(BuildContext context, String value) async {
    try {
      if (value == _personal) {
        await controller.select(null);
      } else if (value.startsWith(_housePrefix)) {
        await controller.select(value.substring(_housePrefix.length));
      } else if (value == _newHouse) {
        await controller.createAndSelect();
      } else if (value == _invitations) {
        await _showInvitations(context);
      } else if (value == _signIn) {
        await Navigator.push(context, appPageRoute(const SignInPage()));
      }
    } catch (e) {
      if (context.mounted) _say(context, describeHouseError(e));
    }
  }

  Future<void> _showInvitations(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101510),
      builder: (sheetContext) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final invites = controller.invites;
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              children: [
                const Text(
                  'Invitations',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (invites.isEmpty)
                  const Text(
                    'No invitations right now.',
                    style: TextStyle(color: Colors.white70),
                  ),
                for (final invite in invites)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${invite.fromName} invited you to '
                            '${invite.houseName}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        TextButton(
                          key: Key('decline-${invite.houseId}'),
                          onPressed: () =>
                              _run(context, () => controller.decline(invite)),
                          child: const Text('Decline'),
                        ),
                        FilledButton(
                          key: Key('join-${invite.houseId}'),
                          onPressed: () async {
                            final ok = await _run(
                              context,
                              () => controller.accept(invite),
                            );
                            if (ok && sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                          child: const Text('Join'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<bool> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } catch (e) {
      if (context.mounted) _say(context, describeHouseError(e));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selected = controller.selectedHouse;
        final invites = controller.invites.length;
        return PopupMenuButton<String>(
          key: const Key('scope-dropdown'),
          tooltip: 'Switch between Personal and your houses',
          color: const Color(0xFF101510),
          offset: const Offset(0, 48),
          onSelected: (value) => _onSelected(context, value),
          itemBuilder: (context) => [
            _item(
              _personal,
              'Personal',
              Icons.person_rounded,
              selected == null,
            ),
            if (controller.isSignedIn) ...[
              for (final house in controller.houses)
                _item(
                  '$_housePrefix${house.id}',
                  house.name,
                  Icons.home_rounded,
                  selected?.id == house.id,
                ),
              const PopupMenuDivider(),
              if (invites > 0)
                _item(
                  _invitations,
                  invites == 1 ? '1 invitation' : '$invites invitations',
                  Icons.mail_outline_rounded,
                  false,
                ),
              _item(_newHouse, 'New house', Icons.add_rounded, false),
            ] else ...[
              const PopupMenuDivider(),
              _item(
                _signIn,
                'Sign in to use houses',
                Icons.login_rounded,
                false,
              ),
            ],
          ],
          child: Container(
            // Exactly as tall as the profile button beside it (44).
            constraints: const BoxConstraints(
              maxWidth: 220,
              minHeight: 44,
              maxHeight: 44,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected == null ? Icons.person_rounded : Icons.home_rounded,
                  color: Colors.greenAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    selected?.name ?? 'Personal',
                    key: const Key('scope-label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: Colors.white70),
                if (invites > 0)
                  Container(
                    key: const Key('invite-badge'),
                    margin: const EdgeInsets.only(left: 4),
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: Colors.orangeAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _item(
    String value,
    String label,
    IconData icon,
    bool selected,
  ) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            color: selected ? Colors.greenAccent : Colors.white70,
            size: 20,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.greenAccent : Colors.white,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check, color: Colors.greenAccent, size: 18),
          ],
        ],
      ),
    );
  }
}
