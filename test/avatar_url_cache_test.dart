import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/avatar_url_cache.dart';

void main() {
  test(
    'minute refreshes reuse URLs; renew near expiry and retry failures',
    () async {
      var now = DateTime.utc(2026, 9, 11);
      final cache = AvatarUrlCache(now: () => now);
      var calls = 0;
      var fail = false;
      Future<Map<String, String>> resolve() => cache.resolve(
        account: 'user',
        key: 'crew',
        paths: ['a/avatar.png'],
        sign: (paths, ttl) async {
          expect(ttl, 300);
          calls++;
          if (fail) throw Exception('offline');
          return {for (final path in paths) path: 'signed-$calls'};
        },
      );
      expect((await resolve()).values.single, 'signed-1');
      for (var i = 0; i < 4; i++) {
        now = now.add(const Duration(minutes: 1));
        expect((await resolve()).values.single, 'signed-1');
      }
      expect(calls, 1);
      now = now.add(const Duration(seconds: 31));
      fail = true;
      expect((await resolve()).values.single, 'signed-1');
      fail = false;
      expect((await resolve()).values.single, 'signed-3');
      now = now.add(const Duration(minutes: 6));
      fail = true;
      expect(await resolve(), isEmpty);
    },
  );

  test(
    'new paths and account/crew changes cannot reuse stale entries',
    () async {
      final cache = AvatarUrlCache();
      final batches = <List<String>>[];
      Future<Map<String, String>> load(String scope, List<String> paths) =>
          cache.resolve(
            account: scope.split(':').first,
            key: scope.split(':').last,
            paths: paths,
            sign: (missing, _) async {
              batches.add(missing);
              return {for (final path in missing) path: '$scope/$path'};
            },
          );
      await load('user:crew', ['a']);
      await load('user:crew', ['a', 'b']);
      expect(batches, [
        ['a'],
        ['b'],
      ]);
      expect((await load('other:crew', ['a']))['a'], 'other:crew/a');
      expect(batches.last, ['a']);
      // Crews signed together keep their own URLs: the fan asks for every
      // crew's faces at once, and the second reply must not empty the first.
      expect((await load('other:second', ['b']))['b'], 'other:second/b');
      expect((await load('other:crew', ['a']))['a'], 'other:crew/a');
      expect(batches.length, 4);
    },
  );

  test('crews signed at the same time each keep their own URLs', () async {
    final cache = AvatarUrlCache();
    final gates = {
      'first': Completer<Map<String, String>>(),
      'second': Completer<Map<String, String>>(),
    };
    Future<Map<String, String>> load(String crew, String path) => cache.resolve(
      account: 'user',
      key: crew,
      paths: [path],
      sign: (missing, _) => gates[crew]!.future,
    );
    // The fan deals every crew at once, so both are in flight together.
    final first = load('first', 'a/avatar.png');
    final second = load('second', 'b/avatar.png');
    gates['second']!.complete({'b/avatar.png': 'signed-b'});
    gates['first']!.complete({'a/avatar.png': 'signed-a'});
    expect((await first)['a/avatar.png'], 'signed-a');
    expect((await second)['b/avatar.png'], 'signed-b');
  });
}
