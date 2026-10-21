import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';

/// A push that arrived while the app is open, drawn the way the system would
/// draw it with the app in the background: a banner at the top that goes by
/// itself, goes sooner when swiped up, and does what the push does when
/// tapped.
///
/// Android does not show a push over its own app, so this stands in for it
/// there. It sits above every route, so it reads the same on any screen.
class PushBannerHost extends StatefulWidget {
  const PushBannerHost({super.key, required this.child});

  final Widget child;

  @override
  State<PushBannerHost> createState() => PushBannerHostState();
}

class PushBannerHostState extends State<PushBannerHost>
    with SingleTickerProviderStateMixin {
  static const _showFor = Duration(seconds: 4);

  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  );
  _Banner? _banner;
  Timer? _timer;

  /// Shows [title] and [body]; a newer banner takes an older one's place.
  void show({
    required String title,
    String? body,
    List<List<dynamic>> icon = HugeIconsStrokeRounded.notification02,
    VoidCallback? onTap,
  }) {
    _timer?.cancel();
    setState(() => _banner = _Banner(title, body, icon, onTap));
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = 1;
    } else {
      unawaited(_slide.forward());
    }
    _timer = Timer(_showFor, _hide);
  }

  Future<void> _hide() async {
    _timer?.cancel();
    if (!mounted || _banner == null) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = 0;
    } else {
      await _slide.reverse();
    }
    if (mounted && !_slide.isAnimating && _slide.value == 0) {
      setState(() => _banner = null);
    }
  }

  void _tap() {
    final onTap = _banner?.onTap;
    unawaited(_hide());
    onTap?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    return Stack(
      children: [
        widget.child,
        if (banner != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, -1.4), end: Offset.zero)
                    .animate(
                      CurvedAnimation(
                        parent: _slide,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      ),
                    ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: GestureDetector(
                        key: const ValueKey('push-banner'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _tap,
                        onVerticalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) < 0) {
                            unawaited(_hide());
                          }
                        },
                        child: _BannerCard(banner: banner),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Banner {
  const _Banner(this.title, this.body, this.icon, this.onTap);
  final String title;
  final String? body;
  final List<List<dynamic>> icon;
  final VoidCallback? onTap;
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner});
  final _Banner banner;

  @override
  Widget build(BuildContext context) {
    final body = banner.body;
    return Semantics(
      liveRegion: true,
      button: banner.onTap != null,
      child: AppSurface(
        borderRadius: 22,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(
            children: [
              AppIcon(icon: banner.icon, size: 22, color: context.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      banner.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (body != null && body.isNotEmpty)
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.muted, fontSize: 14),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
