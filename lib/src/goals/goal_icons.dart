import 'package:hugeicons/styles/stroke_rounded.dart';

class GoalIcon {
  const GoalIcon(this.key, this.label, this.data, this.keywords);
  final String key;
  final String label;
  final List<List<dynamic>> data;
  final String keywords;

  static const all = <GoalIcon>[
    GoalIcon('target', 'Target', HugeIconsStrokeRounded.target01, 'goal focus'),
    GoalIcon(
      'book',
      'Reading',
      HugeIconsStrokeRounded.bookOpen01,
      'read study learn',
    ),
    GoalIcon(
      'strength',
      'Strength',
      HugeIconsStrokeRounded.dumbbell01,
      'gym workout exercise',
    ),
    GoalIcon(
      'walk',
      'Walking',
      HugeIconsStrokeRounded.walking,
      'steps outdoors',
    ),
    GoalIcon(
      'run',
      'Running',
      HugeIconsStrokeRounded.runningShoes,
      'jog cardio',
    ),
    GoalIcon('cycle', 'Cycling', HugeIconsStrokeRounded.bicycle, 'bike cardio'),
    GoalIcon('sleep', 'Sleep', HugeIconsStrokeRounded.sleeping, 'rest bedtime'),
    GoalIcon(
      'yoga',
      'Yoga',
      HugeIconsStrokeRounded.yoga01,
      'stretch meditate mindfulness',
    ),
    GoalIcon(
      'food',
      'Nutrition',
      HugeIconsStrokeRounded.salad,
      'eat vegetables healthy cooking',
    ),
    GoalIcon(
      'music',
      'Music',
      HugeIconsStrokeRounded.musicNote01,
      'practice instrument',
    ),
    GoalIcon(
      'art',
      'Art',
      HugeIconsStrokeRounded.paintBrush01,
      'draw paint creative',
    ),
    GoalIcon(
      'code',
      'Coding',
      HugeIconsStrokeRounded.sourceCode,
      'program learn computer',
    ),
    GoalIcon(
      'plant',
      'Gardening',
      HugeIconsStrokeRounded.plant01,
      'nature grow plants',
    ),
    GoalIcon(
      'savings',
      'Savings',
      HugeIconsStrokeRounded.moneySavingJar,
      'money budget finance',
    ),
  ];

  static GoalIcon find(String key) =>
      all.firstWhere((icon) => icon.key == key, orElse: () => all.first);
}
