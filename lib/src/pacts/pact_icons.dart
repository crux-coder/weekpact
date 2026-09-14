import 'package:hugeicons/styles/stroke_rounded.dart';

class PactIcon {
  const PactIcon(this.key, this.label, this.data, this.keywords);
  final String key;
  final String label;
  final List<List<dynamic>> data;
  final String keywords;

  static const all = <PactIcon>[
    PactIcon('target', 'Target', HugeIconsStrokeRounded.target01, 'pact focus'),
    PactIcon(
      'book',
      'Reading',
      HugeIconsStrokeRounded.bookOpen01,
      'read study learn',
    ),
    PactIcon(
      'strength',
      'Strength',
      HugeIconsStrokeRounded.dumbbell01,
      'gym workout exercise',
    ),
    PactIcon(
      'walk',
      'Walking',
      HugeIconsStrokeRounded.walking,
      'steps outdoors',
    ),
    PactIcon(
      'run',
      'Running',
      HugeIconsStrokeRounded.runningShoes,
      'jog cardio',
    ),
    PactIcon('cycle', 'Cycling', HugeIconsStrokeRounded.bicycle, 'bike cardio'),
    PactIcon('sleep', 'Sleep', HugeIconsStrokeRounded.sleeping, 'rest bedtime'),
    PactIcon(
      'yoga',
      'Yoga',
      HugeIconsStrokeRounded.yoga01,
      'stretch meditate mindfulness',
    ),
    PactIcon(
      'food',
      'Nutrition',
      HugeIconsStrokeRounded.salad,
      'eat vegetables healthy cooking',
    ),
    PactIcon(
      'music',
      'Music',
      HugeIconsStrokeRounded.musicNote01,
      'practice instrument',
    ),
    PactIcon(
      'art',
      'Art',
      HugeIconsStrokeRounded.paintBrush01,
      'draw paint creative',
    ),
    PactIcon(
      'code',
      'Coding',
      HugeIconsStrokeRounded.sourceCode,
      'program learn computer',
    ),
    PactIcon(
      'plant',
      'Gardening',
      HugeIconsStrokeRounded.plant01,
      'nature grow plants',
    ),
    PactIcon(
      'savings',
      'Savings',
      HugeIconsStrokeRounded.moneySavingJar,
      'money budget finance',
    ),
  ];

  static PactIcon find(String key) =>
      all.firstWhere((icon) => icon.key == key, orElse: () => all.first);
}
