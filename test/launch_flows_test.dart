import 'support/photo_fakes.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_sharing.dart';
import 'package:weekpact/src/invites/invite_links.dart';
import 'package:weekpact/src/crew/crew_page.dart';
import 'package:weekpact/src/crew/crew_roster.dart';
import 'package:weekpact/src/onboarding/crew_setup_page.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/sharing/app_share.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/page_frame.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

class SetupCrew extends MissingCrewBackend {
  CrewDetails? crew;
  int created = 0;
  @override
  Future<CrewDetails?> fetchCrew({String? crewId}) async => crew;
  @override
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
  }) async {
    created++;
    return crew = CrewDetails(
      id: 'crew',
      name: name,
      timezone: timezone,
      ownerId: '',
      currentUserRole: 'owner',
      members: [
        CrewMember(
          userId: '',
          email: '',
          role: 'owner',
          joinedAt: DateTime.now(),
        ),
      ],
    );
  }
}

/// Setup that is still finding out where the person got to last time.
class SlowSetupCrew extends SetupCrew {
  final pending = Completer<CrewDetails?>();
  @override
  Future<CrewDetails?> fetchCrew({String? crewId}) => pending.future;
}

class SetupPacts extends DashboardPacts {
  SetupPacts() {
    pacts = [];
  }
  bool fail = false;
  @override
  Future<CrewPact> addPact({
    required String crewId,
    required String title,
    required PactFrequency frequency,
    required int daysPerWeek,
    String iconKey = 'target',
    bool photoRequired = true,
  }) async {
    if (fail) throw StateError('offline');
    final pact = CrewPact(
      id: 'new',
      crewId: crewId,
      title: title,
      frequency: frequency,
      daysPerWeek: daysPerWeek,
      iconKey: iconKey,
      photoRequired: photoRequired,
    );
    pacts.add(pact);
    return pact;
  }
}

class Sharing implements CrewSharingBackend {
  String code = '7K2QXM';
  int fetches = 0;
  int resets = 0;
  bool fail = false;
  @override
  Future<String> inviteCode(String crewId) async {
    fetches++;
    if (fail) throw StateError('offline');
    return code;
  }

  @override
  Future<String> resetInviteCode(String crewId) async {
    if (fail) throw StateError('offline');
    resets++;
    return code = 'ABCDEF';
  }
}

class SharingCrew extends SetupCrew implements CrewSharingBackend {
  final sharing = Sharing();
  @override
  Future<String> inviteCode(String crewId) => sharing.inviteCode(crewId);
  @override
  Future<String> resetInviteCode(String crewId) =>
      sharing.resetInviteCode(crewId);
}

class ShareFake implements AppShare {
  final texts = <String>[];
  bool fail = false;
  @override
  Future<void> text(String text, Rect origin) async {
    if (fail) throw StateError('cancelled');
    texts.add(text);
  }
}

void main() {
  testWidgets('guided setup creates one crew, edits starter, and checks in', (
    tester,
  ) async {
    final crews = SetupCrew();
    final pacts = SetupPacts();
    final home = DashboardBackend(pacts: pacts);
    home.selected.clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CrewSetupPage(
                  crewBackend: crews,
                  pactsBackend: pacts,
                  homeBackend: home,
                  captureCheckInPhoto: captureTestCheckInPhoto,
                  userId: '',
                ),
              ),
            ),
            child: const Text('Begin'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Begin'));
    await tester.pumpUi();
    await tester.enterText(find.byType(TextField), 'Sunday People');
    await tester.tap(find.text('Create crew'));
    await tester.pumpUi();
    expect(crews.created, 1);
    expect(find.text('Step 2 of 4'), findsOneWidget);
    await tester.tap(find.text('Choose a starter pact'));
    await tester.pumpUi();
    await tester.tap(find.text('Read 20 pages'));
    await tester.pumpUi();
    await tester.enterText(find.byType(TextFormField), 'Read 10 pages');
    final save = find.text('SAVE PACT');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpUi();
    expect(pacts.pacts.single.title, 'Read 10 pages');
    expect(pacts.pacts.single.daysPerWeek, 4);
    await tester.ensureVisible(find.text('Continue to first check-in'));
    await tester.tap(find.text('Continue to first check-in'));
    await tester.pumpUi();
    await tester.ensureVisible(find.text('I did it today'));
    await tester.tap(find.text('I did it today'));
    await tester.pumpUi();
    await submitTestPhoto(tester);
    expect(home.selected, {'new'});
    expect(crews.created, 1);
    expect(find.text('Begin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('guided setup stands a placeholder through its first load and '
      'still lets you leave', (tester) async {
    final crews = SlowSetupCrew();
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CrewSetupPage(
                  crewBackend: crews,
                  pactsBackend: DashboardPacts(),
                  homeBackend: DashboardBackend(),
                  userId: '',
                ),
              ),
            ),
            child: const Text('Begin'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Begin'));
    await tester.pumpUi();

    expect(find.byType(SkeletonBar), findsWidgets);
    expect(find.text('Create crew'), findsNothing);
    expect(find.text('Step 1 of 4'), findsNothing);
    // The wait belongs to the page, not to the person standing in front of it.
    await tester.pageBack();
    await tester.pumpUi();
    expect(find.text('Begin'), findsOneWidget);

    crews.pending.complete(null);
    await tester.pumpUi();
    expect(tester.takeException(), isNull);
  });

  testWidgets('setup resumes saved crew and pact without recreating them', (
    tester,
  ) async {
    final crews = SetupCrew();
    await crews.createCrew(name: 'Crew', timezone: 'UTC');
    await tester.pumpWidget(
      MaterialApp(
        home: CrewSetupPage(
          crewBackend: crews,
          pactsBackend: DashboardPacts(),
          homeBackend: DashboardBackend(),
          userId: '',
        ),
      ),
    );
    await tester.pumpUi();
    expect(find.text('Step 3 of 4'), findsOneWidget);
    expect(crews.created, 1);
  });
  testWidgets('first crew tile opens link-only invitations', (tester) async {
    final backend = SharingCrew();
    await backend.createCrew(name: 'Early Birds', timezone: 'UTC');
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: Scaffold(
          body: CrewPage(backend: backend, currentUserEmail: ''),
        ),
      ),
    );
    await tester.pumpUi();
    final invite = find.byType(CrewInviteBand);
    final person = find.byType(CrewPersonBand).first;
    // The invite band closes the roster: same width, stacked under the people.
    expect(
      tester.getTopLeft(invite).dy,
      greaterThan(tester.getTopLeft(person).dy),
    );
    expect(tester.getSize(invite).width, tester.getSize(person).width);
    expect(find.text('Invite your people'), findsNothing);
    await tester.tap(invite);
    await tester.pumpUi();
    expect(find.text('Email'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('SEND INVITE'), findsNothing);
    expect(find.text('Share invite link'), findsOneWidget);
    await tester.tap(find.text('Copy invite link'));
    await tester.pumpUi();
    expect(clipboard, inviteUrl('7K2QXM').toString());
    expect(find.text('Link copied'), findsOneWidget);
    // One code per crew: copying again does not mint another.
    await tester.tap(find.text('Link copied'));
    await tester.pumpUi();
    expect(backend.sharing.fetches, 1);
    expect(
      find.text(
        'Share the link, or read out the code. Both work until you reset them.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('the QR code carries the same link and survives large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = Sharing();
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CrewShareControls(
              backend: backend,
              crewId: 'crew',
              crewName: 'Early Birds',
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    await tester.tap(find.text('Show QR code'));
    await tester.pumpUi();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Scan to join your crew'), findsOneWidget);
    await tester.ensureVisible(find.text('Hide QR code'));
    await tester.tap(find.text('Hide QR code'));
    await tester.pumpUi();
    expect(find.byType(QrImageView), findsNothing);
    expect(backend.fetches, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('sharing sends the link and the code, and retries failures', (
    tester,
  ) async {
    final backend = Sharing();
    final share = ShareFake()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CrewShareControls(
              backend: backend,
              crewId: 'crew',
              crewName: 'Early Birds',
              share: share,
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    await tester.tap(find.text('Share invite link'));
    await tester.pumpUi();
    expect(
      find.text('Could not share the link. Please try again.'),
      findsOneWidget,
    );
    share.fail = false;
    await tester.tap(find.text('Share invite link'));
    await tester.pumpUi();
    expect(share.texts.single, contains('/invite/?code=7K2QXM'));
    expect(share.texts.single, contains('Enter the code 7K2QXM'));
    expect(share.texts.single, contains('Early Birds'));
    // Members share; only the owner can reset.
    expect(find.textContaining('Reset code'), findsNothing);
  });
  testWidgets('the owner can reset the code, and the old one goes', (
    tester,
  ) async {
    final backend = Sharing();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CrewShareControls(
              backend: backend,
              crewId: 'crew',
              crewName: 'Early Birds',
              isOwner: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    expect(find.text('7'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Reset code'));
    await tester.tap(find.textContaining('Reset code'));
    await tester.pumpUi();
    expect(backend.resets, 1);
    expect(find.text('7'), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });
}
