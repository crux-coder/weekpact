import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'invite_links.dart';

/// A typed invite code, or a pasted invite link, turned into an [InviteRef].
///
/// A link tapped on the phone arrives through the deep-link route on its own;
/// this is for the code a friend read out, or the link somebody copied before
/// installing the app and then lost.
class InviteCodeEntry extends StatefulWidget {
  const InviteCodeEntry({
    super.key,
    required this.onInvite,
    this.buttonLabel = 'FIND MY CREW',
    this.showTip = false,
  });

  final ValueChanged<InviteRef> onInvite;
  final String buttonLabel;

  /// The "just installed? tap the link again" note, for the front door.
  final bool showTip;

  @override
  State<InviteCodeEntry> createState() => _InviteCodeEntryState();
}

class _InviteCodeEntryState extends State<InviteCodeEntry> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final invite = inviteFromText(_controller.text);
    if (invite == null) {
      setState(
        () => _error =
            'Codes are 6 letters and numbers, like 7K2QXM. A whole invite '
            'link works too.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    widget.onInvite(invite);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    final invite = inviteFromText(text);
    setState(() {
      _controller.text = invite != null && invite.code.length == 6
          ? invite.code
          : text;
      _error = null;
    });
    if (invite != null) widget.onInvite(invite);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppSurface(
        raised: false,
        borderRadius: WeekPactMetrics.controlRadius,
        builder: (context) => TextField(
          key: const ValueKey('invite-code-field'),
          controller: _controller,
          autofocus: false,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.go,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
          style: TextStyle(
            color: context.fieldInk,
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            hintText: '7K2QXM',
            hintStyle: TextStyle(
              color: context.muted.withValues(alpha: .45),
              fontWeight: FontWeight.w600,
              letterSpacing: 8,
            ),
            filled: false,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          style: TextStyle(
            color: context.errorInk,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _paste,
          style: TextButton.styleFrom(foregroundColor: context.muted),
          child: const Text('Paste a code or link'),
        ),
      ),
      if (widget.showTip) ...[
        const SizedBox(height: 4),
        Text(
          'Just installed? Go back to the message and tap the invite link '
          'again. Now that WeekPact is on your phone, it opens straight to the '
          'crew.',
          style: TextStyle(color: context.muted, fontSize: 14, height: 1.4),
        ),
      ],
      const SizedBox(height: 16),
      AppButton(
        label: widget.buttonLabel,
        color: WeekPactColors.mintGreen,
        height: 56,
        onPressed: _submit,
      ),
    ],
  );
}
