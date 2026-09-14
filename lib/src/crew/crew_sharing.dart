import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../sharing/app_share.dart';

class CrewShareLink {
  const CrewShareLink({required this.expiresAt, this.token});
  final DateTime expiresAt;
  final String? token;
  Uri get url => Uri.parse(
    const String.fromEnvironment(
      'APP_SITE_URL',
      defaultValue: 'https://weekpact.codepeaktrail.dev',
    ),
  ).resolve('/invite/').replace(queryParameters: {'invite': token!});
  factory CrewShareLink.fromJson(Map<String, dynamic> row) => CrewShareLink(
    expiresAt: DateTime.parse(row['expires_at'] as String),
    token: row['token'] as String?,
  );
}

abstract interface class CrewSharingBackend {
  Future<CrewShareLink?> manageShareLink(String crewId, String action);
}

class CrewShareControls extends StatefulWidget {
  const CrewShareControls({
    super.key,
    required this.backend,
    required this.crewId,
    this.share = const NativeAppShare(),
    this.onShared,
    this.showHeading = true,
  });
  final CrewSharingBackend backend;
  final String crewId;
  final AppShare share;
  final bool showHeading;
  final VoidCallback? onShared;
  @override
  State<CrewShareControls> createState() => _CrewShareControlsState();
}

class _CrewShareControlsState extends State<CrewShareControls> {
  CrewShareLink? _qrLink;
  bool _busy = false;
  bool _copied = false;
  String? _error;

  Future<void> _share(BuildContext anchor, {bool copy = false}) async {
    if (_busy) return;
    final origin = copy ? null : shareOrigin(anchor);
    setState(() {
      _busy = true;
      _copied = false;
      _error = null;
    });
    try {
      final link = await widget.backend.manageShareLink(
        widget.crewId,
        'create',
      );
      if (link?.token == null) throw StateError('Missing invite');
      if (copy) {
        await Clipboard.setData(ClipboardData(text: link!.url.toString()));
        if (mounted) setState(() => _copied = true);
      } else {
        await widget.share.text(
          'Let’s make a little progress together. Join my crew on WeekPact: ${link!.url}',
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

  Future<void> _toggleQr() async {
    if (_busy) return;
    if (_qrLink != null) {
      setState(() => _qrLink = null);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await widget.backend.manageShareLink(
        widget.crewId,
        'create',
      );
      if (link?.token == null) throw StateError('Missing invite');
      if (mounted) setState(() => _qrLink = link);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not create the QR code. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.showHeading) ...[
        const Text(
          'Invite your people',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
      ],
      const Text('Invite links are active for 7 days.'),
      const SizedBox(height: 12),
      Builder(
        builder: (anchor) => FilledButton.icon(
          onPressed: _busy ? null : () => _share(anchor),
          icon: const Icon(Icons.ios_share),
          label: Text(_busy ? 'Please wait…' : 'Share invite link'),
        ),
      ),
      const SizedBox(height: 8),
      Builder(
        builder: (anchor) => OutlinedButton.icon(
          onPressed: _busy ? null : () => _share(anchor, copy: true),
          icon: const Icon(Icons.copy_outlined),
          label: Text(_copied ? 'Link copied' : 'Copy invite link'),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : _toggleQr,
        icon: const Icon(Icons.qr_code_2),
        label: Text(_qrLink == null ? 'Show QR code' : 'Hide QR code'),
      ),
      if (_qrLink != null) ...[
        const SizedBox(height: 20),
        const Text(
          'Scan to join your crew',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: AspectRatio(
              aspectRatio: 1,
              child: QrImageView(
                data: _qrLink!.url.toString(),
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
