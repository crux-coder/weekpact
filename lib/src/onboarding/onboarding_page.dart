import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:hugeicons/hugeicons.dart';

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/auth_backend.dart';
import '../auth/account_actions.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/welcome_card.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.backend,
    required this.user,
    required this.onCompleted,
    this.pickAvatar,
  });
  final AuthBackend backend;
  final AuthUser user;
  final ValueChanged<AuthUser> onCompleted;
  final Future<Uint8List?> Function()? pickAvatar;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.user.firstName);
  late final _last = TextEditingController(text: widget.user.lastName);
  bool _details = false;
  bool _saving = false;
  bool _picking = false;
  Uint8List? _avatar;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        widget.pickAvatar == null) {
      _recoverPhoto();
    }
  }

  Future<Uint8List> _preparePhoto(XFile file) async {
    if (await file.length() > 20 * 1024 * 1024) {
      throw StateError('Choose a photo smaller than 20 MB.');
    }
    final bytes = await file.readAsBytes();
    // Re-encode a bounded image so storage receives PNG bytes without photo metadata.
    final descriptor = await ui.ImmutableBuffer.fromUint8List(bytes);
    final imageDescriptor = await ui.ImageDescriptor.encoded(descriptor);
    try {
      final maxSide = imageDescriptor.width > imageDescriptor.height
          ? imageDescriptor.width
          : imageDescriptor.height;
      final scale = maxSide > 512 ? 512 / maxSide : 1.0;
      final codec = await imageDescriptor.instantiateCodec(
        targetWidth: (imageDescriptor.width * scale).round().clamp(1, 512),
        targetHeight: (imageDescriptor.height * scale).round().clamp(1, 512),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data == null || data.lengthInBytes > 5 * 1024 * 1024) {
            throw StateError('Choose a smaller photo.');
          }
          return data.buffer.asUint8List();
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      imageDescriptor.dispose();
      descriptor.dispose();
    }
  }

  Future<void> _recoverPhoto() async {
    try {
      final result = await ImagePicker().retrieveLostData();
      if (result.exception != null) throw result.exception!;
      if (result.files?.isNotEmpty == true) {
        final bytes = await _preparePhoto(result.files!.first);
        if (mounted) {
          setState(() {
            _avatar = bytes;
            _details = true;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We couldn’t restore your photo. Please choose it again.',
        );
      }
    }
  }

  Future<void> _choosePhoto() async {
    if (_picking || _saving) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      Uint8List? bytes;
      if (widget.pickAvatar != null) {
        bytes = await widget.pickAvatar!();
      } else {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 85,
          requestFullMetadata: false,
        );
        if (file != null) bytes = await _preparePhoto(file);
      }
      if (mounted && bytes != null) setState(() => _avatar = bytes);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Couldn’t open that photo. Try another image or check photo access in Settings.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _picking) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final valid = _form.currentState!.validate();
    if (!valid) return;
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
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      TextInput.finishAutofillContext();
      // Explicitly dismiss the native keyboard before replacing this screen.
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      if (mounted) widget.onCompleted(user);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We couldn’t save your profile. Your details are still here—please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.canvas,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'WeekPact.',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: context.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton(
                      onPressed: _saving || _picking
                          ? null
                          : () async {
                              try {
                                await widget.backend.signOut();
                              } catch (_) {
                                if (mounted) {
                                  setState(
                                    () => _error =
                                        'Couldn’t sign out. Please try again.',
                                  );
                                }
                              }
                            },
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                WelcomeCard(
                  title: _details
                      ? 'Make it you.'
                      : 'Good habits.\nGreat company.',
                  subtitle: _details
                      ? 'A name your crew knows. Photo and surname optional.'
                      : 'A few small steps. Better together.',
                  eyebrow: _details ? 'STEP 2 OF 2' : 'STEP 1 OF 2',
                  color: _details
                      ? WeekPactColors.coolGrey
                      : WeekPactColors.stone,
                ),
                const SizedBox(height: 8),
                if (!_details) ...[
                  for (final step in [
                    (
                      '01',
                      'Find your crew',
                      'Invite your people or join a crew.',
                      WeekPactColors.coolGrey,
                    ),
                    (
                      '02',
                      'Make a weekly pact',
                      'Choose pacts you can show up for.',
                      WeekPactColors.cream,
                    ),
                    (
                      '03',
                      'Keep showing up',
                      'Check in. Build a streak together.',
                      WeekPactColors.cream,
                    ),
                  ]) ...[
                    AppSurface(
                      fillColor: step.$4,
                      builder: (context) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: _introStep(context, step.$1, step.$2, step.$3),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  AppButton(
                    label: 'LET’S GET STARTED',

                    onPressed: () => setState(() {
                      _details = true;
                      _error = null;
                    }),
                  ),
                ] else
                  AppSurface(
                    builder: (context) => Padding(
                      padding: const EdgeInsets.all(18),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Column(
                                children: [
                                  Semantics(
                                    button: true,
                                    label: 'Choose avatar photo',
                                    child: InkWell(
                                      onTap: _saving || _picking
                                          ? null
                                          : _choosePhoto,
                                      borderRadius: BorderRadius.circular(60),
                                      child: Container(
                                        width: 112,
                                        height: 112,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: context.yellow,
                                          border: Border.all(
                                            color: context.border,
                                            width: WeekPactMetrics.border,
                                          ),
                                        ),
                                        child: ClipOval(
                                          child: _avatar == null
                                              ? HugeIcon(
                                                  icon: HugeIconsStrokeRounded
                                                      .cameraAdd01,
                                                  size: 36,
                                                  color: context.ink,
                                                )
                                              : Image.memory(
                                                  _avatar!,
                                                  fit: BoxFit.cover,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _saving || _picking
                                        ? null
                                        : _choosePhoto,
                                    child: Text(
                                      _picking
                                          ? 'Opening photos…'
                                          : _avatar == null
                                          ? 'Choose photo'
                                          : 'Change photo',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _first,
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              enabled: !_saving,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.givenName],
                              maxLength: 60,
                              decoration: const InputDecoration(
                                labelText: 'Display name',
                                counterText: '',
                              ),
                              validator: _validateName,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _last,
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              enabled: !_saving,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.familyName],
                              maxLength: 60,
                              decoration: const InputDecoration(
                                labelText: 'Last name (optional)',
                                counterText: '',
                              ),
                              validator: (value) =>
                                  (value?.trim().length ?? 0) > 60
                                  ? 'Use up to 60 characters.'
                                  : null,
                              onFieldSubmitted: (_) => _save(),
                            ),
                            const SizedBox(height: 16),
                            AppButton(
                              label: 'LET’S GO',

                              isLoading: _saving,
                              onPressed: _saving || _picking ? null : _save,
                            ),
                            TextButton(
                              onPressed: _saving || _picking
                                  ? null
                                  : () => setState(() => _details = false),
                              child: const Text('Back'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                AccountActions(
                  backend: widget.backend,
                  showPasswordReset: false,
                  enabled: !_saving && !_picking,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(color: context.errorInk),
                      semanticsLabel: _error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  String? _validateName(String? value) => value == null || value.trim().isEmpty
      ? 'Enter your name.'
      : value.trim().length > 60
      ? 'Use up to 60 characters.'
      : null;
  Widget _introStep(
    BuildContext context,
    String number,
    String title,
    String description,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        number,
        style: TextStyle(
          fontSize: 20,
          color: context.ink,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                color: context.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              description,
              style: TextStyle(fontSize: 16, color: context.ink),
            ),
          ],
        ),
      ),
    ],
  );
}
