import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../invites/invite_links.dart';
import '../sharing/app_share.dart';
import '../theme/weekpact_theme.dart';

/// A crew's one way in: a six-character code that works until someone resets
/// it, and the link that carries it.
abstract interface class CrewSharingBackend {
  /// The crew's code, made the first time anyone asks. Any member may.
  Future<String> inviteCode(String crewId);

  /// A fresh code for the crew. The old one stops working at once. Owner only.
  Future<String> resetInviteCode(String crewId);
}

/// What goes out when someone shares a crew: the link, and the code for the
/// friend who installs the app first and loses the link on the way.
String inviteMessage(String crewName, String code, {String? from}) =>
    'Join $crewName on WeekPact, so we keep each other honest: '
    '${inviteUrl(code, from: from)}\n\n'
    'Already have the app? Enter the code $code.';

/// A code as six raised boxes, the way the invite page and the code screen
/// show it, so the three read as the same thing.
class InviteCodeBoxes extends StatelessWidget {
  const InviteCodeBoxes({super.key, required this.code, this.size = 40});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Invite code ${code.split('').join(' ')}',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, char) in code.split('').indexed) ...[
          if (index > 0) const SizedBox(width: 4),
          Container(
            width: size * .78,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: context.border),
            ),
            child: Text(
              char,
              style: TextStyle(
                color: WeekPactColors.black,
                fontSize: size * .48,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class CrewShareControls extends StatefulWidget {
  const CrewShareControls({
    super.key,
    required this.backend,
    required this.crewId,
    required this.crewName,
    this.inviterId,
    this.isOwner = false,
    this.share = const NativeAppShare(),
    this.onShared,
    this.showHeading = true,
  });
  final CrewSharingBackend backend;
  final String crewId;
  final String crewName;

  /// Who is sharing, so the invite can open with their name.
  final String? inviterId;

  /// Only the owner may reset the code.
  final bool isOwner;
  final AppShare share;
  final bool showHeading;
  final VoidCallback? onShared;
  @override
  State<CrewShareControls> createState() => _CrewShareControlsState();
}

class _CrewShareControlsState extends State<CrewShareControls> {
  String? _code;
  bool _showQr = false;
  bool _busy = false;
  bool _copied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final code = await widget.backend.inviteCode(widget.crewId);
      if (mounted) setState(() => _code = code);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load the invite code.');
      }
    }
  }

  Future<String?> _ensureCode() async {
    if (_code != null) return _code;
    await _load();
    return _code;
  }

  Uri _url(String code) => inviteUrl(code, from: widget.inviterId);

  Future<void> _share(BuildContext anchor, {bool copy = false}) async {
    if (_busy) return;
    final origin = copy ? null : shareOrigin(anchor);
    setState(() {
      _busy = true;
      _copied = false;
      _error = null;
    });
    try {
      final code = await _ensureCode();
      if (code == null) throw StateError('Missing invite');
      if (copy) {
        await Clipboard.setData(ClipboardData(text: _url(code).toString()));
        if (mounted) setState(() => _copied = true);
      } else {
        await widget.share.text(
          inviteMessage(widget.crewName, code, from: widget.inviterId),
          origin!,
        );
      }
      if (mounted) widget.onShared?.call();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = copy
              ? 'Could not copy the link. Please try again.'
              : 'Could not share the link. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _copied = false;
    });
    try {
      final code = await widget.backend.resetInviteCode(widget.crewId);
      if (mounted) setState(() => _code = code);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not reset the code. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading) ...[
          const Text(
            'Invite your people',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
        ],
        const Text(
          'Share the link, or read out the code. Both work until you reset them.',
        ),
        const SizedBox(height: 12),
        Center(
          child: code == null
              ? const SizedBox(height: 40)
              : InviteCodeBoxes(code: code),
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (anchor) => FilledButton.icon(
            onPressed: _busy ? null : () => _share(anchor),
            icon: const AppIcon(icon: HugeIconsStrokeRounded.share08),
            label: Text(_busy ? 'Please wait…' : 'Share invite link'),
          ),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (anchor) => OutlinedButton.icon(
            onPressed: _busy ? null : () => _share(anchor, copy: true),
            icon: const AppIcon(icon: HugeIconsStrokeRounded.copy01),
            label: Text(_copied ? 'Link copied' : 'Copy invite link'),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy || code == null
              ? null
              : () {
                  setState(() => _showQr = !_showQr);
                  // A QR on screen is a link going out, as much as a copy is.
                  if (_showQr) widget.onShared?.call();
                },
          icon: const AppIcon(icon: HugeIconsStrokeRounded.qrCode),
          label: Text(_showQr ? 'Hide QR code' : 'Show QR code'),
        ),
        if (widget.isOwner) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy || code == null ? null : _reset,
            child: const Text('Reset code (the old one stops working)'),
          ),
        ],
        if (_showQr && code != null) ...[
          const SizedBox(height: 20),
          const Text(
            'Scan to join your crew',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: AspectRatio(
                aspectRatio: 1,
                child: QrImageView(
                  data: _url(code).toString(),
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(24),
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                  semanticsLabel: 'Crew invitation QR code. Scan with another phone camera to join.',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Ask them to open their phone camera and scan this code.',
            textAlign: TextAlign.center,
          ),
        ],
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
