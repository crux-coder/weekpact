import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_page.dart';
import 'package:weekpact/src/crew/crew_page_layout.dart';
import 'package:weekpact/src/crew/crew_profile.dart';
import 'package:weekpact/src/crew/crew_roster.dart';
import 'package:weekpact/src/crew/crews_page.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/app_components.dart';
import 'package:weekpact/src/widgets/page_frame.dart';

import 'crews_page_test.dart' show ListWeeks;
import 'multiple_crews_test.dart' show MultipleCrews;
import 'support/fonts.dart';
import 'support/home_fakes.dart';

/// The skeleton is drawn as one flat tone, so what it promises is its blocks'
/// outlines. These hold each block over the thing it stands for, so the
/// crossfade from one to the other resolves in place instead of jumping.
const _capture = ValueKey('skeleton-alignment-capture');

Future<void> _pumpPhone(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pump();
}

/// Past the skeleton's minimum and the crossfade after it.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 800));
  }
}

List<Rect> _rects(WidgetTester tester, Finder finder) => [
  for (final element in finder.evaluate())
    tester.getRect(find.byElementPredicate((e) => e == element)),
];

void _expectSameRects(List<Rect> skeleton, List<Rect> loaded) {
  for (final (i, rect) in skeleton.indexed) {
    expect(rect.left, closeTo(loaded[i].left, 1), reason: 'block $i left');
    expect(rect.top, closeTo(loaded[i].top, 1), reason: 'block $i top');
    expect(rect.width, closeTo(loaded[i].width, 1), reason: 'block $i width');
    expect(
      rect.height,
      closeTo(loaded[i].height, 1),
      reason: 'block $i height',
    );
  }
}

Future<void> _capturePng(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_DESIGN')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/weekpact-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadAppFont);

  testWidgets('the crews list skeleton stands where its cards land', (
    tester,
  ) async {
    final crews = MultipleCrews()..loading = Completer();
    await _pumpPhone(
      tester,
      CrewsPage(
        backend: crews,
        weekBackend: ListWeeks(),
        userId: 'me',
        currentUserEmail: 'owner@example.com',
      ),
    );
    final skeleton = _rects(
      tester,
      find.descendant(
        of: find.byType(CrewsListSkeleton),
        matching: find.byType(AppSurface),
      ),
    );
    expect(skeleton, hasLength(3));
    await _capturePng(tester, 'crews-loading');

    crews.loading!.complete([
      for (final crew in crews.entries)
        PactCrew(
          id: crew.id,
          name: crew.name,
          timezone: crew.timezone,
          isOwner: crew.isOwner,
        ),
    ]);
    await _settle(tester);

    expect(find.byType(CrewsListSkeleton), findsNothing);
    final cards = _rects(tester, find.byType(CrewListCard));
    expect(cards, hasLength(2));
    _expectSameRects(skeleton.take(2).toList(), cards);
    await _capturePng(tester, 'crews-loaded');
    expect(tester.takeException(), isNull);
  });

  for (final tabs in [false, true]) {
    testWidgets('the crew page skeleton stands where the page lands'
        '${tabs ? ', with its tabs' : ''}', (tester) async {
      final crews = MultipleCrews()..crewLoading = Completer<void>();
      crews.entries[0] = CrewDetails(
        id: 'crew',
        name: 'Early Birds',
        timezone: 'UTC',
        ownerId: 'owner-id',
        currentUserRole: 'owner',
        createdAt: DateTime(2026, 9, 7),
        members: [
          for (var i = 0; i < 4; i++)
            CrewMember(
              userId: 'member-$i',
              email: 'member-$i@example.com',
              displayName: 'Member $i',
              role: i == 0 ? 'owner' : 'member',
              joinedAt: DateTime(2026),
            ),
        ],
      );
      final weeks = DashboardBackend(viewerId: 'member-0');
      await _pumpPhone(
        tester,
        CrewPage(
          crewId: 'crew',
          backend: crews,
          profileBackend: weeks,
          pactsBackend: tabs ? weeks.pacts : null,
          currentUserEmail: 'member-0@example.com',
        ),
      );

      // The photo, the summary card, the tabs or the roster's heading, then
      // each band, in the order the page stacks them.
      final skeleton = _rects(
        tester,
        find.descendant(
          of: find.byType(CrewRosterSkeleton),
          matching: find.byWidgetPredicate(
            (w) =>
                (w is SkeletonBar && w.shape != null && w.width == 56) ||
                w is CrewSummaryCard ||
                w is CrewSectionLabel ||
                (w is SkeletonBar && w.height == CrewPageTabs.height) ||
                w is CrewBand,
          ),
        ),
      );
      expect(skeleton, hasLength(7));
      await _capturePng(tester, 'crew-${tabs ? 'tabs-' : ''}loading');

      crews.crewLoading!.complete();
      await _settle(tester);

      expect(find.byType(CrewRosterSkeleton), findsNothing);
      final loaded = _rects(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is CrewAvatar ||
              w is CrewSummaryCard ||
              w is CrewSectionLabel ||
              w is CrewPageTabs ||
              w is CrewPersonBand,
        ),
      );
      expect(loaded, hasLength(7));
      _expectSameRects(skeleton, loaded);
      await _capturePng(tester, 'crew-${tabs ? 'tabs-' : ''}loaded');
      expect(tester.takeException(), isNull);
    });
  }
}
