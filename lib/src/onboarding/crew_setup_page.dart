import '../home/photo_check_in_page.dart';

import 'package:flutter/material.dart';

import '../crew/crew_backend.dart';
import '../crew/device_timezone.dart';
import '../subscriptions/pro_upgrade.dart';
import '../crew/crew_sharing.dart';
import '../home/home_backend.dart';
import '../notifications/notification_primer_page.dart';
import '../pacts/pacts_backend.dart';
import '../pacts/pacts_page.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_frame.dart';

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
    this.solo = false,
  });
  final CrewBackend crewBackend;
  final PactsBackend pactsBackend;
  final HomeBackend homeBackend;
  final String userId;
  final CrewDetails? initialCrew;
  final String? crewId;
  final CheckInPhotoCapture? captureCheckInPhoto;

  /// A crew of one, for now. The invitation step is left out: there is
  /// nobody to send it to yet, and the Crews tab offers it whenever that
  /// changes. Three steps instead of four, and the copy says so.
  final bool solo;
  @override
  State<CrewSetupPage> createState() => _CrewSetupPageState();
}

class _CrewSetupPageState extends State<CrewSetupPage> {
  final _name = TextEditingController();
  CrewDetails? _crew;
  CrewPact? _pact;
  int _step = 0;

  /// Two waits, not one. [_loading] is the page finding out where the person
  /// got to last time, which they are free to walk away from; [_busy] is a
  /// write in flight, which they are not. Back was blocked by both while the
  /// page had a single flag, so the first thing the screen did on opening was
  /// refuse to close.
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// Whether an invitation left this phone during the invite step. Only then
  /// is there anyone to hear from, so only then is the notification ask made.
  bool _shared = false;
  static const _titles = [
    'Your people. Your crew.',
    'Make your first pact.',
    'Better with company.',
    'Your first small step.',
  ];
  static const _soloTitles = [
    'Just you, for now.',
    'Make your first pact.',
    'Better with company.',
    'Your first small step.',
  ];

  /// The step after the pact: the invitation, unless there is nobody to
  /// invite yet.
  int get _afterPact => widget.solo ? 3 : 2;
  int get _stepCount => widget.solo ? 3 : 4;

  /// Which of the visible steps [_step] is. Solo skips the invitation, so its
  /// last step is the third bar, not the fourth.
  int get _visibleStep => widget.solo && _step == 3 ? 2 : _step;
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
    // Already true on the first run, straight from the field initialiser, so
    // the very first load needs no rebuild to announce itself.
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
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
            : _afterPact;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load setup. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
        timezone: await deviceTimezone(),
      );
      if (mounted) {
        setState(() {
          _crew = crew;
          _step = 1;
        });
      }
    } catch (error) {
      if (!mounted) return;
      // Reachable only for someone who already has a crew on another device.
      setState(
        () => _error = isCrewLimitError(error)
            ? 'You’re already in a crew. WeekPact Pro is needed for more than one.'
            : 'Could not create your crew. Please retry.',
      );
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
        _step = _afterPact;
      });
    }
  }

  /// On from the invitation. Somebody whose link is out is asked, once, to
  /// hear it land; somebody who sent nothing has nobody to hear from yet.
  Future<void> _afterInvite() async {
    if (_shared) {
      await NotificationPrimerPage.show(
        context,
        crewName: _crew!.name,
        reason: NotificationPrimerReason.invited,
      );
    }
    if (mounted) setState(() => _step = 3);
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
        if (!_pact!.photoRequired) {
          await widget.homeBackend.saveCheckIns(
            crewId: _crew!.id,
            today: week.today,
            pactIds: checked,
          );
        } else {
          final saved = await showPhotoCheckIn(
            userId: widget.userId,
            context: context,
            backend: widget.homeBackend,
            crewId: _crew!.id,
            pactId: _pact!.id,
            pactTitle: _pact!.title,
            daysKept: week.days(_pact!.id, widget.userId),
            daysPerWeek: _pact!.daysPerWeek,
            today: week.today,
            selectedPactIds: checked,
            capturePhoto: widget.captureCheckInPhoto,
          );
          if (!saved) return;
        }
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
      appBar: AppBar(
        title: Text(widget.solo ? 'Start solo' : 'Start your crew'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _loading
                  ? _loadingPlaceholder(context)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            for (var i = 0; i < _stepCount; i++)
                              Expanded(
                                child: Container(
                                  height: 5,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: i <= _visibleStep
                                        ? WeekPactColors.mintGreen
                                        : context.muted.withValues(alpha: .25),
                                    borderRadius: WeekPactMetrics.pill,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Step ${_visibleStep + 1} of $_stepCount',
                          style: TextStyle(color: context.muted),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          (widget.solo ? _soloTitles : _titles)[_step],
                          style: TextStyle(
                            color: context.ink,
                            fontSize: 36,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        AppSurface(
                          fillColor: WeekPactColors.stone,
                          builder: (context) => Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_step == 0) ...[
                                  Text(
                                    widget.solo
                                        ? 'A crew of one still needs a name. Friends who join later will see it.'
                                        : 'A few friends. One little commitment. Give your crew a name to get started.',
                                  ),
                                  const SizedBox(height: 20),
                                  TextField(
                                    controller: _name,
                                    maxLength: 60,
                                    decoration: InputDecoration(
                                      labelText: 'Crew name',
                                      hintText: widget.solo
                                          ? 'My week'
                                          : 'Early Birds',
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
                                      child: const Text(
                                        'Choose a starter pact',
                                      ),
                                    ),
                                ],
                                if (_step == 2) ...[
                                  if (widget.crewBackend
                                          is CrewSharingBackend &&
                                      _crew!.isOwner)
                                    CrewShareControls(
                                      backend:
                                          widget.crewBackend
                                              as CrewSharingBackend,
                                      crewId: _crew!.id,
                                      onShared: () => _shared = true,
                                    )
                                  else
                                    const Text(
                                      'Invite friends from the Crews tab. You can also start with a check-in now.',
                                    ),
                                  const SizedBox(height: 20),
                                  FilledButton(
                                    onPressed: _busy ? null : _afterInvite,
                                    child: const Text(
                                      'Continue to first check-in',
                                    ),
                                  ),
                                ],
                                if (_step == 3) ...[
                                  Text(
                                    _pact?.title ?? 'Your first pact',
                                    style: const TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Already done it today? Mark your first check-in. If not, come back when you’re ready.',
                                  ),
                                  const SizedBox(height: 20),
                                  FilledButton(
                                    onPressed: _busy ? null : _checkIn,
                                    child: Text(
                                      _busy ? 'Saving…' : 'I did it today',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: TextStyle(color: context.errorInk),
                          ),
                          if (_crew == null)
                            TextButton(
                              onPressed: _busy ? null : _resume,
                              child: const Text('Reload setup'),
                            ),
                        ],
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
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

  /// The same shape the loaded page takes, with its lines not yet filled in,
  /// so nothing jumps when the saved setup arrives. Leaving is still offered:
  /// this wait belongs to the page, not to the person.
  Widget _loadingPlaceholder(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SkeletonBar(height: 5),
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      const Align(
        alignment: Alignment.centerLeft,
        child: SkeletonBar(width: 90, height: 14),
      ),
      const SizedBox(height: 20),
      const SkeletonBar(height: 34),
      const SizedBox(height: 12),
      const Align(
        alignment: Alignment.centerLeft,
        child: SkeletonBar(width: 200, height: 34),
      ),
      const SizedBox(height: 24),
      AppSurface(
        fillColor: WeekPactColors.stone,
        builder: (context) => const Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SkeletonBar(height: 14),
              SizedBox(height: 10),
              SkeletonBar(height: 14),
              SizedBox(height: 24),
              SkeletonBar(height: 48, radius: WeekPactMetrics.controlRadius),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Finish later'),
      ),
    ],
  );
}
