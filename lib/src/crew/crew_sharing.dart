import 'package:flutter/material.dart';

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
  });
  final CrewSharingBackend backend;
  final String crewId;
  final AppShare share;
  final VoidCallback? onShared;
  @override
  State<CrewShareControls> createState() => _CrewShareControlsState();
}

class _CrewShareControlsState extends State<CrewShareControls> {
  CrewShareLink? _link;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final link = await widget.backend.manageShareLink(
        widget.crewId,
        'status',
      );
      if (mounted) setState(() => _link = link);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load invite link. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(BuildContext anchor) async {
    if (_busy) return;
    final origin = shareOrigin(anchor);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_link?.token == null || !_link!.expiresAt.isAfter(DateTime.now())) {
        _link = await widget.backend.manageShareLink(widget.crewId, 'create');
      }
      if (_link?.token == null) throw StateError('Missing invite');
      await widget.share.text(
        'Let’s make a little progress together. Join my crew on WeekPact: ${_link!.url}',
        origin,
      );
      if (mounted) widget.onShared?.call();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not share the link. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.backend.manageShareLink(widget.crewId, 'revoke');
      if (mounted) setState(() => _link = null);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not revoke the link. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Invite your people',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Share through Messages, WhatsApp, or any app you use together. Anyone with the link can join. It expires in 7 days; you can revoke it here.',
      ),
      if (_link != null && _link!.token == null)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Creating a new link replaces the previous one.'),
        ),
      const SizedBox(height: 12),
      Builder(
        builder: (anchor) => FilledButton.icon(
          onPressed: _busy ? null : () => _share(anchor),
          icon: const Icon(Icons.ios_share),
          label: Text(
            _busy
                ? 'Please wait…'
                : _link?.token != null
                ? 'Share invite link'
                : 'Create & share link',
          ),
        ),
      ),
      if (_link != null)
        TextButton(
          onPressed: _busy ? null : _revoke,
          child: const Text('Revoke invite link'),
        ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
