import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_sheet.dart';
import 'pact_icon_picker.dart';
import 'pact_icons.dart';
import 'pacts_backend.dart';

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
  bool _photoRequired = true;
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
      _photoRequired = pact.photoRequired;
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
              photoRequired: _photoRequired,
              frequency: _frequency,
              daysPerWeek: _frequency == PactFrequency.daily ? 7 : _days,
            )
          : await widget.backend.addPact(
              crewId: widget.crew.id,
              title: _title.text.trim(),
              iconKey: _iconKey,
              photoRequired: _photoRequired,
              frequency: _frequency,
              daysPerWeek: _frequency == PactFrequency.daily ? 7 : _days,
            );
      if (mounted) Navigator.pop(context, pact);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = pactErrorMessage(error);
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
                      fontWeight: FontWeight.w700,
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
                fontWeight: FontWeight.w600,
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
              style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: .5),
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
            const SizedBox(height: 18),
            MergeSemantics(
              child: Row(
                children: [
                  const AppIcon(
                    icon: HugeIconsStrokeRounded.camera01,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Photo check-in',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _photoRequired
                              ? 'Checking in takes a picture.'
                              : 'A tap is enough. No picture needed.',
                          style: TextStyle(fontSize: 13, color: context.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    key: const ValueKey('pact-photo-required'),
                    activeTrackColor: WeekPactColors.coolGrey,
                    activeThumbColor: WeekPactColors.black,
                    value: _photoRequired,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _photoRequired = value),
                  ),
                ],
              ),
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

String pactErrorMessage(Object error) {
  if (error is PostgrestException && error.code == '42501') {
    return 'Only the crew owner can manage pacts.';
  }
  return 'Could not load or save pacts. Check your connection and try again.';
}
