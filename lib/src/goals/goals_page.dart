import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/keepup_theme.dart';
import '../widgets/brutal_drawer.dart';
import '../widgets/brutal_widgets.dart';
import '../widgets/page_frame.dart';
import 'goals_backend.dart';
import 'goal_icons.dart';
import 'goal_icon_picker.dart';

import 'package:hugeicons/hugeicons.dart';

class GoalsPage extends StatefulWidget {
  const GoalsPage({
    super.key,
    required this.backend,
    required this.onOpenCrews,
  });
  final GoalsBackend backend;
  final VoidCallback onOpenCrews;

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  List<GoalCrew>? _crews;
  GoalCrew? _selected;
  List<CrewGoal>? _goals;
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
        if (_selected?.id != selected?.id) _goals = null;
        _crews = crews;
        _selected = selected;
      });
      if (selected != null) {
        final goals = await widget.backend.fetchGoals(selected.id);
        if (mounted && request == _request) setState(() => _goals = goals);
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
      _goals = null;
      _error = null;
    });
    try {
      final goals = await widget.backend.fetchGoals(id);
      if (mounted && request == _request) setState(() => _goals = goals);
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = _errorMessage(error));
      }
    }
  }

  Future<void> _addGoal([CrewGoal? existing]) async {
    final crew = _selected;
    if (crew == null || !crew.isOwner) return;
    final goal = await showBrutalDrawer<CrewGoal>(
      context: context,
      builder: (_) =>
          _GoalDrawer(crew: crew, backend: widget.backend, goal: existing),
    );
    if (!mounted || goal == null || _selected?.id != goal.crewId) return;
    // Refresh from the server so an overlapping load cannot hide the new goal.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final crew = _selected;
    return PageFrame(
      header: const PageHeading('GOALS.'),
      onRefresh: _refresh,
      loading: _crews == null && _error == null,
      skeleton: const _GoalsSkeleton(includeSelector: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_crews != null && _crews!.isEmpty)
            BrutalTabbedCard(
              title: 'A SHARED START',
              tabColor: context.mint,
              child: Padding(
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
                    BrutalButton(
                      label: 'GO TO CREWS',
                      color: context.coral,
                      onPressed: widget.onOpenCrews,
                    ),
                  ],
                ),
              ),
            ),
          if (crew != null) ...[
            BrutalTabbedCard(
              title: 'SELECT CREW',
              tabColor: context.yellow,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
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
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
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
            const SizedBox(height: 26),
            if (_goals == null && _error == null)
              const _GoalsSkeleton()
            else if (_goals != null)
              BrutalTabbedCard(
                title: 'WEEKLY GOALS',
                tabColor: context.mint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_goals!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Small steps start here.',
                              style: TextStyle(
                                color: context.ink,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              crew.isOwner
                                  ? 'Add your first shared goal. Choose every day or a few days each week.'
                                  : 'Your crew owner hasn’t added any goals yet.',
                            ),
                          ],
                        ),
                      ),
                    for (var index = 0; index < _goals!.length; index++) ...[
                      _GoalRow(
                        goal: _goals![index],
                        onEdit: crew.isOwner
                            ? () => _addGoal(_goals![index])
                            : null,
                      ),
                      if (index < _goals!.length - 1)
                        Divider(
                          color: context.border,
                          thickness: KeepUpMetrics.fineBorder,
                          height: 2,
                        ),
                    ],
                    if (crew.isOwner)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 16, 18, 22),
                        child: BrutalButton(
                          label: 'ADD GOAL',
                          color: context.coral,
                          onPressed: _addGoal,
                        ),
                      ),
                  ],
                ),
              ),
            if (!crew.isOwner)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Your crew owner manages these goals.',
                  style: TextStyle(color: context.muted),
                ),
              ),
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

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal, this.onEdit});
  final VoidCallback? onEdit;
  final CrewGoal goal;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: goal.frequency == GoalFrequency.daily
                ? context.yellow
                : context.mint,
            border: Border.all(
              color: context.border,
              width: KeepUpMetrics.border,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: HugeIcon(
            icon: GoalIcon.find(goal.iconKey).data,
            color: context.ink,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                goal.title,
                style: TextStyle(
                  color: context.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                goal.schedule,
                style: TextStyle(
                  color: context.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (onEdit != null)
          IconButton(
            tooltip: 'Edit ${goal.title}',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
    ),
  );
}

class _GoalsSkeleton extends StatelessWidget {
  const _GoalsSkeleton({this.includeSelector = false});
  final bool includeSelector;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading goals',
    liveRegion: true,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (includeSelector) ...[
            BrutalTabbedCard(
              title: 'SELECT CREW',
              tabColor: context.yellow,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SkeletonBar(height: 22),
              ),
            ),
            const SizedBox(height: 28),
          ],
          BrutalTabbedCard(
            title: 'WEEKLY GOALS',
            tabColor: context.mint,
            child: Column(
              children: [
                for (var index = 0; index < 3; index++)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        SkeletonBar(width: 42, height: 42),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBar(height: 18),
                              SizedBox(height: 8),
                              SkeletonBar(width: 110, height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _GoalDrawer extends StatefulWidget {
  const _GoalDrawer({required this.crew, required this.backend, this.goal});
  final CrewGoal? goal;
  final GoalCrew crew;
  final GoalsBackend backend;
  @override
  State<_GoalDrawer> createState() => _GoalDrawerState();
}

class _GoalDrawerState extends State<_GoalDrawer> {
  final _title = TextEditingController();
  final _form = GlobalKey<FormState>();
  GoalFrequency _frequency = GoalFrequency.daily;
  int _days = 3;
  String _iconKey = 'target';
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    if (goal != null) {
      _title.text = goal.title;
      _frequency = goal.frequency;
      _days = goal.daysPerWeek;
      _iconKey = goal.iconKey;
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
      final existing = widget.goal;
      final goal = existing != null
          ? await widget.backend.updateGoal(
              goalId: existing.id,
              crewId: widget.crew.id,
              title: _title.text.trim(),
              iconKey: _iconKey,
              frequency: _frequency,
              daysPerWeek: _frequency == GoalFrequency.daily ? 7 : _days,
            )
          : await widget.backend.addGoal(
              crewId: widget.crew.id,
              title: _title.text.trim(),
              iconKey: _iconKey,
              frequency: _frequency,
              daysPerWeek: _frequency == GoalFrequency.daily ? 7 : _days,
            );
      if (mounted) Navigator.pop(context, goal);
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
    child: BrutalDrawer(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.goal == null ? 'ADD A GOAL' : 'EDIT GOAL',
                    style: TextStyle(
                      color: context.ink,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close goal',
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'GOAL NAME',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: .4,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: KeepUpMetrics.buttonHeight,
                  height: KeepUpMetrics.buttonHeight,
                  child: BrutalShadow(
                    fillColor: context.yellow,
                    child: IconButton(
                      tooltip: 'Change icon: ${GoalIcon.find(_iconKey).label}',
                      onPressed: _saving
                          ? null
                          : () async {
                              FocusScope.of(context).unfocus();
                              final selected = await showBrutalDrawer<String>(
                                context: context,
                                builder: (_) =>
                                    GoalIconPicker(selectedKey: _iconKey),
                              );
                              if (mounted && selected != null) {
                                setState(() => _iconKey = selected);
                              }
                            },
                      icon: HugeIcon(
                        icon: GoalIcon.find(_iconKey).data,
                        color: context.ink,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: BrutalTextField(
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
                  selected: _frequency == GoalFrequency.daily,
                  selectedColor: context.yellow,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _frequency = GoalFrequency.daily),
                ),
                ChoiceChip(
                  label: const Text('Days per week'),
                  selected: _frequency == GoalFrequency.weekly,
                  selectedColor: context.mint,
                  onSelected: _saving
                      ? null
                      : (_) =>
                            setState(() => _frequency = GoalFrequency.weekly),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_frequency == GoalFrequency.weekly)
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
            BrutalButton(
              label: widget.goal == null ? 'SAVE GOAL' : 'SAVE CHANGES',
              color: context.coral,
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
    return 'Only the crew owner can manage goals.';
  }
  return 'Could not load or save goals. Check your connection and try again.';
}
