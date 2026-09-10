import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/brutal_drawer.dart';
import '../widgets/brutal_widgets.dart';
import 'goal_icons.dart';

class GoalIconPicker extends StatefulWidget {
  const GoalIconPicker({super.key, required this.selectedKey});
  final String selectedKey;

  @override
  State<GoalIconPicker> createState() => _GoalIconPickerState();
}

class _GoalIconPickerState extends State<GoalIconPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final icons = GoalIcon.all
        .where(
          (icon) =>
              '${icon.label} ${icon.keywords}'.toLowerCase().contains(_query),
        )
        .toList();
    return BrutalDrawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'CHOOSE AN ICON',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Close icon picker',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          BrutalShadow(
            child: TextField(
              style: TextStyle(color: context.fieldInk, fontSize: 17),
              decoration: InputDecoration(
                hintText: 'Search icons',
                hintStyle: TextStyle(color: context.muted),
                prefixIcon: Icon(Icons.search, color: context.muted),
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
                                ? context.mint
                                : context.surface,
                            side: BorderSide(
                              color: context.border,
                              width: selected
                                  ? WeekPactMetrics.selectedBorder
                                  : WeekPactMetrics.border,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context, icon.key),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              HugeIcon(
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
