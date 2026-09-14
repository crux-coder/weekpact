import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../sharing/app_share.dart';
import '../theme/weekpact_theme.dart';

class WeeklyRecap {
  const WeeklyRecap({
    required this.weekStart,
    required this.checkIns,
    required this.activeMembers,
    required this.completedPacts,
    required this.totalPacts,
    required this.earned,
    this.seen = false,
  });
  final String weekStart;
  final int checkIns, activeMembers, completedPacts, totalPacts;
  final bool earned, seen;
  factory WeeklyRecap.fromJson(Map<String, dynamic> row) => WeeklyRecap(
    weekStart: row['week_start'] as String,
    checkIns: row['check_ins'] as int,
    activeMembers: row['active_members'] as int,
    completedPacts: row['completed_pacts'] as int,
    totalPacts: row['total_pacts'] as int,
    earned: row['earned'] as bool,
    seen: row['seen'] as bool? ?? false,
  );
}

abstract interface class RecapBackend {
  Future<WeeklyRecap?> fetchRecap(String crewId, {String? markSeen});
}

class SupabaseRecapBackend implements RecapBackend {
  const SupabaseRecapBackend(this.client);
  final SupabaseClient client;
  @override
  Future<WeeklyRecap?> fetchRecap(String crewId, {String? markSeen}) async {
    final data = await client.rpc(
      'weekly_recap',
      params: {'p_crew': crewId, 'p_seen': markSeen},
    );
    return data == null
        ? null
        : WeeklyRecap.fromJson(Map<String, dynamic>.from(data as Map));
  }
}

class WeeklyRecapPage extends StatefulWidget {
  const WeeklyRecapPage({
    super.key,
    required this.recap,
    this.share = const NativeAppShare(),
  });
  final WeeklyRecap recap;
  final AppShare share;
  @override
  State<WeeklyRecapPage> createState() => _WeeklyRecapPageState();
}

class _WeeklyRecapPageState extends State<WeeklyRecapPage> {
  final _capture = GlobalKey();
  bool _sharing = false;
  String? _error;
  Future<void> _share(BuildContext anchor) async {
    if (_sharing) return;
    final origin = shareOrigin(anchor);
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      final boundary =
          _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 3);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      if (bytes == null) throw StateError('Could not create image');
      await widget.share.image(bytes.buffer.asUint8List(), origin);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not share your recap. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your week, together')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RepaintBoundary(
                  key: _capture,
                  child: RecapShareCard(recap: widget.recap),
                ),
                const SizedBox(height: 20),
                Text(
                  'Just the shared wins. Names, photos, and your crew name stay private.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.muted),
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (anchor) => FilledButton.icon(
                    onPressed: _sharing ? null : () => _share(anchor),
                    icon: const Icon(Icons.ios_share),
                    label: Text(_sharing ? 'Preparing…' : 'Share this week'),
                  ),
                ),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: context.errorInk)),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Let’s make another good week'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// This is the entire exported image; no surrounding account/crew UI is captured.
class RecapShareCard extends StatelessWidget {
  const RecapShareCard({super.key, required this.recap});
  final WeeklyRecap recap;
  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(recap.weekStart);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final end = date.add(const Duration(days: 6));
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: WeekPactColors.mintGreen,
        borderRadius: BorderRadius.circular(24),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'RobotoCondensed',
          color: WeekPactColors.black,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WeekPact.',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 28),
            Text(
              '${months[date.month - 1]} ${date.day} – ${months[end.month - 1]} ${end.day}',
              style: const TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 14),
            Text(
              recap.checkIns > 0
                  ? 'Look what we\ndid together.'
                  : 'A fresh week.\nA little possibility.',
              style: const TextStyle(
                fontSize: 39,
                fontWeight: FontWeight.bold,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              '${recap.checkIns}',
              style: const TextStyle(
                fontSize: 78,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
            Text(
              recap.checkIns == 1 ? 'check-in together' : 'check-ins together',
              style: const TextStyle(fontSize: 23),
            ),
            const SizedBox(height: 24),
            Text(
              '${recap.completedPacts} ${recap.completedPacts == 1 ? 'pact' : 'pacts'} completed · ${recap.activeMembers} ${recap.activeMembers == 1 ? 'person' : 'people'} showed up',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 24),
            const Divider(color: Color(0x3047623B)),
            const SizedBox(height: 12),
            Text(
              recap.earned
                  ? 'A crew streak earned. Every small step counted.'
                  : 'Every small step counts. Here’s to the next one.',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            const Text(
              'Good habits. Great company.',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
