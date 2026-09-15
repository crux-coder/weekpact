import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:flutter/material.dart';

import 'auth_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, required this.user, required this.backend});
  final AuthUser user;
  final AuthBackend backend;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final _first = TextEditingController(text: widget.user.firstName);
  late final _last = TextEditingController(text: widget.user.lastName);
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await widget.backend.completeOnboarding(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
      );
      if (mounted) Navigator.pop(context, user);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save your profile. Try again.';
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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Edit profile',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
                  tooltip: 'Close profile',
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'FIRST NAME',
              hint: 'First name',
              controller: _first,
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Enter your first name'
                  : null,
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'LAST NAME',
              hint: 'Last name',
              controller: _last,
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Enter your last name'
                  : null,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: context.errorInk)),
              ),
            const SizedBox(height: 20),
            AppButton(
              label: 'SAVE',
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    ),
  );
}
