import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';
import 'home_backend.dart';
import 'stories.dart';

/// Posts an achievement to [crewId]: a win outside any pact, for the crew's
/// rail today. Completes with what was posted, or null when the sheet was
/// put away.
///
/// Words only. A pact that wants proof asks for a photo at check-in; an
/// achievement is a member telling the crew, and the crew claps for the
/// telling.
Future<Achievement?> showAchievementComposer({
  required BuildContext context,
  required HomeBackend backend,
  required String crewId,
  required String crewName,
}) => showAppSheet<Achievement>(
  context: context,
  builder: (context) => AppSheet(
    builder: (context) => _AchievementComposer(
      backend: backend,
      crewId: crewId,
      crewName: crewName,
    ),
  ),
);

class _AchievementComposer extends StatefulWidget {
  const _AchievementComposer({
    required this.backend,
    required this.crewId,
    required this.crewName,
  });

  final HomeBackend backend;
  final String crewId;
  final String crewName;

  @override
  State<_AchievementComposer> createState() => _AchievementComposerState();
}

class _AchievementComposerState extends State<_AchievementComposer> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  bool _posting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _length => _text.text.trim().characters.length;

  Future<void> _post() async {
    if (_posting || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      final posted = await widget.backend.postAchievement(
        crewId: widget.crewId,
        text: _text.text.trim(),
      );
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
      Navigator.pop(context, posted);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        // The server caps a member's day, and says so in its own words.
        _error = error.toString().contains('five achievements')
            ? 'That’s five achievements today. Save the next one for tomorrow.'
            : 'Could not post. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final over = _length > Achievement.maxLength;
    return Form(
      key: _form,
      child: Column(
        key: const ValueKey('achievement-composer'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 40,
                child: DecoratedBox(
                  decoration: const ShapeDecoration(
                    color: WeekPactColors.achievement,
                    shape: WeekPactMetrics.buttonShape,
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: achievementIcon,
                      color: WeekPactColors.black,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Share an achievement',
                  style: TextStyle(
                    color: context.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'A win outside your pacts. ${widget.crewName.trim().isEmpty ? 'Your crew' : widget.crewName.trim()} '
            'sees it in today’s stories, and can clap for it.',
            style: TextStyle(color: context.muted, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 16),
          AppTextField(
            key: const ValueKey('achievement-text'),
            hint: 'Climbed my first 6c',
            controller: _text,
            minLines: 3,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Say what you did.';
              if (text.characters.length > Achievement.maxLength) {
                return 'Keep it to ${Achievement.maxLength} characters.';
              }
              return null;
            },
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$_length / ${Achievement.maxLength}',
              style: TextStyle(
                fontFamily: WeekPactType.secondary,
                fontFamilyFallback: WeekPactType.secondaryFallback,
                fontSize: 12,
                color: over ? context.errorInk : context.muted,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: context.errorInk, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          AppButton(
            key: const ValueKey('post-achievement'),
            label: _posting ? 'POSTING…' : 'POST',
            isLoading: _posting,
            onPressed: _length == 0 || over || _posting ? null : _post,
          ),
        ],
      ),
    );
  }
}
