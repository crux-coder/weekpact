import '../home/photo_check_in_sheet.dart';

import 'package:flutter/material.dart';

import '../crew/crew_backend.dart';
import '../crew/crew_sharing.dart';
import '../home/home_backend.dart';
import '../pacts/pacts_backend.dart';
import '../pacts/pacts_page.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';

/// Resumes from saved crew/pact/check-in data, so backing out or retrying never
/// creates another crew or asks members to repeat completed steps.
class CrewSetupPage extends StatefulWidget {
  const CrewSetupPage({
    super.key,
    required this.crewBackend,
    required this.pactsBackend,
    required this.homeBackend,
    required this.userId,
    this.initialCrew,
    this.crewId,
    this.captureCheckInPhoto,
  });
  final CrewBackend crewBackend;
  final PactsBackend pactsBackend;
  final HomeBackend homeBackend;
  final String userId;
  final CrewDetails? initialCrew;
  final String? crewId;
  final CheckInPhotoCapture? captureCheckInPhoto;
  @override
  State<CrewSetupPage> createState() => _CrewSetupPageState();
}

class _CrewSetupPageState extends State<CrewSetupPage> {
  final _name = TextEditingController();
  CrewDetails? _crew;
  CrewPact? _pact;
  int _step = 0;
  bool _busy = true;
  String? _error;
  static const _titles = [
    'Your people. Your crew.',
    'Make your first pact.',
    'Better with company.',
    'Your first small step.',
  ];
  @override
  void initState() {
    super.initState();
    _resume();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    try {
      final crew =
          widget.initialCrew ??
          await widget.crewBackend.fetchCrew(crewId: widget.crewId);
      final pacts = crew == null
          ? <CrewPact>[]
          : await widget.pactsBackend.fetchPacts(crew.id);
      if (!mounted) return;
      setState(() {
        _crew = crew;
        _pact = pacts.firstOrNull;
        _step = crew == null
            ? 0
            : pacts.isEmpty
            ? 1
            : crew.members.length > 1
            ? 3
            : 2;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load setup. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    if (_name.text.trim().length < 2 || _name.text.trim().length > 60) {
      setState(() => _error = 'Give your crew a name with 2–60 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final crew = await widget.crewBackend.createCrew(
        name: _name.text.trim(),
        timezone: const String.fromEnvironment(
          'APP_TIMEZONE',
          defaultValue: 'UTC',
        ),
      );
      if (mounted) {
        setState(() {
          _crew = crew;
          _step = 1;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not create your crew. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePact() async {
    final crew = _crew!;
    final pact = await showAppSheet<CrewPact>(
      context: context,
      builder: (_) => PactEditor(
        crew: PactCrew(
          id: crew.id,
          name: crew.name,
          timezone: crew.timezone,
          isOwner: crew.isOwner,
        ),
        backend: widget.pactsBackend,
      ),
    );
    if (mounted && pact != null) {
      setState(() {
        _pact = pact;
        _step = 2;
      });
    }
  }

  Future<void> _checkIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final week = await widget.homeBackend.fetchWeek(_crew!.id);
      if (_pact == null || !week.pacts.any((p) => p.id == _pact!.id)) {
        throw StateError('Pact changed');
      }
      final checked = week.checkedToday(widget.userId);
      if (!checked.contains(_pact!.id)) {
        checked.add(_pact!.id);
        if (!mounted) return;
        final saved = await showPhotoCheckIn(
          userId: widget.userId,
          context: context,
          backend: widget.homeBackend,
          crewId: _crew!.id,
          pactId: _pact!.id,
          pactTitle: _pact!.title,
          today: week.today,
          selectedPactIds: checked,
          capturePhoto: widget.captureCheckInPhoto,
        );
        if (!saved) return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('First step, done. Here’s to a good week!'),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not check in. Please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Start your crew')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 4; i++)
                        Expanded(
                          child: Container(
                            height: 5,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: i <= _step
                                  ? WeekPactColors.mintGreen
                                  : context.muted.withValues(alpha: .25),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Step ${_step + 1} of 4',
                    style: TextStyle(color: context.muted),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _titles[_step],
                    style: TextStyle(
                      color: context.ink,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppSurface(
                    fillColor: WeekPactColors.mintGreen,
                    builder: (context) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_step == 0) ...[
                            const Text(
                              'A few friends. One little commitment. Give your crew a name to get started.',
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _name,
                              maxLength: 60,
                              decoration: const InputDecoration(
                                labelText: 'Crew name',
                                hintText: 'Early Birds',
                              ),
                              onSubmitted: (_) => _create(),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _busy ? null : _create,
                              child: const Text('Create crew'),
                            ),
                          ],
                          if (_step == 1) ...[
                            Text(
                              _crew!.isOwner
                                  ? 'Pick something small enough to repeat. Start with a suggestion, then edit the name and weekly target.'
                                  : 'Your crew owner sets the pacts. Ask them to add the first one, then return here.',
                            ),
                            const SizedBox(height: 20),
                            if (_crew!.isOwner)
                              FilledButton(
                                onPressed: _busy ? null : _choosePact,
                                child: const Text('Choose a starter pact'),
                              ),
                          ],
                          if (_step == 2) ...[
                            if (widget.crewBackend is CrewSharingBackend &&
                                _crew!.isOwner)
                              CrewShareControls(
                                backend:
                                    widget.crewBackend as CrewSharingBackend,
                                crewId: _crew!.id,
                              )
                            else
                              const Text(
                                'Invite friends from the Crews tab. You can also start with a check-in now.',
                              ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _step = 3),
                              child: const Text('Continue to first check-in'),
                            ),
                          ],
                          if (_step == 3) ...[
                            Text(
                              _pact?.title ?? 'Your first pact',
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Already done it today? Mark your first check-in. If not, come back when you’re ready.',
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _busy ? null : _checkIn,
                              child: Text(_busy ? 'Saving…' : 'I did it today'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: context.errorInk)),
                    if (_crew == null)
                      TextButton(
                        onPressed: _busy ? null : _resume,
                        child: const Text('Reload setup'),
                      ),
                  ],
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: Text(
                      _step == 3 ? 'I’ll check in later' : 'Finish later',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
