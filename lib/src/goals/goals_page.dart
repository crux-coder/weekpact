import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/app_components.dart';
import '../widgets/page_frame.dart';
import 'goals_backend.dart';
import 'goal_icons.dart';
import 'goals_overview.dart';
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
    final goal = await showAppSheet<CrewGoal>(
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
      header: Row(
        children: [
          const Expanded(child: PageHeading('Goals')),
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
      skeleton: const _GoalsSkeleton(),
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
            if (_goals == null && _error == null)
              const _GoalsSkeleton()
            else if (_goals != null) ...[
              WeeklyRhythmCard(goals: _goals!),
              const SizedBox(height: 22),
              Text(
                'Your goals',
                style: TextStyle(
                  color: context.ink,
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (_goals!.isEmpty)
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
                              ? 'Add your first shared goal. Choose every day or a few days each week.'
                              : 'Your crew owner hasn’t added any goals yet.',
                        ),
                      ],
                    ),
                  ),
                )
              else
                GoalSquareGrid(
                  goals: _goals!,
                  onEdit: crew.isOwner ? (goal) => _addGoal(goal) : null,
                ),
              if (crew.isOwner) ...[
                const SizedBox(height: 16),
                AppButton(
                  label: 'ADD GOAL',
                  color: WeekPactColors.mintGreen,
                  onPressed: _addGoal,
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

class _GoalsSkeleton extends StatelessWidget {
  const _GoalsSkeleton();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading goals',
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
            'Your goals',
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
                            'Change icon: ${GoalIcon.find(_iconKey).label}',
                        onPressed: _saving
                            ? null
                            : () async {
                                FocusScope.of(context).unfocus();
                                final selected = await showAppSheet<String>(
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
            AppButton(
              label: widget.goal == null ? 'SAVE GOAL' : 'SAVE CHANGES',

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
