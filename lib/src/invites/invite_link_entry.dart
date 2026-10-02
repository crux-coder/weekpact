import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'invite_links.dart';

/// A pasted invite link, turned into its token.
///
/// A link tapped on the phone arrives through the deep-link route on its own;
/// this is for the person who was sent one in a chat on another device, or
/// who typed it from a friend's screen. It accepts the full link, the link
/// with the scheme dropped, or the bare token, and answers with the token.
class InviteLinkEntry extends StatefulWidget {
  const InviteLinkEntry({
    super.key,
    required this.onToken,
    this.buttonLabel = 'CONTINUE',
  });

  final ValueChanged<String> onToken;
  final String buttonLabel;

  @override
  State<InviteLinkEntry> createState() => _InviteLinkEntryState();
}

class _InviteLinkEntryState extends State<InviteLinkEntry> {
  final _form = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    widget.onToken(inviteTokenFromText(_controller.text)!);
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'INVITE LINK',
          hint: 'Paste the link your friend sent',
          controller: _controller,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          validator: (value) => inviteTokenFromText(value ?? '') == null
              ? 'That doesn’t look like a WeekPact invite link.'
              : null,
        ),
        const SizedBox(height: 10),
        Text(
          'Tapping the link on this phone, or pointing its camera at a '
          'friend’s QR code, brings you here on its own.',
          style: TextStyle(color: context.muted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: widget.buttonLabel,
          icon: HugeIconsStrokeRounded.arrowRight01,
          onPressed: _submit,
        ),
      ],
    ),
  );
}

/// The token inside whatever was pasted: a full invite link, one missing its
/// scheme, or the token on its own. Null for anything that is none of those.
String? inviteTokenFromText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final fromUri = inviteTokenFromUri(Uri.tryParse(trimmed));
  if (fromUri != null) return fromUri;
  if (!trimmed.contains('://')) {
    final withScheme = inviteTokenFromUri(Uri.tryParse('https://$trimmed'));
    if (withScheme != null) return withScheme;
  }
  // A bare token: one run of URL-safe characters, long enough not to be a
  // word somebody typed into the wrong box.
  final bare = RegExp(r'^[A-Za-z0-9_-]{16,}$');
  return bare.hasMatch(trimmed) ? trimmed : null;
}
