import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'weekpact_theme.dart';

/// Frosts whatever scrolls under the status bar, on every route, instead of
/// letting it slide out of view behind the clock and the island with a hard
/// edge.
///
/// The blur is full behind the status bar and eases out below it, row by row,
/// so there is no line where frosted meets sharp. Flutter's own blur has one
/// strength over its whole area, so this runs a shader of its own; where
/// shader filters are not available (Skia, and tests) it falls back to stacked
/// bands that build the blur up in steps.
class StatusBarBlur extends StatefulWidget {
  const StatusBarBlur({super.key, required this.child});

  final Widget child;

  @override
  State<StatusBarBlur> createState() => _StatusBarBlurState();
}

class _StatusBarBlurState extends State<StatusBarBlur> {
  /// How far below the status bar the blur trails off.
  static const _fade = 28.0;

  /// The blur behind the status bar, in logical pixels.
  static const _sigma = 10.0;

  static ui.FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    if (_program == null && ui.ImageFilter.isShaderFilterSupported) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      _program = await ui.FragmentProgram.fromAsset(
        'shaders/progressive_blur.frag',
      );
      if (mounted) setState(() {});
    } catch (_) {
      // The stepped bands stand in.
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    if (top == 0) return widget.child;
    final height = top + _fade;
    final canvas = context.canvas;
    final program = _program;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: height,
          child: IgnorePointer(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (program != null)
                  ClipRect(
                    child: BackdropFilter(
                      filter: _shaderBlur(
                        program,
                        MediaQuery.devicePixelRatioOf(context),
                        top,
                        height,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  )
                else
                  ..._steppedBlur(height),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, .4, .7, 1],
                      colors: [
                        canvas.withValues(alpha: .6),
                        canvas.withValues(alpha: .4),
                        canvas.withValues(alpha: .12),
                        canvas.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Across, then down; each pass eases out between the foot of the status
  /// bar and the end of the fade.
  ui.ImageFilter _shaderBlur(
    ui.FragmentProgram program,
    double ratio,
    double top,
    double height,
  ) {
    ui.ImageFilter pass(double dx, double dy) {
      final shader = program.fragmentShader()
        ..setFloat(2, dx)
        ..setFloat(3, dy)
        ..setFloat(4, _sigma * ratio)
        ..setFloat(5, top * .6 * ratio)
        ..setFloat(6, height * ratio);
      return ui.ImageFilter.shader(shader);
    }

    return ui.ImageFilter.compose(outer: pass(0, 1), inner: pass(1, 0));
  }

  /// Bands that each blur what those beneath them already blurred, each
  /// stopping a little higher, as (share of the height, blur).
  static const _bands = [
    (1.0, .6),
    (.88, 1.0),
    (.76, 1.6),
    (.64, 2.4),
    (.52, 3.4),
    (.4, 4.6),
    (.28, 6.0),
  ];

  List<Widget> _steppedBlur(double height) => [
    for (final (share, sigma) in _bands)
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: height * share,
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.mirror,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
  ];
}
