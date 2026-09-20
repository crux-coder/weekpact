import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:flutter/material.dart';

import '../widgets/app_icon.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/app_components.dart';
import 'pact_icons.dart';

class PactIconPicker extends StatefulWidget {
  const PactIconPicker({super.key, required this.selectedKey});
  final String selectedKey;

  @override
  State<PactIconPicker> createState() => _PactIconPickerState();
}

class _PactIconPickerState extends State<PactIconPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final icons = PactIcon.all
        .where(
          (icon) =>
              '${icon.label} ${icon.keywords}'.toLowerCase().contains(_query),
        )
        .toList();
    return AppSheet(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'CHOOSE AN ICON',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Close icon picker',
                onPressed: () => Navigator.pop(context),
                icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppSurface(
            builder: (context) => TextField(
              style: TextStyle(color: context.fieldInk, fontSize: 17),
              decoration: InputDecoration(
                hintText: 'Search icons',
                hintStyle: TextStyle(color: context.muted),
                prefixIcon: AppIcon(
                  icon: HugeIconsStrokeRounded.search01,
                  color: context.muted,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 17,
                ),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: (MediaQuery.sizeOf(context).height * .36).clamp(
              160.0,
              340.0,
            ),
            child: icons.isEmpty
                ? const Center(child: Text('No icons found'))
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 115,
                          mainAxisExtent: 92,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: icons.length,
                    itemBuilder: (context, index) {
                      final icon = icons[index];
                      final selected = widget.selectedKey == icon.key;
                      return Semantics(
                        selected: selected,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(4),
                            foregroundColor: context.ink,
                            backgroundColor: selected
                                ? WeekPactColors.coolGrey
                                : context.surface,
                            side: BorderSide(
                              color: context.border,
                              width: selected
                                  ? WeekPactMetrics.selectedBorder
                                  : WeekPactMetrics.border,
                            ),
                            shape: WeekPactMetrics.buttonShape,
                          ),
                          onPressed: () => Navigator.pop(context, icon.key),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AppIcon(
                                icon: icon.data,
                                color: context.ink,
                                size: 28,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                icon.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
