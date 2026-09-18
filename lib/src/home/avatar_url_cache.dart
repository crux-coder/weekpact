/// Reuses short-lived avatar URLs so a dashboard refresh keeps the image cache.
class AvatarUrlCache {
  AvatarUrlCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const lifetimeSeconds = 300;

  /// How many keys keep their URLs at once. The fan asks for every crew's
  /// faces in one go, so a handful of crews plus the one the page is showing
  /// all have to fit; past that the least recently asked for is dropped.
  static const _keys = 12;

  final DateTime Function() _now;

  /// One bucket per key, most recently asked for last. Keeping them apart is
  /// what lets several crews be in flight together: a reply that lands second
  /// fills its own bucket instead of emptying the first one's.
  final _buckets = <String, Map<String, ({String url, DateTime expires})>>{};
  String? _account;

  Future<Map<String, String>> resolve({
    required String? account,
    required String key,
    required List<String> paths,
    required Future<Map<String, String>> Function(List<String>, int) sign,
  }) async {
    // Nothing signed for one account may be handed to the next.
    if (_account != account) {
      _buckets.clear();
      _account = account;
    }
    final entries = _buckets.remove(key) ?? {};
    _buckets[key] = entries;
    while (_buckets.length > _keys) {
      _buckets.remove(_buckets.keys.first);
    }
    final started = _now();
    entries.removeWhere(
      (path, entry) => !paths.contains(path) || !entry.expires.isAfter(started),
    );
    final missing = paths.toSet().where((path) {
      final entry = entries[path];
      return entry == null ||
          !entry.expires.isAfter(started.add(const Duration(seconds: 30)));
    }).toList();
    if (missing.isNotEmpty) {
      try {
        final urls = await sign(missing, lifetimeSeconds);
        // An older request must not refill another account's cache.
        if (_account != account) return {};
        for (final path in missing) {
          final url = urls[path];
          if (url != null) {
            entries[path] = (
              url: url,
              expires: started.add(const Duration(seconds: lifetimeSeconds)),
            );
          }
        }
      } catch (_) {
        // Keep still-valid images during a transient storage failure.
      }
    }
    if (_account != account) return {};
    final now = _now();
    return {
      for (final path in paths)
        if (entries[path] case final entry? when entry.expires.isAfter(now))
          path: entry.url,
    };
  }
}
