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

import 'package:hugeicons/hugeicons.dart';

class PactsPage extends StatefulWidget {
  const PactsPage({
    super.key,
    required this.backend,
    required this.onOpenCrews,
  });
  final PactsBackend backend;
  final VoidCallback onOpenCrews;

  @override
  State<PactsPage> createState() => _PactsPageState();
}

class _PactsPageState extends State<PactsPage> {
  List<PactCrew>? _crews;
  PactCrew? _selected;
  List<CrewPact>? _pacts;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() => _error = null);
    try {
      final crews = await widget.backend.fetchCrews();
      if (!mounted || request != _request) return;
      final matches = crews.where((crew) => crew.id == _selected?.id);
      final selected = matches.isNotEmpty
          ? matches.first
          : (crews.isEmpty ? null : crews.first);
      setState(() {
        if (_selected?.id != selected?.id) _pacts = null;
        _crews = crews;
        _selected = selected;
      });
      if (selected != null) {
        final pacts = await widget.backend.fetchPacts(selected.id);
        if (mounted && request == _request) setState(() => _pacts = pacts);
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = _errorMessage(error));
      }
    }
  }

  Future<void> _select(String? id) async {
    if (id == null || id == _selected?.id) return;
    final crew = _crews!.firstWhere((crew) => crew.id == id);
    final request = ++_request;
    setState(() {
      _selected = crew;
      _pacts = null;
      _error = null;
    });
    try {
      final pacts = await widget.backend.fetchPacts(id);
      if (mounted && request == _request) setState(() => _pacts = pacts);
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = _errorMessage(error));
      }
    }
  }

  Future<void> _addPact([CrewPact? existing]) async {
    final crew = _selected;
    if (crew == null || !crew.isOwner) return;
    final pact = await showAppSheet<CrewPact>(
      context: context,
      builder: (_) =>
          _PactDrawer(crew: crew, backend: widget.backend, pact: existing),
    );
    if (!mounted || pact == null || _selected?.id != pact.crewId) return;
    // Refresh from the server so an overlapping load cannot hide the new pact.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final crew = _selected;
    return PageFrame(
      header: Row(
        children: [
          const Expanded(child: PageHeading('Pacts')),
          if (crew != null) ...[
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: AppSurface(
                builder: (context) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: crew.id,
                      isExpanded: true,
                      dropdownColor: context.surface,
                      items: _crews!
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.id,
                              child: Text(
                                entry.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _select,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      onRefresh: _refresh,
      loading: _crews == null && _error == null,
      skeleton: const _PactsSkeleton(),
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
            if (_pacts == null && _error == null)
              const _PactsSkeleton()
            else if (_pacts != null) ...[
              WeeklyRhythmCard(pacts: _pacts!),
              const SizedBox(height: 22),
              Text(
                'Your pacts',
                style: TextStyle(
                  color: context.ink,
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                ),
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
                PactSquareGrid(
                  pacts: _pacts!,
                  onEdit: crew.isOwner ? (pact) => _addPact(pact) : null,
                ),
              if (crew.isOwner) ...[
                const SizedBox(height: 16),
                AppButton(
                  label: 'ADD PACT',
                  color: WeekPactColors.mintGreen,
                  onPressed: _addPact,
                ),
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

class _PactsSkeleton extends StatelessWidget {
  const _PactsSkeleton();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading pacts',
    liveRegion: true,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSurface(
            fillColor: WeekPactColors.softYellow,
            builder: (context) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBar(width: 160, height: 20),
                  SizedBox(height: 20),
                  SkeletonBar(width: 90, height: 64),
                  SizedBox(height: 14),
                  SkeletonBar(height: 14),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Your pacts',
            style: TextStyle(
              color: context.ink,
              fontSize: 25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: AppSurface(
                      builder: (context) => Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.topLeft,
                              child: SkeletonBar(width: 36, height: 36),
                            ),
                            Spacer(),
                            SkeletonBar(height: 18),
                            SizedBox(height: 8),
                            SkeletonBar(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

class _PactDrawer extends StatefulWidget {
  const _PactDrawer({required this.crew, required this.backend, this.pact});
  final CrewPact? pact;
  final PactCrew crew;
  final PactsBackend backend;
  @override
  State<_PactDrawer> createState() => _PactDrawerState();
}

class _PactDrawerState extends State<_PactDrawer> {
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
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
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
                        icon: HugeIcon(
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
                  selectedColor: context.mint,
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
