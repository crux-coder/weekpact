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
        scope: 'user:crew',
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
            scope: scope,
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
    },
  );
}
