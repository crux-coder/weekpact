import '../home/home_backend.dart';
import '../crew/crew_page_layout.dart';
import '../crew/crew_switcher.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/app_components.dart';
import '../widgets/page_frame.dart';
import 'pacts_backend.dart';
import 'pact_icons.dart';
import 'pacts_overview.dart';
import 'pact_icon_picker.dart';

import '../widgets/app_icon.dart';

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
        setState(() => _error = _errorMessage(error));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _select(String? id) async {
    if (id == null || id == _selected?.id) return;
    widget.onCrewSelected?.call(id);
    final crew = _crews!.firstWhere((crew) => crew.id == id);
    final request = ++_request;
    setState(() {
      _selected = crew;
      _pacts = null;
      _error = null;
      _loading = true;
    });
    try {
      final week = await widget.loadWeek(id);
      if (mounted && request == _request) {
        setState(() {
          _week = week;
          _pacts = week.pacts;
        });
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = _errorMessage(error));
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

  @override
  Widget build(BuildContext context) {
    final crew = _selected;
    return PageFrame(
      header: const CrewPageHeading(
        title: 'Pacts',
        dotColor: WeekPactColors.stone,
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
          if (crew != null) ...[
            CrewSwitcher(
              compact: true,
              crews: _crews!,
              selectedId: crew.id,
              onSelected: _loading ? null : _select,
            ),
            const SizedBox(height: 12),
          ],
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
                        fontWeight: FontWeight.w900,
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
                showSelector: false,
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
                      'Your pacts',
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
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
                        fontWeight: FontWeight.w700,
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
                            fontWeight: FontWeight.w700,
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
                  onEdit: crew.isOwner ? (pact) => _addPact(pact) : null,
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
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton(onPressed: _refresh, child: const Text('TRY AGAIN')),
          ],
        ],
      ),
    );
  }
}

class PactEditor extends StatefulWidget {
  const PactEditor({
    super.key,
    required this.crew,
    required this.backend,
    this.pact,
  });
  final CrewPact? pact;
  final PactCrew crew;
  final PactsBackend backend;
  @override
  State<PactEditor> createState() => PactEditorState();
}

class PactEditorState extends State<PactEditor> {
  final _title = TextEditingController();
  final _form = GlobalKey<FormState>();
  PactFrequency _frequency = PactFrequency.daily;
  int _days = 3;
  String _iconKey = 'target';
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final pact = widget.pact;
    if (pact != null) {
      _title.text = pact.title;
      _frequency = pact.frequency;
      _days = pact.daysPerWeek;
      _iconKey = pact.iconKey;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.pact;
      final pact = existing != null
          ? await widget.backend.updatePact(
              pactId: existing.id,
              crewId: widget.crew.id,
              title: _title.text.trim(),
              iconKey: _iconKey,
              frequency: _frequency,
              daysPerWeek: _frequency == PactFrequency.daily ? 7 : _days,
            )
          : await widget.backend.addPact(
              crewId: widget.crew.id,
              title: _title.text.trim(),
              iconKey: _iconKey,
              frequency: _frequency,
              daysPerWeek: _frequency == PactFrequency.daily ? 7 : _days,
            );
      if (mounted) Navigator.pop(context, pact);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _errorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AppSheet(
      builder: (context) => Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.pact == null ? 'ADD A PACT' : 'EDIT PACT',
                    style: TextStyle(
                      color: context.ink,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close pact',
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
                ),
              ],
            ),
            if (widget.pact == null) ...[
              const SizedBox(height: 16),
              const Text('Start small. Make it yours.'),
              Wrap(
                spacing: 8,
                children: [
                  for (final starter in [
                    ('Move for 30 min', 'run', 3),
                    ('Read 20 pages', 'book', 4),
                    ('A little fresh air', 'target', 5),
                  ])
                    ActionChip(
                      label: Text(starter.$1),
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _title.text = starter.$1;
                              _iconKey = starter.$2;
                              _frequency = PactFrequency.weekly;
                              _days = starter.$3;
                            }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'PACT NAME',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: .4,
              ),
            ),
            const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 56,
                    child: AppSurface(
                      fillColor: context.yellow,
                      builder: (context) => IconButton(
                        tooltip:
                            'Change icon: ${PactIcon.find(_iconKey).label}',
                        onPressed: _saving
                            ? null
                            : () async {
                                FocusScope.of(context).unfocus();
                                final selected = await showAppSheet<String>(
                                  context: context,
                                  builder: (_) =>
                                      PactIconPicker(selectedKey: _iconKey),
                                );
                                if (mounted && selected != null) {
                                  setState(() => _iconKey = selected);
                                }
                              },
                        icon: AppIcon(
                          icon: PactIcon.find(_iconKey).data,
                          color: context.ink,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppTextField(
                      hint: 'Move for 30 minutes',
                      controller: _title,
                      validator: (value) {
                        final title = value?.trim() ?? '';
                        if (title.length < 2 || title.length > 100) {
                          return 'Use 2–100 characters';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'REPEAT EACH WEEK',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .5),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Every day'),
                  selected: _frequency == PactFrequency.daily,
                  selectedColor: context.yellow,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _frequency = PactFrequency.daily),
                ),
                ChoiceChip(
                  label: const Text('Days per week'),
                  selected: _frequency == PactFrequency.weekly,
                  selectedColor: WeekPactColors.coolGrey,
                  onSelected: _saving
                      ? null
                      : (_) =>
                            setState(() => _frequency = PactFrequency.weekly),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_frequency == PactFrequency.weekly)
              DropdownButtonFormField<int>(
                icon: const AppIcon(
                  icon: HugeIconsStrokeRounded.arrowDown01,
                  size: 20,
                ),
                initialValue: _days,
                decoration: const InputDecoration(
                  labelText: 'Days per week',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  7,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text(
                      '${index + 1} ${index == 0 ? 'day' : 'days'} per week',
                    ),
                  ),
                ),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _days = value!),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(_error!, style: TextStyle(color: context.errorInk)),
              ),
            const SizedBox(height: 24),
            AppButton(
              label: widget.pact == null ? 'SAVE PACT' : 'SAVE CHANGES',

              isLoading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    ),
  );
}

String _errorMessage(Object error) {
  if (error is PostgrestException && error.code == '42501') {
    return 'Only the crew owner can manage pacts.';
  }
  return 'Could not load or save pacts. Check your connection and try again.';
}
