import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/avatar_picker.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar_shape.dart';
import 'crew_backend.dart';
import 'crew_page.dart' show crewErrorMessage;

String? validateCrewName(String? value) {
  final name = value?.trim() ?? '';
  if (name.length < 2) return 'Use at least 2 characters';
  if (name.length > 60) return 'Use no more than 60 characters';
  return null;
}

String? validateCrewDescription(String? value) =>
    (value?.trim().length ?? 0) > crewDescriptionMaxLength
    ? 'Use no more than $crewDescriptionMaxLength characters'
    : null;

/// A crew's face: its photo, or the first letter of its name on a tint.
///
/// [photo] is one just chosen and not yet saved, which wins over [url].
class CrewAvatar extends StatelessWidget {
  const CrewAvatar({
    super.key,
    required this.name,
    this.url,
    this.photo,
    this.size = 56,
    this.color = WeekPactColors.mintGreen,
  });

  final String name;
  final String? url;
  final Uint8List? photo;
  final double size;
  final Color color;

  Widget _initial(BuildContext context) {
    final trimmed = name.trim();
    return ColoredBox(
      color: color,
      child: Center(
        child: trimmed.isEmpty
            ? AppIcon(
                icon: HugeIconsStrokeRounded.userGroup02,
                color: WeekPactColors.black,
                size: size * .45,
              )
            : Text(
                trimmed.characters.first.toUpperCase(),
                style: TextStyle(
                  color: WeekPactColors.black,
                  fontSize: size * .42,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: AvatarClip(
      child: photo != null
          ? Image.memory(
              photo!,
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) => _initial(context),
            )
          : url?.trim().isNotEmpty == true
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, synchronous) =>
                  synchronous || frame != null ? child : _initial(context),
              errorBuilder: (context, _, _) => _initial(context),
            )
          : _initial(context),
    ),
  );
}

/// The crew's photo with the button that changes it, as both the new-crew
/// form and the editor show it. Picking is the caller's: it holds the bytes
/// until the crew is saved.
class CrewPhotoField extends StatelessWidget {
  const CrewPhotoField({
    super.key,
    required this.name,
    required this.onPick,
    this.url,
    this.photo,
    this.picking = false,
  });

  final String name;
  final String? url;
  final Uint8List? photo;
  final bool picking;

  /// Null while the form is busy.
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photo != null || url?.trim().isNotEmpty == true;
    return Center(
      child: Column(
        children: [
          Semantics(
            button: true,
            label: 'Choose crew photo',
            child: InkWell(
              onTap: picking ? null : onPick,
              customBorder: const AvatarShape(),
              child: CrewAvatar(
                key: const ValueKey('crew-photo-field-avatar'),
                name: name,
                url: url,
                photo: photo,
                size: 88,
              ),
            ),
          ),
          TextButton(
            onPressed: picking ? null : onPick,
            child: Text(
              picking
                  ? 'Opening photos…'
                  : hasPhoto
                  ? 'Change photo'
                  : 'Add photo',
            ),
          ),
        ],
      ),
    );
  }
}

/// Runs the photo picker for a crew form, turning a failure into the line the
/// form shows. Returns null when nothing was chosen.
Future<({Uint8List? photo, String? error})> pickCrewPhoto(
  AvatarPicker? picker,
) async {
  try {
    return (photo: await (picker ?? pickAvatarPhoto)(), error: null);
  } catch (_) {
    return (
      photo: null,
      error:
          'Couldn’t open that photo. Try another image or check photo '
          'access in Settings.',
    );
  }
}

/// The owner's sheet for a crew's name, description and photo. Pops with the
/// saved crew.
class CrewEditor extends StatefulWidget {
  const CrewEditor({
    super.key,
    required this.crew,
    required this.backend,
    this.pickAvatar,
  });

  final CrewDetails crew;
  final CrewEditingBackend backend;

  /// Injected by tests, which have no gallery for the native picker to open.
  final AvatarPicker? pickAvatar;

  @override
  State<CrewEditor> createState() => _CrewEditorState();
}

class _CrewEditorState extends State<CrewEditor> {
  late final _name = TextEditingController(text: widget.crew.name);
  late final _description = TextEditingController(
    text: widget.crew.description ?? '',
  );
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  bool _picking = false;
  // Only a photo chosen here is uploaded; null keeps the crew's own.
  Uint8List? _photo;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The placeholder letter follows the name as it is typed.
    _name.addListener(_onNameChanged);
  }

  void _onNameChanged() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    if (_saving || _picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    final picked = await pickCrewPhoto(widget.pickAvatar);
    if (!mounted) return;
    setState(() {
      _picking = false;
      _photo = picked.photo ?? _photo;
      _error = picked.error;
    });
  }

  Future<void> _save() async {
    if (_saving || _picking || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final crew = await widget.backend.updateCrew(
        crewId: widget.crew.id,
        name: _name.text,
        description: _description.text,
        avatar: _photo,
      );
      if (mounted) Navigator.pop(context, crew);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is ArgumentError
              ? '${error.message}'
              : error.toString().contains('edit a crew')
              ? 'Only the crew’s owner can edit it.'
              : crewErrorMessage(error);
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
                    'Edit crew',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
                  tooltip: 'Close crew editor',
                ),
              ],
            ),
            const SizedBox(height: 8),
            CrewPhotoField(
              name: _name.text,
              url: widget.crew.avatarUrl,
              photo: _photo,
              picking: _picking,
              onPick: _saving ? null : _choosePhoto,
            ),
            const SizedBox(height: 12),
            AppTextField(
              key: const ValueKey('crew-editor-name'),
              label: 'CREW NAME',
              hint: 'Early Birds',
              controller: _name,
              validator: validateCrewName,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            AppTextField(
              key: const ValueKey('crew-editor-description'),
              label: 'DESCRIPTION',
              hint: 'What this crew is about (optional)',
              controller: _description,
              validator: validateCrewDescription,
              keyboardType: TextInputType.multiline,
              minLines: 2,
              maxLines: 4,
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
