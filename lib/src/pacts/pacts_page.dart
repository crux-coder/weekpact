import '../home/home_backend.dart';
import '../crew/crew_page_layout.dart';
import '../crew/crew_switcher.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_sheet.dart';
import '../widgets/app_components.dart';
import '../widgets/page_frame.dart';
import 'pacts_backend.dart';
import 'pacts_overview.dart';
import 'pact_editor.dart';

class PactsPage extends StatefulWidget {
  const PactsPage({
    super.key,
    required this.backend,
    required this.loadWeek,
    required this.userId,
    required this.onOpenCrews,
    this.active = true,
    this.selectedCrewId,
    this.onCrewSelected,
  });
  final String? selectedCrewId;
  final ValueChanged<String>? onCrewSelected;
  final bool active;
  final PactsBackend backend;
  final Future<CrewWeek> Function(String crewId) loadWeek;
  final String userId;
  final VoidCallback onOpenCrews;

  @override
  State<PactsPage> createState() => _PactsPageState();
}

class _PactsPageState extends State<PactsPage> with WidgetsBindingObserver {
  CrewWeek? _week;
  List<PactCrew>? _crews;
  PactCrew? _selected;
  List<CrewPact>? _pacts;
  String? _error;
  int _request = 0;
  bool _loading = false;
  bool _hasLoaded = false;
  String? _deleting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) _refresh();
  }

  @override
  void didUpdateWidget(covariant PactsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        (!oldWidget.active ||
            widget.userId != oldWidget.userId ||
            widget.selectedCrewId != oldWidget.selectedCrewId)) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final crews = await widget.backend.fetchCrews();
      if (!mounted || request != _request) return;
      final matches = crews.where(
        (crew) => crew.id == (widget.selectedCrewId ?? _selected?.id),
      );
      final selected = matches.isNotEmpty
          ? matches.first
          : (crews.isEmpty ? null : crews.first);
      setState(() {
        if (_selected?.id != selected?.id) _pacts = null;
        _crews = crews;
        _selected = selected;
      });
      if (selected != null) {
        final week = await widget.loadWeek(selected.id);
        if (mounted && request == _request) {
          setState(() {
            _week = week;
            _pacts = week.pacts;
          });
        }
      }
      if (mounted && request == _request) _hasLoaded = true;
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = pactErrorMessage(error));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _select(String? id) async {
    if (id == null || id == _selected?.id) return;
    // The asked-for crew may not be in the list any more — deleted, or left
    // from another device, between the switcher opening and a name in it being
    // tapped. That is the same position the page's own load handles, so it
    // lands the same way: whatever crew is left, or none at all.
    final crews = _crews ?? const <PactCrew>[];
    final matches = crews.where((crew) => crew.id == id);
    final crew = matches.isNotEmpty
        ? matches.first
        : (crews.isEmpty ? null : crews.first);
    if (crew == null) {
      setState(() {
        _selected = null;
        _pacts = null;
        _week = null;
        _error = null;
      });
      return;
    }
    widget.onCrewSelected?.call(crew.id);
    final request = ++_request;
    setState(() {
      _selected = crew;
      _pacts = null;
      _error = null;
      _loading = true;
    });
    try {
      final week = await widget.loadWeek(crew.id);
      if (mounted && request == _request) {
        setState(() {
          _week = week;
          _pacts = week.pacts;
        });
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = pactErrorMessage(error));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _addPact([CrewPact? existing]) async {
    final crew = _selected;
    if (crew == null || !crew.isOwner) return;
    final pact = await showAppSheet<CrewPact>(
      context: context,
      builder: (_) =>
          PactEditor(crew: crew, backend: widget.backend, pact: existing),
    );
    if (!mounted || pact == null || _selected?.id != pact.crewId) return;
    // Refresh from the server so an overlapping load cannot hide the new pact.
    await _refresh();
  }

  Future<void> _deletePact(CrewPact pact) async {
    final crew = _selected;
    if (crew == null || !crew.isOwner || _deleting != null) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        icon: HugeIconsStrokeRounded.delete02,
        iconColor: WeekPactColors.sand,
        title: 'Delete pact?',
        // What goes with it, said plainly: the cascade behind this takes every
        // check-in ever made against the pact, for the whole crew, and that is
        // not something the crew can undo afterwards.
        message:
            '“${pact.title}” and every check-in the crew has ever made '
            'against it will be gone. This cannot be undone.',
        actions: [
          // Card ink, not the error red: the app's other destructive
          // confirmations — leaving a crew, removing a member — are this
          // button, and ink at 15px clears contrast on the fill where the
          // red does not. The red is spent on the menu entry that got here.
          AppButton(
            label: 'DELETE',
            onPressed: () => Navigator.pop(context, true),
          ),
          AppDialogDismiss(
            label: 'CANCEL',
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deleting = pact.id;
      _error = null;
    });
    try {
      await widget.backend.deletePact(pactId: pact.id, crewId: pact.crewId);
      if (!mounted) return;
      // The week the bars and the progress card both read is the server's, so
      // the page reloads it rather than dropping the pact from the local list
      // and leaving the card above still counting it.
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = pactErrorMessage(error));
    } finally {
      if (mounted) setState(() => _deleting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final crew = _selected;
    return PageFrame(
      header: CrewPageHeading(
        switcher: crew == null
            ? null
            : CrewSwitcher(
                crews: _crews!,
                selectedId: crew.id,
                onSelected: _loading ? null : _select,
              ),
      ),
      onRefresh: _refresh,
      loading: !_hasLoaded && _loading,
      skeleton: const CrewPageSkeleton(
        label: 'Loading pacts',
        body: PactsSkeletonBody(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_crews != null && _crews!.isEmpty)
            AppSectionCard(
              title: 'A shared start',
              builder: (context) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Find your crew first.',
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Create or join a crew to start building weekly habits together.',
                    ),
                    const SizedBox(height: 22),
                    AppButton(
                      label: 'GO TO CREWS',

                      onPressed: widget.onOpenCrews,
                    ),
                  ],
                ),
              ),
            ),
          if (crew != null) ...[
            if (_loading || (_pacts == null && _error == null))
              const CrewPageSkeleton(
                label: 'Loading pacts',
                body: PactsSkeletonBody(),
              )
            else if (_pacts != null) ...[
              YourWeekCard(week: _week!, userId: widget.userId),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      'Pacts',
                      key: const ValueKey('pacts-heading'),
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_pacts!.isNotEmpty)
                    Text(
                      'DAYS / WEEK',
                      style: TextStyle(
                        color: context.muted,
                        fontSize: 12,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_pacts!.isEmpty)
                AppSurface(
                  builder: (context) => Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Small steps start here.',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          crew.isOwner
                              ? 'Add your first shared pact. Choose every day or a few days each week.'
                              : 'Your crew owner hasn’t added any pacts yet.',
                        ),
                      ],
                    ),
                  ),
                )
              else
                PactBarList(
                  pacts: _pacts!,
                  onEdit: crew.isOwner && _deleting == null
                      ? (pact) => _addPact(pact)
                      : null,
                  onDelete: crew.isOwner && _deleting == null
                      ? _deletePact
                      : null,
                ),
              if (crew.isOwner) ...[
                const SizedBox(height: 16),
                AppButton(label: 'ADD PACT', onPressed: _addPact),
              ],
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: context.errorInk,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextButton(onPressed: _refresh, child: const Text('TRY AGAIN')),
          ],
        ],
      ),
    );
  }
}
