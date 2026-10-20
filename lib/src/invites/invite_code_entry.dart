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
    this.showButton = true,
  });

  final ValueChanged<InviteRef> onInvite;
  final String buttonLabel;

  /// Off for a screen that pins its own button to the foot and calls
  /// [InviteCodeEntryState.submit] from it.
  final bool showButton;

  @override
  State<InviteCodeEntry> createState() => InviteCodeEntryState();
}

class InviteCodeEntryState extends State<InviteCodeEntry> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void submit() {
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

  void _onChanged(String text) {
    // A whole link pasted in: a code-and-sender link goes straight through,
    // as does a legacy token that could never fit the boxes.
    if (text.length > inviteCodeLength) {
      final invite = inviteFromText(text);
      if (invite != null) {
        if (invite.code.length == inviteCodeLength) {
          _controller.value = TextEditingValue(
            text: invite.code,
            selection: const TextSelection.collapsed(offset: inviteCodeLength),
          );
        }
        FocusScope.of(context).unfocus();
        widget.onInvite(invite);
        return;
      }
    }
    final cleaned = text
        .toUpperCase()
        .split('')
        .where(inviteCodeAlphabet.contains)
        .take(inviteCodeLength)
        .join();
    if (cleaned != text) {
      _controller.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    setState(() => _error = null);
  }

  /// One box per character; the real field sits invisibly on top so typing,
  /// pasting and the keyboard all behave like any other text field.
  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 64,
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < inviteCodeLength; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _CodeCell(
                        char: i < text.length ? text[i] : null,
                        active:
                            _focus.hasFocus &&
                            (i == text.length ||
                                (i == inviteCodeLength - 1 &&
                                    text.length == inviteCodeLength)),
                      ),
                    ),
                  ],
                ],
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    key: const ValueKey('invite-code-field'),
                    controller: _controller,
                    focusNode: _focus,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.go,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    ],
                    onChanged: _onChanged,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.errorInk,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
        if (widget.showButton) ...[
          const SizedBox(height: 24),
          AppButton(
            label: widget.buttonLabel,
            color: WeekPactColors.mintGreen,
            height: 56,
            onPressed: submit,
          ),
        ],
      ],
    );
  }
}

class _CodeCell extends StatelessWidget {
  const _CodeCell({required this.char, required this.active});

  final String? char;
  final bool active;

  @override
  Widget build(BuildContext context) => AppSurface(
    raised: false,
    borderRadius: WeekPactMetrics.controlRadius,
    borderWidth: active ? 2.5 : WeekPactMetrics.border,
    builder: (context) => Center(
      child: Text(
        char ?? '',
        style: TextStyle(
          color: context.fieldInk,
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
