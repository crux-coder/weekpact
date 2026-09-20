import '../widgets/app_icon.dart';

import 'dart:typed_data';

import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:flutter/material.dart';

import 'auth_backend.dart';
import 'avatar_picker.dart';
import '../onboarding/profile_avatar.dart';
import '../widgets/avatar_shape.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';

/// What the sheet hands back: the saved account, and the photo when a new one
/// was chosen, so the page behind can show it without asking storage for the
/// bytes it already has.
class ProfileEdit {
  const ProfileEdit({required this.user, this.avatar});
  final AuthUser user;
  final Uint8List? avatar;
}

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
    super.key,
    required this.user,
    required this.backend,
    this.pickAvatar,
  });
  final AuthUser user;
  final AuthBackend backend;

  /// Injected by tests, which have no gallery for the native picker to open.
  final AvatarPicker? pickAvatar;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final _first = TextEditingController(text: widget.user.firstName);
  late final _last = TextEditingController(text: widget.user.lastName);
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  bool _picking = false;
  // Only a photo chosen here is uploaded on save; leaving it null keeps the
  // one already on the account rather than clearing it.
  Uint8List? _avatar;
  String? _error;

  String get _initials => [widget.user.firstName, widget.user.lastName]
      .where((part) => part.trim().isNotEmpty)
      .map((part) => part.trim().characters.first.toUpperCase())
      .join();

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    if (_saving || _picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final bytes = await (widget.pickAvatar ?? pickAvatarPhoto)();
      if (mounted && bytes != null) setState(() => _avatar = bytes);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Couldn’t open that photo. Try another image or check photo '
              'access in Settings.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _picking || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await widget.backend.completeOnboarding(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        avatar: _avatar,
      );
      if (mounted) {
        Navigator.pop(context, ProfileEdit(user: user, avatar: _avatar));
      }
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
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
                  tooltip: 'Close profile',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Column(
                children: [
                  Semantics(
                    button: true,
                    label: 'Choose profile photo',
                    child: InkWell(
                      onTap: _saving || _picking ? null : _choosePhoto,
                      customBorder: const AvatarShape(),
                      // The avatar loads the photo on the account today; a
                      // pick here overrides it without a second download.
                      child: ProfileAvatar(
                        key: const ValueKey('profile-editor-avatar'),
                        backend: widget.backend,
                        size: 88,
                        initials: _initials,
                        backgroundColor: WeekPactColors.mintGreen,
                        photo: _avatar,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving || _picking ? null : _choosePhoto,
                    child: Text(_picking ? 'Opening photos…' : 'Change photo'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
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
